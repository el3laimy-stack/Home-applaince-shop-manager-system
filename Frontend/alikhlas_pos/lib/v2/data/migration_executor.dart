import 'dart:io';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'database_schema_sql.dart';
import 'database_contract_sql.dart';
import 'database_posting_sql.dart';
import 'migration_recovery.dart';
import 'migration_validation.dart';
import 'raw_database_validation.dart';

/// Drift's beforeOpen runs BEFORE it persists user_version. The interceptor
/// holds ensureOpen until the delegate has finished that work AND acceptance
/// has completed. No application query or transaction can cross this boundary.
class MigrationAcceptanceInterceptor extends QueryInterceptor {
  final _opening = Expando<_AcceptanceState>();

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    if (executor is TransactionExecutor) return executor.ensureOpen(user);
    final state = _opening[executor] ??= _AcceptanceState();
    // A Future belongs to its creation zone. Returning a completed Future from
    // a widget's FakeAsync zone to runAsync can deadlock its new listeners.
    // Preserve the gate while opening; create fresh results after completion.
    if (state.failure case (final error, final stack)) {
      return Future.error(error, stack);
    }
    if (state.result case final bool result) return Future.value(result);
    return state.pending ??= _openAndRemember(executor, user, state);
  }

  Future<bool> _openAndRemember(
    QueryExecutor executor,
    QueryExecutorUser user,
    _AcceptanceState state,
  ) async {
    try {
      final result = await _open(executor, user);
      state.result = result;
      return result;
    } catch (error, stack) {
      state.failure = (error, stack);
      rethrow;
    }
  }

  @override
  Future<void> close(QueryExecutor inner) {
    _opening[inner] = null;
    return inner.close();
  }

  Future<bool> _open(QueryExecutor executor, QueryExecutorUser user) async {
    final opened = await executor.ensureOpen(user);
    final files = await executor.runSelect('PRAGMA database_list;', const []);
    final main = files.where((row) => row['name'] == 'main');
    final path = main.isEmpty ? null : main.single['file'] as String?;
    if (path != null && path.isNotEmpty) {
      if (user is! GeneratedDatabase) {
        throw StateError('Expected generated schema metadata');
      }
      await MigrationRecovery(
        File(path),
        targetVersion: user.schemaVersion,
      ).finalizeIfSuccessful(
        user.schemaVersion,
        validateSchema: () async => validateOpenedSchema(File(path), user),
      );
    }
    return opened;
  }
}

class _AcceptanceState {
  Future<bool>? pending;
  bool? result;
  (Object, StackTrace)? failure;
}

Future<void> validateOpenedSchema(File file, GeneratedDatabase model) async {
  final database = sqlite.sqlite3.open(
    file.path,
    mode: sqlite.OpenMode.readOnly,
  );
  try {
    await validateRawDatabase(
      sqliteReader(database),
      model,
      version: model.schemaVersion,
    );
    for (final table in model.allTables) {
      final columns = database.select(
        'PRAGMA table_info(${quoteDatabaseIdentifier(table.actualTableName)});',
      );
      final names = columns.map((row) => row['name']).toSet();
      if (!table.$columns.every((column) => names.contains(column.$name))) {
        throw StateError('Missing migration schema columns');
      }
      final keys = columns
          .where((row) => (row['pk'] as int) > 0)
          .map((row) => row['name'])
          .toSet();
      final expected = table.$primaryKey.map((column) => column.$name).toSet();
      if (keys.length != expected.length || !keys.containsAll(expected)) {
        throw StateError('Migration primary key mismatch');
      }
    }
    for (final sql in [
      ...legacyPerformanceIndexes,
      ...legacyIntegrityGuards,
      ...schema14Indexes,
      ...schema14ReferenceGuards,
      ...schema15Indexes,
      ...schema15Guards,
      ...schema16Indexes,
      ...schema16Guards(),
      ...schema14Guards(model),
    ]) {
      final name = RegExp(
        r'(?:INDEX|TRIGGER)\s+(?:IF NOT EXISTS\s+)?([a-z0-9_]+)',
        caseSensitive: false,
      ).firstMatch(sql)!.group(1)!;
      final rows = database.select(
        'SELECT sql FROM sqlite_master WHERE name=?',
        [name],
      );
      String normalized(String value) => value
          .toLowerCase()
          .replaceAll('if not exists', '')
          .replaceAll(';', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (rows.length != 1 ||
          normalized(rows.single['sql'] as String) != normalized(sql)) {
        throw StateError('Migration schema object mismatch');
      }
    }
  } finally {
    database.close();
  }
}
