import 'dart:io';
import 'dart:typed_data';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late File live;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('migration-acceptance-');
    live = File('${directory.path}/shop.db');
    final database = sqlite3.open(live.path);
    database.execute(
      'CREATE TABLE evidence(id INTEGER PRIMARY KEY, value BLOB);',
    );
    database.execute('INSERT INTO evidence VALUES (?, ?)', [1, 'original']);
    database.execute('INSERT INTO evidence VALUES (?, ?)', [
      2,
      Uint8List.fromList([0, 1, 255]),
    ]);
    database.execute('PRAGMA user_version=12;');
    database.close();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  MigrationRecovery recovery({Future<void> Function(String)? checkpoint}) =>
      MigrationRecovery(live, targetVersion: 13, checkpoint: checkpoint);

  Future<void> start() async {
    await recovery().prepareForOpen();
    await recovery().markMigrationStarted(from: 12, to: 13);
  }

  void commitSchema() {
    final database = sqlite3.open(live.path);
    database.execute(
      'ALTER TABLE evidence ADD COLUMN extra TEXT; PRAGMA user_version=13;',
    );
    database.close();
  }

  Future<void> checkSchema() async {
    final database = sqlite3.open(live.path, mode: OpenMode.readOnly);
    try {
      expect(
        database.select('PRAGMA table_info(evidence)').map((r) => r['name']),
        contains('extra'),
      );
    } finally {
      database.close();
    }
  }

  List<Object?> evidence() {
    final database = sqlite3.open(live.path, mode: OpenMode.readOnly);
    try {
      return database
          .select('SELECT value FROM evidence ORDER BY id')
          .map((row) => row['value'])
          .toList();
    } finally {
      database.close();
    }
  }

  for (final missing in [true, false]) {
    test(
      'unfinished migration recovers original records with missing=$missing',
      () async {
        await start();
        if (missing) {
          await live.delete();
        } else {
          await live.writeAsString('partial corrupt header');
        }
        await expectLater(
          recovery().prepareForOpen(),
          throwsA(isA<DatabaseMigrationFailed>()),
        );
        expect(evidence().first, 'original');
        final restored = await live.readAsBytes();
        await expectLater(
          recovery().prepareForOpen(),
          throwsA(isA<DatabaseMigrationFailed>()),
        );
        expect(await live.readAsBytes(), restored);
        expect(await File('${recovery().marker.path}.failed').exists(), isTrue);
      },
    );
  }

  test(
    'a second interruption during rollback cannot create an empty shop',
    () async {
      await start();
      await expectLater(
        recovery(
          checkpoint: (phase) async {
            if (phase == 'restore-live-removed') {
              throw StateError('simulated termination');
            }
          },
        ).prepareForOpen(),
        throwsStateError,
      );
      expect(await live.exists(), isFalse);
      await expectLater(
        recovery().prepareForOpen(),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      expect(evidence().first, 'original');
    },
  );

  test('reaching user_version does not clear the acceptance barrier', () async {
    await start();
    commitSchema();
    await recovery().prepareForOpen();
    expect(await recovery().marker.exists(), isTrue);
    expect(await File('${recovery().marker.path}.migrating').exists(), isTrue);
    await recovery().finalizeIfSuccessful(13, validateSchema: checkSchema);
    expect(await recovery().marker.exists(), isFalse);
  });

  test(
    'physically healthy database with a missing receipt/document is rejected',
    () async {
      await start();
      commitSchema();
      final database = sqlite3.open(live.path);
      database.execute(
        "DELETE FROM evidence WHERE id=1; INSERT INTO evidence VALUES(3, 'replacement', NULL);",
      );
      expect(database.select('PRAGMA quick_check').single.values.single, 'ok');
      database.close();
      await expectLater(
        recovery().finalizeIfSuccessful(13, validateSchema: checkSchema),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      expect(await recovery().marker.exists(), isTrue);
      expect(
        await File('${recovery().marker.path}.accepted').exists(),
        isFalse,
      );
    },
  );

  test(
    'schema rejection also keeps pending metadata and original snapshot',
    () async {
      await start();
      commitSchema();
      await expectLater(
        recovery().finalizeIfSuccessful(
          13,
          validateSchema: () async {
            throw const FormatException('missing required trigger');
          },
        ),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      expect(await recovery().pendingSnapshot(), isNotNull);
      expect(await recovery().marker.exists(), isTrue);
    },
  );

  for (final phase in ['accepted', 'cleanup:.migrating', 'cleanup:']) {
    test(
      'accepted upgrade preserves subsequent writes after interruption at $phase',
      () async {
        await start();
        commitSchema();
        await expectLater(
          recovery(
            checkpoint: (actual) async {
              if (actual == phase) throw StateError('simulated termination');
            },
          ).finalizeIfSuccessful(13, validateSchema: checkSchema),
          throwsStateError,
        );
        expect(
          await File('${recovery().marker.path}.accepted').exists(),
          isTrue,
        );
        final database = sqlite3.open(live.path);
        database.execute(
          "INSERT INTO evidence VALUES(3, 'after-acceptance', NULL)",
        );
        database.close();
        await recovery().prepareForOpen();
        await recovery().prepareForOpen();
        expect(evidence(), contains('after-acceptance'));
        expect(await recovery().marker.exists(), isFalse);
        expect(
          await File('${recovery().marker.path}.accepted').exists(),
          isFalse,
        );
      },
    );
  }

  test(
    'accepted but corrupt live data is never replaced with a stale snapshot',
    () async {
      await start();
      commitSchema();
      await expectLater(
        recovery(
          checkpoint: (phase) async {
            if (phase == 'accepted') throw StateError('simulated termination');
          },
        ).finalizeIfSuccessful(13, validateSchema: checkSchema),
        throwsStateError,
      );
      await live.writeAsString('accepted data now needs support');
      await expectLater(
        recovery().prepareForOpen(),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      expect(await live.readAsString(), 'accepted data now needs support');
    },
  );

  test('changed snapshot never overwrites the current file', () async {
    await start();
    final snapshot = await recovery().pendingSnapshot();
    await snapshot!.writeAsString('changed snapshot');
    final current = await live.readAsBytes();
    await expectLater(
      recovery().prepareForOpen(),
      throwsA(isA<DatabaseMigrationFailed>()),
    );
    expect(await live.readAsBytes(), current);
  });

  test(
    'migration cannot reset an identifier sequence even when its last row was deleted',
    () async {
      final initial = sqlite3.open(live.path);
      initial.execute(
        'CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT); INSERT INTO history(id) VALUES(1000); DELETE FROM history;',
      );
      initial.close();
      await start();
      commitSchema();
      final changed = sqlite3.open(live.path);
      changed.execute("UPDATE sqlite_sequence SET seq=1 WHERE name='history'");
      changed.close();
      await expectLater(
        recovery().finalizeIfSuccessful(13, validateSchema: checkSchema),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      expect(await recovery().marker.exists(), isTrue);
    },
  );

  test(
    'support exports a verified failed snapshot across known target versions without altering originals',
    () async {
      await start();
      await expectLater(
        recovery().prepareForOpen(),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      final original = await live.readAsBytes();
      final failed = File('${recovery().marker.path}.failed');
      final metadata = await failed.readAsString();
      final exported = await MigrationRecovery(
        live,
        targetVersion: 16,
      ).exportVerifiedRecovery(Directory('${directory.path}/support'));
      final copy = sqlite3.open(exported.path, mode: OpenMode.readOnly);
      expect(
        copy.select('SELECT value FROM evidence WHERE id=1').single['value'],
        'original',
      );
      expect(copy.select('PRAGMA user_version').single.values.single, 12);
      copy.close();
      expect(await live.readAsBytes(), original);
      expect(await failed.readAsString(), metadata);
      expect(
        await Directory('${exported.parent.path}/evidence').exists(),
        isTrue,
      );
      await expectLater(
        MigrationRecovery(live, targetVersion: 16).prepareForOpen(),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
    },
  );

  test('support cannot discard writes made after a failed upgrade', () async {
    await start();
    await expectLater(
      recovery().prepareForOpen(),
      throwsA(isA<DatabaseMigrationFailed>()),
    );
    final database = sqlite3.open(live.path);
    database.execute("INSERT INTO evidence VALUES(3,'newer data')");
    database.close();
    await expectLater(
      recovery().exportVerifiedRecovery(Directory('${directory.path}/support')),
      throwsFormatException,
    );
    expect(await Directory('${directory.path}/support').exists(), isFalse);
    expect(evidence(), contains('newer data'));
  });
}
