import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';

void main() {
  testWidgets('completed acceptance can be read from tester runAsync zone', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1 AS value').getSingle();
      final value = await tester.runAsync(
        () async => (await db.customSelect('SELECT 2 AS value').getSingle())
            .data['value'],
      );
      expect(value, 2);
    } finally {
      await db.close();
    }
  });
  test(
    'acceptance failure stays closed for concurrent writes, retry and another zone',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-gate-');
      final file = File('${dir.path}/shop.db');
      final seed = AppDatabase(NativeDatabase(file));
      await seed.customSelect('SELECT 1').get();
      await seed.close();
      final initial = sql.sqlite3.open(file.path);
      initial.execute(
        "INSERT INTO app_settings(key,value) VALUES ('evidence','original'); PRAGMA user_version=15",
      );
      initial.close();
      final recovery = MigrationRecovery(file, targetVersion: 16);
      await recovery.prepareForOpen();
      await recovery.markMigrationStarted(from: 15, to: 16);
      final changed = sql.sqlite3.open(file.path);
      changed.execute(
        "DELETE FROM app_settings WHERE key='evidence'; PRAGMA user_version=16",
      );
      changed.close();
      final db = AppDatabase(NativeDatabase(file));
      Future<Object?> capture(Future<void> Function() action) async {
        try {
          await action();
          return null;
        } catch (e) {
          return e;
        }
      }

      try {
        final errors = await Future.wait([
          capture(
            () => db.customStatement(
              "INSERT INTO app_settings VALUES ('write-one','bad')",
            ),
          ),
          capture(
            () => db.transaction(
              () => db.customStatement(
                "INSERT INTO app_settings VALUES ('write-two','bad')",
              ),
            ),
          ),
        ]);
        expect(errors, everyElement(isA<DatabaseMigrationFailed>()));
        final retry = await runZoned(
          () => capture(
            () => db.customStatement(
              "INSERT INTO app_settings VALUES ('write-three','bad')",
            ),
          ),
        );
        expect(retry, isA<DatabaseMigrationFailed>());
        final reader = sql.sqlite3.open(file.path, mode: sql.OpenMode.readOnly);
        try {
          expect(
            reader.select(
              "SELECT 1 FROM app_settings WHERE key LIKE 'write-%'",
            ),
            isEmpty,
          );
        } finally {
          reader.close();
        }
        expect(await recovery.marker.exists(), true);
        expect(await File('${recovery.marker.path}.accepted').exists(), false);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
