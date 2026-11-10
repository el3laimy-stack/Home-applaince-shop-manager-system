import 'dart:io';

/// Isolates best-effort retention cleanup from successful snapshot creation.
/// Tests can simulate a locked old backup without relying on host-specific
/// file-lock behavior.
class BackupFileOperations {
  const BackupFileOperations();

  Future<void> deleteFile(File file) => file.delete();

  Future<void> flushFile(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<void> publishFile(File source, File target) async {
    if (await target.exists()) {
      throw FileSystemException('Backup target already exists', target.path);
    }
    await source.rename(target.path);
  }
}
