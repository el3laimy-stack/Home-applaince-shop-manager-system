// Run from the Flutter project: dart run tool/check_migration_recovery.dart
// Uses only disposable fixtures; never opens a shop database.
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:alikhlas_pos/v2/data/application_lock.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('verified-recovery-cli-');
  try {
    final live = File('${root.path}/shop.db');
    final raw = sqlite3.open(live.path);
    raw.execute(File('test/fixtures/schema_v13.sql').readAsStringSync());
    raw.execute("INSERT INTO app_settings VALUES ('evidence','original')");
    raw.close();
    final recovery = MigrationRecovery(live, targetVersion: 14);
    await recovery.prepareForOpen();
    await recovery.markMigrationStarted(from: 13, to: 14);
    await live.writeAsString('interrupted migration');
    try {
      await recovery.prepareForOpen();
      throw StateError('Expected failed guard');
    } on DatabaseMigrationFailed {
      // Expected refusal after recovering the verified original.
    }
    final originals = <String, String>{};
    for (final file
        in await root.list().where((f) => f is File).cast<File>().toList()) {
      originals[file.path] = sha256
          .convert(await file.readAsBytes())
          .toString();
    }
    final result = await Process.run('dart', [
      'run',
      'tool/export_migration_recovery.dart',
      live.path,
      '${root.path}/exports',
    ]);
    if (result.exitCode != 0) throw StateError('CLI refused verified fixture');
    final exported = (await Directory(
      '${root.path}/exports',
    ).list().where((f) => f is Directory).cast<Directory>().toList()).single;
    final copy = sqlite3.open(
      '${exported.path}/alikhlas_v2.db',
      mode: OpenMode.readOnly,
    );
    if (copy.select('PRAGMA user_version').single.values.single != 13 ||
        copy
                .select("SELECT value FROM app_settings WHERE key='evidence'")
                .single
                .values
                .single !=
            'original') {
      throw StateError('CLI content mismatch');
    }
    copy.close();
    for (final entry in originals.entries) {
      if (sha256.convert(await File(entry.key).readAsBytes()).toString() !=
          entry.value) {
        throw StateError('Original evidence changed');
      }
    }
    await ApplicationLock.acquire(root);
    final denied = await Process.run('dart', [
      'run',
      'tool/export_migration_recovery.dart',
      live.path,
      '${root.path}/locked-export',
    ]);
    if (denied.exitCode != 1 ||
        await Directory('${root.path}/locked-export').exists()) {
      throw StateError('CLI did not respect application lock');
    }
    await ApplicationLock.release();
    stdout.writeln(
      'PASS: verified separate export, original hashes and markers retained, active process lock enforced',
    );
  } finally {
    await ApplicationLock.release();
    await root.delete(recursive: true);
  }
}
