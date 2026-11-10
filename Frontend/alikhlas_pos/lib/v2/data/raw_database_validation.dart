import 'dart:async';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import '../core/money.dart';
import 'database_contract_history.dart';
import 'database_contract_sql.dart';
import 'database_reference_contracts.dart';
import 'database_posting_sql.dart';
import 'operation_receipt_codec.dart';
import 'migration_validation.dart';

typedef RawDatabaseReader =
    FutureOr<List<Map<String, Object?>>> Function(
      String sql,
      List<Object?> arguments,
    );

/// Codes and object names only: financial and personal values never enter logs.
class DatabaseContractViolation extends FormatException {
  DatabaseContractViolation(this.code, this.object)
    : super('Database contract: $code ($object)');
  final String code, object;
}

RawDatabaseReader sqliteReader(sqlite.Database database) =>
    (sql, arguments) => database
        .select(sql, arguments)
        .map((row) => Map<String, Object?>.from(row))
        .toList();

/// Reads storage classes before any generated row mapping or arithmetic.
/// A historical version requires only columns/tables introduced by that version.
Future<void> validateRawDatabase(
  RawDatabaseReader read,
  GeneratedDatabase model, {
  required int version,
  bool checkRelationships = true,
}) async {
  void reject(String code, String object) =>
      throw DatabaseContractViolation(code, object);
  if (version < 3 || version > model.schemaVersion) {
    reject('unsupported-version', 'schema');
  }
  final quick = await read('PRAGMA quick_check;', []);
  if (quick.length != 1 || quick.single.values.single != 'ok') {
    reject('physical-integrity', 'schema');
  }
  final present = (await read(
    "SELECT name FROM sqlite_master WHERE type='table'",
    [],
  )).map((r) => r['name']).toSet();
  final availableColumns = <String, Set<Object?>>{};
  for (final table in model.allTables) {
    final name = table.actualTableName;
    if ((tableIntroduced[name] ?? 3) > version) continue;
    if (!present.contains(name)) reject('missing-table', name);
    final quoted = quoteDatabaseIdentifier(name);
    final columns = await read('PRAGMA table_info($quoted)', []);
    final byName = {for (final c in columns) c['name']: c};
    availableColumns[name] = byName.keys.toSet();
    for (final column in table.$columns) {
      if ((columnIntroduced['$name.${column.$name}'] ??
              tableIntroduced[name] ??
              3) >
          version) {
        continue;
      }
      final actual = byName[column.$name];
      if (actual == null) reject('missing-column', '$name.${column.$name}');
      final integer =
          column.type == DriftSqlType.int ||
          column.type == DriftSqlType.bool ||
          column.type == DriftSqlType.dateTime;
      final storage = integer ? 'integer' : 'text';
      if ((actual!['type'] as String).toLowerCase() != storage) {
        reject('declared-type', '$name.${column.$name}');
      }
      final q = quoteDatabaseIdentifier(column.$name);
      final bad = column.$nullable
          ? "($q IS NOT NULL AND typeof($q) != '$storage')"
          : "typeof($q) != '$storage'";
      if ((await read(
        'SELECT 1 FROM $quoted WHERE $bad LIMIT 1',
        [],
      )).isNotEmpty) {
        reject('storage-type', '$name.${column.$name}');
      }
      if (column.type == DriftSqlType.bool &&
          (await read(
            'SELECT 1 FROM $quoted WHERE $q NOT IN (0,1) LIMIT 1',
            [],
          )).isNotEmpty) {
        reject('boolean', '$name.${column.$name}');
      }
      if (!column.$nullable && actual['notnull'] != 1 && actual['pk'] == 0) {
        reject('nullability', '$name.${column.$name}');
      }
    }
    final keys = columns
        .where((c) => (c['pk'] as int) > 0)
        .map((c) => c['name'])
        .toSet();
    final expected = table.$primaryKey.map((c) => c.$name).toSet();
    if (keys.length != expected.length || !keys.containsAll(expected)) {
      reject('primary-key', name);
    }
    final fks = await read('PRAGMA foreign_key_list($quoted)', []);
    for (final fk in declaredForeignKeys[name] ?? <List<String>>[]) {
      if (!fks.any(
        (r) =>
            r['from'] == fk[0] &&
            r['table'] == fk[1] &&
            r['to'] == fk[2] &&
            r['on_update'] == 'NO ACTION' &&
            r['on_delete'] == 'NO ACTION',
      )) {
        reject('foreign-key-contract', name);
      }
    }
    final indices = await read('PRAGMA index_list($quoted)', []);
    for (final unique in declaredUniqueKeys[name] ?? <List<String>>[]) {
      var found = false;
      for (final index in indices.where(
        (r) => r['unique'] == 1 && r['partial'] == 0,
      )) {
        final fields = await read(
          'PRAGMA index_info(${quoteDatabaseIdentifier(index['name'] as String)})',
          [],
        );
        if (fields.map((r) => r['name']).join('|') == unique.join('|')) {
          found = true;
        }
      }
      if (!found) reject('unique-contract', name);
    }
  }
  if ((await read('PRAGMA foreign_key_check', [])).isNotEmpty) {
    reject('foreign-key-data', 'schema');
  }
  Future<void> none(String table, String predicate, String code) async {
    if (present.contains(table) &&
        (await read(
          'SELECT 1 FROM ${quoteDatabaseIdentifier(table)} WHERE $predicate LIMIT 1',
          [],
        )).isNotEmpty) {
      reject(code, table);
    }
  }

  for (final table in model.allTables) {
    final name = table.actualTableName;
    final available = availableColumns[name];
    if (available == null) continue;
    for (final predicate in schema14Predicates[name] ?? <String>[]) {
      final words = RegExp(
        r'\b[a-z_]+\b',
      ).allMatches(predicate).map((m) => m[0]).toSet();
      final missing = table.$columns.any(
        (c) => words.contains(c.$name) && !available.contains(c.$name),
      );
      if (!missing) await none(name, predicate, 'value-contract');
    }
  }
  for (final table in [
    'sale_items',
    'purchase_items',
    'sale_return_items',
    'purchase_return_items',
  ]) {
    await none(table, 'qty <= 0', 'quantity');
  }
  await none(
    'products',
    'stock_qty < 0 OR min_stock_qty < 0 OR sale_price_minor <= 0 OR avg_cost_minor < 0',
    'product-values',
  );
  if (version >= 10) {
    await none(
      'products',
      'inventory_value_minor < 0 OR (stock_qty=0 AND inventory_value_minor != 0)',
      'inventory-value',
    );
  } else {
    // Never let SQLite promote an overflowing int64 product to REAL.
    for (final spec in [
      ['products', 'stock_qty', 'avg_cost_minor'],
      ['sale_items', 'qty', 'unit_cost_minor'],
      ['sale_return_items', 'qty', 'unit_cost_minor'],
    ]) {
      for (final row in await read(
        'SELECT ${spec[1]} AS quantity, ${spec[2]} AS cost FROM ${spec[0]}',
        [],
      )) {
        checkedMinor(
          BigInt.from(row['quantity'] as int) * BigInt.from(row['cost'] as int),
        );
      }
    }
  }
  await none(
    'shifts',
    "status NOT IN ('open','closed') OR opening_cash_minor < 0 OR actual_cash_minor < 0",
    'shift-values',
  );
  if ((await read(
    "SELECT 1 FROM shifts WHERE status='open' LIMIT 1 OFFSET 1",
    [],
  )).isNotEmpty) {
    reject('multiple-open-shifts', 'shifts');
  }
  for (final table in ['sale_invoices', 'purchase_invoices']) {
    for (final row in await read(
      'SELECT total_minor,paid_minor,remaining_minor FROM $table',
      [],
    )) {
      final total = BigInt.from(row['total_minor'] as int);
      final paid = BigInt.from(row['paid_minor'] as int);
      final remaining = BigInt.from(row['remaining_minor'] as int);
      if (total < BigInt.zero ||
          paid < BigInt.zero ||
          remaining < BigInt.zero ||
          paid + remaining != total) {
        reject('invoice-issuance-total', table);
      }
    }
  }
  for (final table in [
    'sale_items',
    'purchase_items',
    'sale_return_items',
    'purchase_return_items',
  ]) {
    final money = model.allTables
        .firstWhere((t) => t.actualTableName == table)
        .$columns
        .where(
          (c) =>
              c.$name.endsWith('_minor') &&
              (columnIntroduced['$table.${c.$name}'] ??
                      tableIntroduced[table] ??
                      3) <=
                  version,
        );
    if (money.isEmpty) continue;
    await none(
      table,
      money.map((c) => '${quoteDatabaseIdentifier(c.$name)} < 0').join(' OR '),
      'negative-item-money',
    );
  }
  await none(
    'ledger_lines',
    'debit_minor < 0 OR credit_minor < 0 OR (debit_minor > 0 AND credit_minor > 0)',
    'ledger-line-values',
  );
  if (version >= 16) {
    await none(
      'ledger_entries',
      "posting_state!='posted'",
      'stray-ledger-draft',
    );
  }
  if (!checkRelationships) return;
  // BigInt aggregates avoid SQL SUM overflow and cancelling aggregate errors.
  final totals = <int, ({BigInt debit, BigInt credit, int count})>{};
  for (final row in await read(
    'SELECT entry_id,debit_minor,credit_minor FROM ledger_lines',
    [],
  )) {
    final id = row['entry_id'] as int;
    final before =
        totals[id] ?? (debit: BigInt.zero, credit: BigInt.zero, count: 0);
    totals[id] = (
      debit: before.debit + BigInt.from(row['debit_minor'] as int),
      credit: before.credit + BigInt.from(row['credit_minor'] as int),
      count: before.count + 1,
    );
  }
  for (final row in await read('SELECT id FROM ledger_entries', [])) {
    final sum = totals[row['id']];
    if (sum == null ||
        sum.count < 2 ||
        sum.debit <= BigInt.zero ||
        sum.debit != sum.credit ||
        sum.debit > maxMoneyMinor) {
      reject('ledger-balance', 'ledger_entries');
    }
  }
  if ((await read(
    'SELECT 1 FROM installment_plans GROUP BY owner_type,owner_id HAVING COUNT(*)>1 LIMIT 1',
    [],
  )).isNotEmpty) {
    reject('duplicate-plan', 'installment_plans');
  }
  if (version >= 7 &&
      (await read(
        'SELECT 1 FROM opening_balances GROUP BY balance_type,party_id HAVING COUNT(*)>1 LIMIT 1',
        [],
      )).isNotEmpty) {
    reject('duplicate-opening', 'opening_balances');
  }
  Future<void> references(
    String table,
    String type,
    String id,
    Map<String, String> targets,
  ) async {
    if (!present.contains(table)) return;
    final valid = validReference(
      'source',
      type,
      id,
      targets,
      existingTables: present.cast<String>(),
    );
    if ((await read(
      'SELECT 1 FROM $table source WHERE NOT ($valid) LIMIT 1',
      [],
    )).isNotEmpty) {
      reject('polymorphic-reference', table);
    }
  }

  await references(
    'ledger_entries',
    'reference_type',
    'reference_id',
    ledgerReferences,
  );
  await references(
    'stock_movements',
    'reference_type',
    'reference_id',
    movementReferences,
  );
  await references('payments', 'owner_type', 'owner_id', paymentOwners);
  await references('installment_plans', 'owner_type', 'owner_id', planOwners);
  await references(
    'installment_plans',
    'party_type',
    'party_id',
    partyReferences,
  );
  await none(
    'ledger_lines',
    invalidLedgerAccount('ledger_lines'),
    'ledger-account-party',
  );
  if ((await read(
    "SELECT 1 FROM ledger_entries WHERE reference_type!='installment_payment' GROUP BY reference_type,reference_id HAVING COUNT(*)>1 LIMIT 1",
    [],
  )).isNotEmpty) {
    reject('duplicate-document-posting', 'ledger_entries');
  }
  final quantities = <int, BigInt>{};
  final currentQuantities = <int, BigInt>{};
  for (final row in await read('SELECT id,stock_qty FROM products', [])) {
    currentQuantities[row['id'] as int] = BigInt.from(row['stock_qty'] as int);
  }
  for (final row in await read(
    'SELECT product_id,qty_delta,balance_after FROM stock_movements ORDER BY id',
    [],
  )) {
    final id = row['product_id'] as int;
    final delta = BigInt.from(row['qty_delta'] as int);
    final balance = BigInt.from(row['balance_after'] as int);
    final prior = quantities[id] ?? (balance - delta);
    if (prior < BigInt.zero ||
        prior > maxMoneyMinor ||
        prior + delta != balance) {
      reject('stock-movement-chain', 'stock_movements');
    }
    quantities[id] = balance;
  }
  for (final row in quantities.entries) {
    if (row.value != currentQuantities[row.key]) {
      reject('stock-current-quantity', 'products');
    }
  }
  // No-movement historical opening stock is exposed by dataIntegrityAudit;
  // it is not silently invented or erased by a migration.
  for (final spec in [
    [
      'sale_return_items',
      'sale_returns',
      'sale_items',
      'sale_id',
      'sale_item_id',
    ],
    [
      'purchase_return_items',
      'purchase_returns',
      'purchase_items',
      'purchase_id',
      'purchase_item_id',
    ],
  ]) {
    if (!present.contains(spec[0])) continue;
    final bad = await read(
      'SELECT 1 FROM ${spec[0]} r JOIN ${spec[1]} h ON h.id=r.return_id JOIN ${spec[2]} i ON i.id=r.${spec[4]} WHERE i.${spec[3]} != h.${spec[3]} OR i.product_id != r.product_id LIMIT 1',
      [],
    );
    if (bad.isNotEmpty) reject('return-source-mismatch', spec[0]);
    final returned = <int, BigInt>{};
    for (final row in await read(
      'SELECT ${spec[4]} AS original,qty FROM ${spec[0]}',
      [],
    )) {
      final id = row['original'] as int;
      returned[id] =
          (returned[id] ?? BigInt.zero) + BigInt.from(row['qty'] as int);
    }
    for (final row in await read('SELECT id,qty FROM ${spec[2]}', [])) {
      if ((returned[row['id']] ?? BigInt.zero) >
          BigInt.from(row['qty'] as int)) {
        reject('return-exceeds-original', spec[0]);
      }
    }
  }

  for (final spec in [
    ['sale', 'sale_invoices', 'customer', 'customer_id'],
    ['purchase', 'purchase_invoices', 'supplier', 'supplier_id'],
  ]) {
    final invalid = await read(
      "SELECT 1 FROM installment_plans p WHERE p.owner_type='${spec[0]}' AND NOT EXISTS(SELECT 1 FROM ${spec[1]} i WHERE i.id=p.owner_id AND p.party_type='${spec[2]}' AND p.party_id=i.${spec[3]}) LIMIT 1",
      [],
    );
    if (invalid.isNotEmpty) reject('plan-owner-party', 'installment_plans');
  }
  if (version >= 7) {
    final invalid = await read(
      "SELECT 1 FROM installment_plans p WHERE p.owner_type='opening_balance' AND NOT EXISTS(SELECT 1 FROM opening_balances b WHERE b.id=p.owner_id AND b.party_id=p.party_id AND ((b.balance_type='customerReceivable' AND p.party_type='customer') OR (b.balance_type='supplierPayable' AND p.party_type='supplier'))) LIMIT 1",
      [],
    );
    if (invalid.isNotEmpty) reject('plan-owner-party', 'installment_plans');
  }

  for (final spec in [
    ['sale', 'sale_invoices', 'sale_items', 'sale_id', 'unit_price_minor'],
    [
      'purchase',
      'purchase_invoices',
      'purchase_items',
      'purchase_id',
      'unit_cost_minor',
    ],
  ]) {
    final lines = <int, BigInt>{};
    for (final row in await read(
      'SELECT ${spec[3]} AS owner,qty,${spec[4]} AS unit,line_total_minor FROM ${spec[2]}',
      [],
    )) {
      final extended =
          BigInt.from(row['qty'] as int) * BigInt.from(row['unit'] as int);
      checkedMinor(extended);
      if (extended != BigInt.from(row['line_total_minor'] as int)) {
        reject('invoice-line-total', spec[2]);
      }
      final id = row['owner'] as int;
      lines[id] = (lines[id] ?? BigInt.zero) + extended;
    }
    final payments = <int, BigInt>{};
    for (final row in await read(
      "SELECT owner_id,amount_minor FROM payments WHERE owner_type='${spec[0]}' AND method IN ('cash','wallet')",
      [],
    )) {
      final id = row['owner_id'] as int;
      payments[id] =
          (payments[id] ?? BigInt.zero) +
          BigInt.from(row['amount_minor'] as int);
    }
    for (final row in await read('SELECT * FROM ${spec[1]}', [])) {
      final id = row['id'] as int;
      final total = BigInt.from(row['total_minor'] as int);
      final paid = BigInt.from(row['paid_minor'] as int);
      if ((payments[id] ?? BigInt.zero) != paid) {
        reject('invoice-paid-total', spec[1]);
      }
      if (spec[0] == 'sale') {
        final subtotal = BigInt.from(row['subtotal_minor'] as int);
        if ((lines[id] ?? BigInt.zero) != subtotal ||
            total !=
                subtotal -
                    BigInt.from(row['discount_minor'] as int) +
                    BigInt.from(row['interest_minor'] as int)) {
          reject('invoice-total', spec[1]);
        }
      } else if ((lines[id] ?? BigInt.zero) != total) {
        reject('invoice-total', spec[1]);
      }
    }
  }
  final schedules = <int, ({int count, BigInt total})>{};
  for (final row in await read(
    'SELECT plan_id,amount_minor FROM installment_payments',
    [],
  )) {
    final id = row['plan_id'] as int;
    final before = schedules[id] ?? (count: 0, total: BigInt.zero);
    schedules[id] = (
      count: before.count + 1,
      total: before.total + BigInt.from(row['amount_minor'] as int),
    );
  }
  for (final row in await read('SELECT * FROM installment_plans', [])) {
    final principal = BigInt.from(row['principal_minor'] as int);
    final interest = BigInt.from(row['interest_minor'] as int);
    final total = BigInt.from(row['total_minor'] as int);
    final paid = BigInt.from(row['paid_minor'] as int);
    final schedule = schedules[row['id']];
    if (principal < BigInt.zero ||
        interest < BigInt.zero ||
        total > principal + interest ||
        paid < BigInt.zero ||
        paid > total ||
        schedule == null ||
        schedule.total != total ||
        schedule.count != row['installment_count'] ||
        row['status'] != (paid == total ? 'closed' : 'open')) {
      reject('installment-contract', 'installment_plans');
    }
  }

  final accountNets = <String, BigInt>{};
  final partyNets = <String, BigInt>{};
  for (final row in await read(
    'SELECT account_code,party_type,party_id,debit_minor,credit_minor FROM ledger_lines',
    [],
  )) {
    final delta =
        BigInt.from(row['debit_minor'] as int) -
        BigInt.from(row['credit_minor'] as int);
    final account = row['account_code'] as String;
    accountNets[account] = (accountNets[account] ?? BigInt.zero) + delta;
    if (row['party_type'] != null) {
      final key = "$account:${row['party_type']}:${row['party_id']}";
      partyNets[key] = (partyNets[key] ?? BigInt.zero) + delta;
    }
  }
  for (final account in ['sales', 'interest_income', 'payables']) {
    checkedMinor(-(accountNets[account] ?? BigInt.zero));
  }
  for (final net in [...accountNets.values, ...partyNets.values]) {
    checkedMinor(net);
  }

  for (final entry in partyNets.entries) {
    if (entry.key.startsWith('payables:supplier:')) checkedMinor(-entry.value);
  }
  if (version >= 7) {
    await none(
      'opening_balances',
      "(balance_type='customerReceivable' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=opening_balances.party_id)) OR (balance_type='supplierPayable' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=opening_balances.party_id))",
      'opening-party-reference',
    );
  }
  final expectedParty = <String, BigInt>{};
  for (final row in await read(
    'SELECT party_type,party_id,total_minor,paid_minor FROM installment_plans',
    [],
  )) {
    final key = "${row['party_type']}:${row['party_id']}";
    expectedParty[key] =
        (expectedParty[key] ?? BigInt.zero) +
        BigInt.from(row['total_minor'] as int) -
        BigInt.from(row['paid_minor'] as int);
  }
  final actualParty = <String, BigInt>{};
  for (final row in await read(
    "SELECT party_type,party_id,account_code,debit_minor,credit_minor FROM ledger_lines WHERE account_code IN ('receivables','payables')",
    [],
  )) {
    if ((row['account_code'] == 'receivables' &&
            row['party_type'] != 'customer') ||
        (row['account_code'] == 'payables' &&
            row['party_type'] != 'supplier')) {
      reject('party-account', 'ledger_lines');
    }
    final key = "${row['party_type']}:${row['party_id']}";
    final delta =
        BigInt.from(row['debit_minor'] as int) -
        BigInt.from(row['credit_minor'] as int);
    actualParty[key] =
        (actualParty[key] ?? BigInt.zero) +
        (row['party_type'] == 'supplier' ? -delta : delta);
  }
  for (final total in expectedParty.values) {
    checkedMinor(total);
  }
  for (final key in {...expectedParty.keys, ...actualParty.keys}) {
    if ((expectedParty[key] ?? BigInt.zero) !=
        (actualParty[key] ?? BigInt.zero)) {
      reject('party-plan-balance', 'installment_plans');
    }
  }
  if (version >= 14) {
    final baseline = await read(
      'SELECT key,value,source_version FROM migration_baselines',
      [],
    );
    if (baseline.length != 1 ||
        baseline.single['key'] != 'inventory_ledger_delta') {
      reject('baseline-contract', 'migration_baselines');
    }
    final saved = baseline.single;
    final value = BigInt.tryParse(saved['value'] as String);
    final source = saved['source_version'] as int;
    if (value == null ||
        value.toString() != saved['value'] ||
        source < 3 ||
        source > version ||
        (source >= 14 && value != BigInt.zero)) {
      reject('baseline-contract', 'migration_baselines');
    }
    var held = BigInt.zero;
    for (final row in await read(
      'SELECT inventory_value_minor FROM products',
      [],
    )) {
      held += BigInt.from(row['inventory_value_minor'] as int);
    }
    checkedMinor(held);
    var recorded = BigInt.zero;
    for (final row in await read(
      "SELECT debit_minor,credit_minor FROM ledger_lines WHERE account_code='inventory'",
      [],
    )) {
      recorded +=
          BigInt.from(row['debit_minor'] as int) -
          BigInt.from(row['credit_minor'] as int);
    }
    if (recorded - held != value) {
      reject('new-inventory-ledger-variance', 'products');
    }
  }
  if (version >= 15) {
    for (final row in await read('SELECT * FROM operation_receipts', [])) {
      final decoded = decodeOperationReceipt(
        row['receipt_key'] as String,
        row['raw_payload'] as String,
      );
      if (row['status'] == 'blocked') {
        if (row['block_reason'] is! String ||
            (row['block_reason'] as String).isEmpty) {
          reject('receipt-barrier', 'operation_receipts');
        }
        continue;
      }
      if (row['status'] != 'ready' ||
          row['format_version'] != 1 ||
          !decoded.isReady ||
          row['namespace'] != decoded.namespace ||
          row['operation_key'] != decoded.operationKey ||
          row['fingerprint'] != decoded.fingerprint ||
          row['result_kind'] != decoded.resultKind ||
          row['result_value'] != decoded.resultValue ||
          row['block_reason'] != null) {
        reject('receipt-contract', 'operation_receipts');
      }
      final table = receiptResultTables[decoded.resultKind];
      if (table != null &&
          (await read('SELECT 1 FROM $table WHERE id=?', [
            decoded.resultValue,
          ])).isEmpty) {
        reject('receipt-result-reference', 'operation_receipts');
      }
    }
  }
}
