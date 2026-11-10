// Real subprocess-kill checks for the recovery protocol. Disposable SQLite
// evidence tables isolate marker boundaries from application schema changes.
// Run: dart run tool/check_migration_process_recovery.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 3 && arguments[0] == '--child') {
    await child(arguments[1], Directory(arguments[2]));
    return;
  }
  for (final phase in ['accepted', 'restore-live-removed']) {
    final root = await Directory.systemTemp.createTemp(
      'migration-process-$phase-',
    );
    try {
      final process = await Process.start('dart', [
        'run',
        Platform.script.toFilePath(),
        '--child',
        phase,
        root.path,
      ]);
      final ready = Completer<void>();
      final output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'PAUSE:$phase' && !ready.isCompleted) ready.complete();
          });
      final errors = process.stderr.drain<void>();
      try {
        await ready.future.timeout(const Duration(seconds: 45));
        if (!process.kill(ProcessSignal.sigkill)) {
          throw StateError('Could not kill recovery child');
        }
        await process.exitCode.timeout(const Duration(seconds: 30));
      } finally {
        process.kill();
        await output.cancel();
        await errors;
      }
      final file = File('${root.path}/shop.db');
      final recovery = MigrationRecovery(file, targetVersion: 13);
      if (phase == 'accepted') {
        await recovery.prepareForOpen();
        final raw = sqlite3.open(file.path);
        raw.execute(
          "INSERT INTO evidence VALUES (2,'new operational write',NULL)",
        );
        raw.close();
        await recovery.prepareForOpen();
        final check = sqlite3.open(file.path);
        if (check.select('SELECT id FROM evidence ORDER BY id').length != 2) {
          throw StateError('Accepted history rolled back');
        }
        check.close();
        if (await recovery.marker.exists()) {
          throw StateError('Accepted cleanup incomplete');
        }
      } else {
        if (await file.exists()) {
          throw StateError('Child did not stop at live-removal boundary');
        }
        try {
          await recovery.prepareForOpen();
          throw StateError('Expected failed migration refusal');
        } on DatabaseMigrationFailed {
          // Expected refusal after recovering the verified original.
        }
        final raw = sqlite3.open(file.path);
        if (raw.select('PRAGMA user_version').single.values.single != 12 ||
            raw.select('SELECT value FROM evidence').single.values.single !=
                'original') {
          throw StateError('Interrupted recovery lost the original');
        }
        raw.close();
        if (!await recovery.marker.exists()) {
          throw StateError('Failure evidence disappeared');
        }
      }
      stdout.writeln(
        'PASS: SIGKILL at $phase preserves the required recovery state',
      );
    } finally {
      await root.delete(recursive: true);
    }
  }
}

Future<void> child(String phase, Directory root) async {
  final file = File('${root.path}/shop.db');
  final raw = sqlite3.open(file.path);
  raw.execute(
    "CREATE TABLE evidence(id INTEGER PRIMARY KEY,value TEXT NOT NULL); INSERT INTO evidence VALUES (1,'original'); PRAGMA user_version=12",
  );
  raw.close();
  final recovery = MigrationRecovery(
    file,
    targetVersion: 13,
    checkpoint: (at) async {
      if (at == phase) {
        stdout.writeln('PAUSE:$phase');
        await stdout.flush();
        await ReceivePort().first;
      }
    },
  );
  await recovery.prepareForOpen();
  await recovery.markMigrationStarted(from: 12, to: 13);
  if (phase == 'accepted') {
    final changed = sqlite3.open(file.path);
    changed.execute(
      'ALTER TABLE evidence ADD COLUMN extra TEXT; PRAGMA user_version=13',
    );
    changed.close();
    await recovery.finalizeIfSuccessful(
      13,
      validateSchema: () async {
        final current = sqlite3.open(file.path, mode: OpenMode.readOnly);
        try {
          if (!current
              .select('PRAGMA table_info(evidence)')
              .any((r) => r['name'] == 'extra')) {
            throw StateError('Missing column');
          }
        } finally {
          current.close();
        }
      },
    );
  } else {
    await file.writeAsString('interrupted upgrade');
    await recovery.prepareForOpen();
  }
}
