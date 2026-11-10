import 'dart:io';
import 'package:alikhlas_pos/v2/application/backup_file_operations.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class FailPublication extends BackupFileOperations {
  bool fail = true;
  @override
  Future<void> publishFile(File source, File target) async {
    if (fail) {
      fail = false;
      throw FileSystemException('simulated disk failure', target.path);
    }
    await super.publishFile(source, target);
  }
}

class FailFlush extends BackupFileOperations {
  @override
  Future<void> flushFile(File file) async =>
      throw FileSystemException('simulated flush failure', file.path);
}

void main() {
  late Directory directory;
  late AppDatabase db;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('snapshot-publication-');
    db = AppDatabase(NativeDatabase.memory());
    await V2UseCases(db).bootstrap();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'failed publication cannot displace a valid copy or count a partial .db',
    () async {
      final normal = V2UseCases(db);
      final original = await normal.backupToDirectory(directory);
      final originalBytes = await original.readAsBytes();
      final broken = File('${directory.path}/alikhlas-v2-interrupted.db');
      await broken.writeAsString('partial sqlite copy');
      await broken.setLastModified(DateTime(2099));
      await normal.setBackupDirectory(directory.path);
      await db.customStatement(
        "UPDATE app_settings SET value='1' WHERE key='backup.keepCopies'",
      );
      final failing = V2UseCases(db, backupFileOperations: FailPublication());
      await expectLater(
        failing.backupToDirectory(directory),
        throwsA(isA<FileSystemException>()),
      );
      expect(await original.readAsBytes(), originalBytes);
      expect((await directory.list().toList()).whereType<Directory>(), isEmpty);
      final created = await normal.backupToDirectory(directory);
      expect(await original.exists(), isFalse);
      expect(await broken.readAsString(), 'partial sqlite copy');
      final status = (await normal.workbenchSnapshot()).backupStatus;
      expect(status.backupCount, 1);
      expect(status.latestBackupPath, created.path);
    },
  );

  test(
    'healthy SQLite with an incomplete schema cannot displace the published backup',
    () async {
      final uc = V2UseCases(db);
      await db.customStatement(
        "UPDATE app_settings SET value='1' WHERE key='backup.keepCopies'",
      );
      final fake = File('${directory.path}/alikhlas-v2-incomplete.db');
      final raw = sqlite.sqlite3.open(fake.path);
      for (final name in [
        'users',
        'app_settings',
        'products',
        'sale_invoices',
        'sale_items',
        'purchase_invoices',
        'purchase_items',
        'ledger_entries',
        'ledger_lines',
      ]) {
        raw.execute('CREATE TABLE $name(id INTEGER)');
      }
      raw.execute('PRAGMA user_version=13');
      raw.close();
      await fake.setLastModified(DateTime(2099));
      final published = await uc.backupToDirectory(directory);
      expect(await published.exists(), true);
      expect(await fake.exists(), true);
      await uc.setBackupDirectory(directory.path);
      final status = (await uc.workbenchSnapshot()).backupStatus;
      expect(status.backupCount, 1);
      expect(status.latestBackupPath, published.path);
    },
  );

  test(
    'retention always keeps a new backup even if a valid older copy is future dated',
    () async {
      final uc = V2UseCases(db);
      await db.customStatement(
        "UPDATE app_settings SET value='1' WHERE key='backup.keepCopies'",
      );
      final original = await uc.backupToDirectory(directory);
      await original.setLastModified(DateTime(2099));
      final published = await uc.backupToDirectory(directory);
      expect(await published.exists(), true);
      expect(await original.exists(), false);
    },
  );

  test(
    'flush failure never publishes a final filename or advances success',
    () async {
      final uc = V2UseCases(db, backupFileOperations: FailFlush());
      await uc.setBackupDirectory(directory.path);
      expect(await uc.tryAutomaticBackup(), isNull);
      expect(await directory.list().toList(), isEmpty);
      expect(
        (await db.select(db.appSettings).get()).where(
          (row) => row.key == 'backup.lastSuccessAt',
        ),
        isEmpty,
      );
    },
  );

  test(
    'portable failures release busy state and do not leave final/partial files',
    () async {
      final operations = FailPublication();
      final uc = V2UseCases(db, backupFileOperations: operations);
      // First publish is the staged database; fail before any ZIP is published.
      await expectLater(
        uc.createPortableBackup(directory),
        throwsA(isA<FileSystemException>()),
      );
      expect(await directory.list().toList(), isEmpty);
      expect(await (await uc.createPortableBackup(directory)).exists(), isTrue);
    },
  );

  test(
    'portable backups with an identical clock never overwrite each other',
    () async {
      final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 10));
      final first = await uc.createPortableBackup(directory);
      final bytes = await first.readAsBytes();
      final second = await uc.createPortableBackup(directory);
      expect(first.path, isNot(second.path));
      expect(await first.readAsBytes(), bytes);
      expect(await directory.list().length, 2);
    },
  );
}
