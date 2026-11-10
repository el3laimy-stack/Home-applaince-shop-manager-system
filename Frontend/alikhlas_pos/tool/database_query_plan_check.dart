// Structural EXPLAIN checks; full-data timing lives in the scale benchmark.
// Run: flutter test --no-pub tool/database_query_plan_check.dart
import 'dart:convert';
import 'dart:io';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/database_contract_sql.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new owner and return indexes support their lookup predicates', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      Future<List<String>> explain(String sql) async =>
          (await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
              .map((row) => row.data['detail'] as String)
              .toList();
      final result = <String, Object?>{};
      for (final probe in [
        (
          'idx_purchase_items_purchase',
          'SELECT * FROM purchase_items WHERE purchase_id=1',
        ),
        (
          'idx_sale_return_items_return',
          'SELECT * FROM sale_return_items WHERE return_id=1',
        ),
        (
          'idx_purchase_return_items_return',
          'SELECT * FROM purchase_return_items WHERE return_id=1',
        ),
        (
          'idx_sale_invoices_customer',
          'SELECT * FROM sale_invoices WHERE customer_id=1',
        ),
        (
          'idx_purchase_invoices_supplier',
          'SELECT * FROM purchase_invoices WHERE supplier_id=1',
        ),
      ]) {
        await db.customStatement('DROP INDEX ${probe.$1}');
        final before = await explain(probe.$2);
        await db.customStatement(
          schema14Indexes.firstWhere((sql) => sql.contains(probe.$1)),
        );
        final after = await explain(probe.$2);
        expect(after.any((detail) => detail.contains(probe.$1)), true);
        result[probe.$1] = {'before': before, 'after': after};
      }
      result['posted_line_lookup'] = await explain(
        "SELECT * FROM ledger_lines l WHERE l.entry_id=1 AND EXISTS(SELECT 1 FROM ledger_entries e WHERE e.id=l.entry_id AND e.posting_state='posted')",
      );
      final sqlite =
          (await db
                  .customSelect('SELECT sqlite_version() AS version')
                  .getSingle())
              .data['version'];
      final report = const JsonEncoder.withIndent('  ').convert({
        'schema_version': db.schemaVersion,
        'sqlite_version': sqlite,
        'scope':
            'Empty canonical schema; structural access-path check, not runtime performance.',
        'plans': result,
      });
      File('docs/database/query_plans_v16.json').writeAsStringSync('$report\n');
    } finally {
      await db.close();
    }
  });
}
