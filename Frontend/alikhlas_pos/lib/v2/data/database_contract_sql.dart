import 'package:drift/drift.dart';
import 'migration_validation.dart';

const schema14Indexes = <String>[
  "CREATE UNIQUE INDEX IF NOT EXISTS idx_single_open_shift ON shifts(status) WHERE status='open'",
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_plan_owner_unique ON installment_plans(owner_type,owner_id)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_opening_party_unique ON opening_balances(balance_type,party_id) WHERE party_id IS NOT NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_opening_liquid_unique ON opening_balances(balance_type) WHERE party_id IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id)',
  'CREATE INDEX IF NOT EXISTS idx_sale_return_items_source ON sale_return_items(sale_item_id)',
  'CREATE INDEX IF NOT EXISTS idx_sale_return_items_return ON sale_return_items(return_id)',
  'CREATE INDEX IF NOT EXISTS idx_purchase_return_items_return ON purchase_return_items(return_id)',
  'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns(sale_id)',
  'CREATE INDEX IF NOT EXISTS idx_sale_invoices_customer ON sale_invoices(customer_id)',
  'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier ON purchase_invoices(supplier_id)',
];

const schema15Indexes = <String>[
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_operation_receipt_identity ON operation_receipts(namespace,operation_key) WHERE namespace IS NOT NULL AND operation_key IS NOT NULL',
];

const schema15Guards = <String>[
  "CREATE TRIGGER IF NOT EXISTS receipt_immutable_update BEFORE UPDATE ON operation_receipts BEGIN SELECT RAISE(ABORT,'Operation receipt is immutable'); END;",
  "CREATE TRIGGER IF NOT EXISTS receipt_immutable_delete BEFORE DELETE ON operation_receipts BEGIN SELECT RAISE(ABORT,'Operation receipt is immutable'); END;",
  "CREATE TRIGGER IF NOT EXISTS receipt_immutable_replace BEFORE INSERT ON operation_receipts WHEN EXISTS(SELECT 1 FROM operation_receipts WHERE receipt_key=NEW.receipt_key OR (namespace=NEW.namespace AND operation_key=NEW.operation_key)) BEGIN SELECT RAISE(ABORT,'Operation receipt is immutable'); END;",
];

// Expressions use only fixed table/column names. Negative liquid balances remain
// valid; a confirmation in the application controls those financial operations.
const schema14Predicates = <String, List<String>>{
  'ledger_entries': ["posting_state NOT IN ('draft','posted')"],
  'operation_receipts': [
    "status NOT IN ('ready','blocked')",
    'format_version!=1',
    "status='ready' AND (namespace IS NULL OR operation_key IS NULL OR fingerprint IS NULL OR result_kind IS NULL OR result_value IS NULL OR result_value<=0 OR block_reason IS NOT NULL)",
    "status='blocked' AND block_reason IS NULL",
  ],
  'products': [
    'stock_qty<0',
    'min_stock_qty<0',
    'sale_price_minor<=0',
    'avg_cost_minor<0',
    'inventory_value_minor<0',
    'stock_qty=0 AND inventory_value_minor!=0',
  ],
  'shifts': [
    "status NOT IN ('open','closed')",
    'opening_cash_minor<0',
    'actual_cash_minor<0',
    'opening_ledger_entry_id<0',
  ],
  'sale_invoices': [
    'subtotal_minor<0',
    'discount_minor<0',
    'interest_minor<0',
    'total_minor<0',
    'paid_minor<0',
    'remaining_minor<0',
  ],
  'purchase_invoices': ['total_minor<0', 'paid_minor<0', 'remaining_minor<0'],
  'sale_items': [
    'qty<=0',
    'unit_price_minor<0',
    'unit_cost_minor<0',
    'cost_minor<0',
    'line_total_minor<0',
  ],
  'purchase_items': ['qty<=0', 'unit_cost_minor<0', 'line_total_minor<0'],
  'sale_return_items': [
    'qty<=0',
    'unit_price_minor<0',
    'unit_cost_minor<0',
    'cost_minor<0',
  ],
  'purchase_return_items': [
    'qty<=0',
    'unit_cost_minor<0',
    'inventory_unit_cost_minor<0',
  ],
  'payments': [
    'amount_minor<=0',
    "method NOT IN ('cash','wallet','installment')",
  ],
  'expenses': ['amount_minor<=0', "method NOT IN ('cash','wallet')"],
  'installment_plans': [
    'principal_minor<0',
    'interest_minor<0',
    'total_minor<0',
    'paid_minor<0',
    'paid_minor>total_minor',
    'installment_count<=0',
    "status NOT IN ('open','closed')",
  ],
  'installment_payments': [
    'amount_minor<0',
    "status NOT IN ('pending','partial','paid')",
  ],
  'sale_returns': ['refund_minor<0'],
  'purchase_returns': ['credit_minor<0'],
  'stock_movements': ['balance_after<0'],
  'inventory_adjustments': [
    'value_delta_minor=-9223372036854775808',
    'previous_qty<0',
    'counted_qty<0',
    'unit_cost_minor<0',
  ],
  'opening_balances': [
    "balance_type IN ('cash','wallet') AND (party_id IS NOT NULL OR due_date IS NOT NULL)",
    "balance_type IN ('customerReceivable','supplierPayable') AND (party_id IS NULL OR due_date IS NULL)",
    'amount_minor<=0',
    "balance_type NOT IN ('cash','wallet','customerReceivable','supplierPayable')",
  ],
  'financial_corrections': [
    'delta_minor=-9223372036854775808',
    'delta_minor=0',
    "target NOT IN ('cash','wallet')",
  ],
  'ledger_lines': [
    'debit_minor<0',
    'credit_minor<0',
    'debit_minor>0 AND credit_minor>0',
  ],
  'checkout_drafts': [
    'revision<=0',
    "kind NOT IN ('sale','purchase')",
    "state NOT IN ('editing','suspended','submitting')",
  ],
};

const openingPartyInvalid =
    "(NEW.balance_type='customerReceivable' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.party_id)) OR (NEW.balance_type='supplierPayable' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.party_id))";
final schema14ReferenceGuards = [
  for (final event in ['INSERT', 'UPDATE'])
    "CREATE TRIGGER IF NOT EXISTS opening_party_${event.toLowerCase()} BEFORE $event ON opening_balances WHEN $openingPartyInvalid BEGIN SELECT RAISE(ABORT,'Invalid opening party'); END;",
];

List<String> schema14Guards(GeneratedDatabase model) {
  final result = <String>[];
  for (final table in model.allTables) {
    final name = table.actualTableName;
    final invalid = <String>[];
    for (final column in table.$columns) {
      final field = 'NEW.${quoteDatabaseIdentifier(column.$name)}';
      final integer =
          column.type == DriftSqlType.int ||
          column.type == DriftSqlType.dateTime ||
          column.type == DriftSqlType.bool;
      final check = "typeof($field) != '${integer ? 'integer' : 'text'}'";
      invalid.add(column.$nullable ? '($field IS NOT NULL AND $check)' : check);
      if (column.type == DriftSqlType.bool) invalid.add('$field NOT IN (0,1)');
    }
    for (final predicate in schema14Predicates[name] ?? <String>[]) {
      invalid.add(
        predicate.replaceAllMapped(RegExp(r'\b[a-z_]+\b'), (m) {
          final word = m[0]!;
          return table.$columns.any((c) => c.$name == word)
              ? 'NEW.$word'
              : word;
        }),
      );
    }
    if (table.$columns.any(
      (column) => column.$name == 'id' && column.hasAutoIncrement,
    )) {
      // BEFORE INSERT uses -1 for an unspecified rowid. Test only the resolved
      // identity here, so preserved historical -1 rows cannot block auto ids.
      result.add(
        "CREATE TRIGGER IF NOT EXISTS identity_sentinel_$name AFTER INSERT ON ${quoteDatabaseIdentifier(name)} WHEN NEW.id=-1 BEGIN SELECT RAISE(ABORT,'Reserved implicit identity'); END;",
      );
    }
    for (final event in ['INSERT', 'UPDATE']) {
      result.add(
        "CREATE TRIGGER IF NOT EXISTS contract_${name}_${event.toLowerCase()} BEFORE $event ON ${quoteDatabaseIdentifier(name)} WHEN ${invalid.map((s) => '($s)').join(' OR ')} BEGIN SELECT RAISE(ABORT,'Invalid storage or value contract'); END;",
      );
    }
  }
  for (final event in ['UPDATE', 'DELETE']) {
    result.add(
      "CREATE TRIGGER IF NOT EXISTS migration_baseline_${event.toLowerCase()} BEFORE $event ON migration_baselines BEGIN SELECT RAISE(ABORT,'Historical baseline is immutable'); END;",
    );
  }
  result.add(
    "CREATE TRIGGER IF NOT EXISTS migration_baseline_replace BEFORE INSERT ON migration_baselines WHEN EXISTS(SELECT 1 FROM migration_baselines WHERE key=NEW.key) BEGIN SELECT RAISE(ABORT,'Historical baseline is immutable'); END;",
  );
  return result;
}
