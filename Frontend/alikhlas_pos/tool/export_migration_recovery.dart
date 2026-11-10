import 'dart:io';
import 'package:alikhlas_pos/v2/data/application_lock.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';

/// Offline export only; does not select a new app data directory or publish.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/export_migration_recovery.dart LIVE_DB EXPORT_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  final live = File(arguments[0]).absolute;
  try {
    await ApplicationLock.acquire(live.parent);
    final copy = await MigrationRecovery(
      live,
      targetVersion: 16,
    ).exportVerifiedRecovery(Directory(arguments[1]));
    stdout.writeln(
      'Verified recovery exported to ${copy.path}. Original files and markers retained.',
    );
  } catch (_) {
    stderr.writeln(
      'Recovery export refused. Keep the original files; no automatic rollback was performed.',
    );
    exitCode = 1;
  } finally {
    await ApplicationLock.release();
  }
}
