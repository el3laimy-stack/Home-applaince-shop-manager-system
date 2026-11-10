import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

String quoteDatabaseIdentifier(String name) =>
    '"${name.replaceAll('"', '""')}"';

/// Compares original records, including their SQLite storage types, rather than
/// trusting user_version or aggregate totals that can hide missing documents.
/// All original columns must survive; new columns/tables are checked separately
/// by the current schema and data contracts before acceptance.
void verifyMigrationPreservesRecords(
  File snapshot,
  File live, {
  required int fromVersion,
  bool allowDraftTransformation = true,
  bool allowAdditionalSchema = true,
}) {
  final before = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
  Database? after;
  try {
    after = sqlite3.open(live.path, mode: OpenMode.readOnly);
    for (final database in [before, after]) {
      database.execute('PRAGMA trusted_schema = OFF;');
      if (database.select('PRAGMA quick_check;').single.values.single != 'ok' ||
          database.select('PRAGMA foreign_key_check;').isNotEmpty) {
        throw const FormatException('Migration integrity validation failed');
      }
    }
    final tables = before.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (!allowAdditionalSchema) {
      final currentTables = after
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((row) => row['name'])
          .toSet();
      final originalTables = tables.map((row) => row['name']).toSet();
      if (currentTables.length != originalTables.length ||
          !currentTables.containsAll(originalTables)) {
        throw const FormatException('Recovery source schema changed');
      }
    }
    for (final table in tables) {
      final name = table['name'] as String;
      final identifier = quoteDatabaseIdentifier(name);
      final columns = before
          .select('PRAGMA table_info($identifier);')
          .map((row) => row['name'] as String)
          .toList();
      if (columns.isEmpty) throw const FormatException('Missing source schema');
      if (!allowAdditionalSchema &&
          after.select('PRAGMA table_info($identifier)').length !=
              columns.length) {
        throw const FormatException('Recovery source columns changed');
      }
      final draftMigration =
          allowDraftTransformation &&
          fromVersion < 13 &&
          name == 'app_settings';
      final expected = _rowHashes(
        before,
        identifier,
        columns,
        skipDrafts: draftMigration,
      );
      final actual = _rowHashes(after, identifier, columns);
      if (expected.length != actual.length ||
          expected.entries.any((entry) => actual[entry.key] != entry.value)) {
        throw const FormatException('Original migration records changed');
      }
      if (draftMigration) {
        for (final kind in ['sale', 'purchase']) {
          final old = before.select(
            'SELECT value FROM app_settings WHERE key=?',
            ['draft.$kind.v1'],
          );
          if (old.isEmpty) continue;
          final moved = after.select(
            'SELECT payload FROM checkout_drafts WHERE id=? AND kind=?',
            ['legacy-$kind', kind],
          );
          if (moved.length != 1 ||
              _encode(old.single['value']) !=
                  _encode(moved.single['payload'])) {
            throw const FormatException('Legacy draft was not preserved');
          }
        }
      }
    }
    if (before
        .select("SELECT 1 FROM sqlite_master WHERE name='sqlite_sequence'")
        .isNotEmpty) {
      for (final row in before.select('SELECT name,seq FROM sqlite_sequence')) {
        final current = after.select(
          'SELECT seq FROM sqlite_sequence WHERE name=?',
          [row['name']],
        );
        if (current.length != 1 ||
            _encode(current.single['seq']) != _encode(row['seq'])) {
          throw const FormatException('Original identifier sequence changed');
        }
      }
    }
  } finally {
    after?.close();
    before.close();
  }
}

Map<String, int> _rowHashes(
  Database database,
  String table,
  List<String> columns, {
  bool skipDrafts = false,
}) {
  final hashes = <String, int>{};
  final statement = database.prepare(
    'SELECT ${columns.map(quoteDatabaseIdentifier).join(',')} FROM $table',
  );
  try {
    final cursor = statement.selectCursor();
    while (cursor.moveNext()) {
      final row = cursor.current;
      if (skipDrafts &&
          {'draft.sale.v1', 'draft.purchase.v1'}.contains(row['key'])) {
        continue;
      }
      final encoded = jsonEncode([
        for (final column in columns) _encode(row[column]),
      ]);
      final hash = sha256.convert(utf8.encode(encoded)).toString();
      hashes.update(hash, (value) => value + 1, ifAbsent: () => 1);
    }
  } finally {
    statement.close();
  }
  return hashes;
}

String _encode(Object? value) => switch (value) {
  null => 'null',
  int() => 'integer:$value',
  double() => 'real:$value',
  String() => 'text:$value',
  List<int>() => 'blob:${base64Encode(value)}',
  _ => throw const FormatException('Unsupported SQLite storage value'),
};
