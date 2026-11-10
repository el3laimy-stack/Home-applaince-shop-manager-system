import 'database_reference_contracts.dart';

const schema16Indexes = <String>[
  "CREATE UNIQUE INDEX IF NOT EXISTS idx_posted_document_source ON ledger_entries(reference_type,reference_id) WHERE posting_state='posted' AND reference_type!='installment_payment'",
];
const _postedOld =
    "EXISTS(SELECT 1 FROM ledger_entries WHERE id=OLD.entry_id AND posting_state='posted')";
const _postedNew =
    "EXISTS(SELECT 1 FROM ledger_entries WHERE id=NEW.entry_id AND posting_state='posted')";
const _postedCollision =
    "EXISTS(SELECT 1 FROM ledger_lines l JOIN ledger_entries e ON e.id=l.entry_id WHERE l.id=NEW.id AND e.posting_state='posted')";
const _entryCollision =
    "EXISTS(SELECT 1 FROM ledger_entries WHERE id=NEW.id AND posting_state='posted')";
const _accountInvalid =
    "NEW.account_code NOT IN ('cash','wallet','receivables','payables','inventory','inventory_variance','financial_variance','sales','cogs','expenses','interest_income','capital') OR ((NEW.party_type IS NULL)!=(NEW.party_id IS NULL)) OR (NEW.account_code='receivables' AND (NEW.party_type IS NULL OR NEW.party_type!='customer')) OR (NEW.account_code='payables' AND (NEW.party_type IS NULL OR NEW.party_type!='supplier')) OR (NEW.account_code NOT IN ('receivables','payables') AND NEW.party_type IS NOT NULL) OR (NEW.party_type='customer' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.party_id)) OR (NEW.party_type='supplier' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.party_id)) OR (NEW.party_type IS NOT NULL AND NEW.party_type NOT IN ('customer','supplier'))";

String invalidLedgerAccount(String alias) =>
    _accountInvalid.replaceAll('NEW.', '$alias.');

String _guard(String name, String event, String table, String invalid) =>
    "CREATE TRIGGER IF NOT EXISTS $name BEFORE $event ON $table WHEN $invalid BEGIN SELECT RAISE(ABORT,'Invalid reference or immutable posted history'); END;";

List<String> schema16Guards() {
  final sql = <String>[
    _guard(
      'ledger_entry_insert',
      'INSERT',
      'ledger_entries',
      "NEW.posting_state!='draft' OR (NEW.id!=-1 AND $_entryCollision)",
    ),
    _guard(
      'ledger_entry_update',
      'UPDATE',
      'ledger_entries',
      "OLD.posting_state='posted' OR $_entryCollision OR NEW.posting_state NOT IN ('draft','posted')",
    ),
    _guard(
      'ledger_entry_delete',
      'DELETE',
      'ledger_entries',
      "OLD.posting_state='posted'",
    ),
    _guard(
      'ledger_entry_post',
      'UPDATE OF posting_state',
      'ledger_entries',
      "NEW.posting_state='posted' AND ((SELECT COUNT(*) FROM ledger_lines WHERE entry_id=OLD.id)<2 OR COALESCE((SELECT SUM(debit_minor) FROM ledger_lines WHERE entry_id=OLD.id),0)<=0 OR (SELECT SUM(debit_minor) FROM ledger_lines WHERE entry_id=OLD.id)!=(SELECT SUM(credit_minor) FROM ledger_lines WHERE entry_id=OLD.id))",
    ),
    _guard(
      'ledger_line_insert',
      'INSERT',
      'ledger_lines',
      "$_postedNew OR (NEW.id!=-1 AND $_postedCollision) OR NOT EXISTS(SELECT 1 FROM ledger_entries WHERE id=NEW.entry_id) OR $_accountInvalid",
    ),
    _guard(
      'ledger_line_update',
      'UPDATE',
      'ledger_lines',
      "$_postedOld OR $_postedNew OR $_postedCollision OR NOT EXISTS(SELECT 1 FROM ledger_entries WHERE id=NEW.entry_id) OR $_accountInvalid",
    ),
    _guard('ledger_line_delete', 'DELETE', 'ledger_lines', _postedOld),
  ];
  sql.add(
    _guard(
      'ledger_entry_identity',
      'UPDATE OF id',
      'ledger_entries',
      'NEW.id!=OLD.id AND EXISTS(SELECT 1 FROM ledger_lines WHERE entry_id=OLD.id)',
    ),
  );
  final references =
      <String, ({String type, String id, Map<String, String> targets})>{
        'ledger_entries': (
          type: 'reference_type',
          id: 'reference_id',
          targets: ledgerReferences,
        ),
        'stock_movements': (
          type: 'reference_type',
          id: 'reference_id',
          targets: movementReferences,
        ),
        'payments': (
          type: 'owner_type',
          id: 'owner_id',
          targets: paymentOwners,
        ),
        'installment_plans': (
          type: 'owner_type',
          id: 'owner_id',
          targets: planOwners,
        ),
      };
  for (final source in references.entries) {
    final ref = source.value;
    for (final event in ['INSERT', 'UPDATE']) {
      sql.add(
        _guard(
          'reference_${source.key}_${event.toLowerCase()}',
          event,
          source.key,
          'NOT (${validReference('NEW', ref.type, ref.id, ref.targets)})',
        ),
      );
    }
  }
  for (final event in ['INSERT', 'UPDATE']) {
    sql.add(
      _guard(
        'plan_party_${event.toLowerCase()}',
        event,
        'installment_plans',
        "NOT (${validReference('NEW', 'party_type', 'party_id', partyReferences)}) OR (NEW.owner_type='sale' AND NOT EXISTS(SELECT 1 FROM sale_invoices WHERE id=NEW.owner_id AND customer_id=NEW.party_id AND NEW.party_type='customer')) OR (NEW.owner_type='purchase' AND NOT EXISTS(SELECT 1 FROM purchase_invoices WHERE id=NEW.owner_id AND supplier_id=NEW.party_id AND NEW.party_type='supplier')) OR (NEW.owner_type='opening_balance' AND NOT EXISTS(SELECT 1 FROM opening_balances WHERE id=NEW.owner_id AND party_id=NEW.party_id AND ((balance_type='customerReceivable' AND NEW.party_type='customer') OR (balance_type='supplierPayable' AND NEW.party_type='supplier'))))",
      ),
    );
  }
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
    for (final event in ['INSERT', 'UPDATE']) {
      sql.add(
        _guard(
          'return_source_${spec[0]}_${event.toLowerCase()}',
          event,
          spec[0],
          "NOT EXISTS(SELECT 1 FROM ${spec[1]} h JOIN ${spec[2]} i ON i.${spec[3]}=h.${spec[3]} WHERE h.id=NEW.return_id AND i.id=NEW.${spec[4]} AND i.product_id=NEW.product_id) OR NEW.qty > (SELECT qty FROM ${spec[2]} WHERE id=NEW.${spec[4]}) - COALESCE((SELECT SUM(qty) FROM ${spec[0]} WHERE ${spec[4]}=NEW.${spec[4]} ${event == 'UPDATE' ? 'AND id!=OLD.id' : ''}),0)",
        ),
      );
    }
  }
  // Both source identity updates and deletes must preserve polymorphic links.
  final targets = <String, Set<String>>{};
  for (final source in references.entries) {
    for (final destination in source.value.targets.entries) {
      targets
          .putIfAbsent(destination.value, () => {})
          .add(
            "EXISTS(SELECT 1 FROM ${source.key} WHERE ${source.value.type}='${destination.key}' AND ${source.value.id}=OLD.id)",
          );
    }
  }
  for (final party in partyReferences.entries) {
    targets
        .putIfAbsent(party.value, () => {})
        .add(
          "EXISTS(SELECT 1 FROM ledger_lines WHERE party_type='${party.key}' AND party_id=OLD.id) OR EXISTS(SELECT 1 FROM installment_plans WHERE party_type='${party.key}' AND party_id=OLD.id)",
        );
  }
  const receiptKindsByTable = <String, String>{
    'sale_invoices': 'sale_invoice',
    'purchase_invoices': 'purchase_invoice',
    'sale_returns': 'sale_return',
    'purchase_returns': 'purchase_return',
    'products': 'product',
    'inventory_adjustments': 'inventory_adjustment',
    'opening_balances': 'opening_balance',
    'financial_corrections': 'financial_correction',
    'financial_correction_reversals': 'financial_correction_reversal',
    'expenses': 'expense',
    'ledger_entries': 'ledger_entry',
    'shifts': 'shift',
  };
  for (final receipt in receiptKindsByTable.entries) {
    targets
        .putIfAbsent(receipt.key, () => {})
        .add(
          "EXISTS(SELECT 1 FROM operation_receipts WHERE status='ready' AND result_kind='${receipt.value}' AND result_value=OLD.id)",
        );
  }
  for (final target in targets.entries) {
    final used = target.value.map((s) => '($s)').join(' OR ');
    sql.add(
      _guard(
        'reference_target_${target.key}_delete',
        'DELETE',
        target.key,
        used,
      ),
    );
    sql.add(
      _guard(
        'reference_target_${target.key}_identity',
        'UPDATE OF id',
        target.key,
        'NEW.id!=OLD.id AND ($used)',
      ),
    );
    sql.add(
      _guard(
        'reference_target_${target.key}_replace',
        'INSERT',
        target.key,
        "NEW.id!=-1 AND (${used.replaceAll('OLD.id', 'NEW.id')})",
      ),
    );
  }
  // Financial document bodies become historical once their posting exists.
  const documents = <String, List<String>>{
    'sale_invoices': ['sale', 'sale_cogs'],
    'purchase_invoices': ['purchase'],
    'sale_returns': ['sale_return', 'sale_return_cogs'],
    'purchase_returns': ['purchase_return'],
    'expenses': ['expense'],
    'inventory_adjustments': ['inventory_adjustment'],
    'opening_balances': ['opening_balance'],
    'financial_corrections': ['financial_correction'],
    'financial_correction_reversals': ['financial_correction_reversal'],
  };
  for (final document in documents.entries) {
    final types = document.value.map((s) => "'$s'").join(',');
    final posted =
        "EXISTS(SELECT 1 FROM ledger_entries WHERE reference_type IN ($types) AND reference_id=OLD.id AND posting_state='posted')";
    for (final event in ['UPDATE', 'DELETE']) {
      sql.add(
        _guard(
          'history_${document.key}_${event.toLowerCase()}',
          event,
          document.key,
          posted,
        ),
      );
    }
  }
  for (final spec in [
    ['sale_items', 'sale_id', "'sale','sale_cogs'"],
    ['purchase_items', 'purchase_id', "'purchase'"],
    ['sale_return_items', 'return_id', "'sale_return','sale_return_cogs'"],
    ['purchase_return_items', 'return_id', "'purchase_return'"],
  ]) {
    String posted(String alias) =>
        "EXISTS(SELECT 1 FROM ledger_entries WHERE reference_type IN (${spec[2]}) AND reference_id=$alias.${spec[1]} AND posting_state='posted')";
    final collision =
        "EXISTS(SELECT 1 FROM ${spec[0]} original JOIN ledger_entries e ON e.reference_id=original.${spec[1]} WHERE original.id=NEW.id AND e.reference_type IN (${spec[2]}) AND e.posting_state='posted')";
    sql.add(
      _guard(
        'history_${spec[0]}_insert',
        'INSERT',
        spec[0],
        "${posted('NEW')} OR (NEW.id!=-1 AND $collision)",
      ),
    );
    sql.add(
      _guard(
        'history_${spec[0]}_update',
        'UPDATE',
        spec[0],
        '${posted('OLD')} OR ${posted('NEW')} OR $collision',
      ),
    );
    sql.add(
      _guard('history_${spec[0]}_delete', 'DELETE', spec[0], posted('OLD')),
    );
  }
  for (final table in ['payments', 'stock_movements']) {
    for (final event in ['UPDATE', 'DELETE']) {
      sql.add(
        _guard('history_${table}_${event.toLowerCase()}', event, table, '1'),
      );
    }
    sql.add(
      _guard(
        'history_${table}_replace',
        'INSERT',
        table,
        'NEW.id!=-1 AND EXISTS(SELECT 1 FROM $table WHERE id=NEW.id)',
      ),
    );
  }

  sql.add(
    _guard(
      'history_payment_append',
      'INSERT',
      'payments',
      "(NEW.owner_type='sale' AND EXISTS(SELECT 1 FROM ledger_entries WHERE reference_type IN ('sale','sale_cogs') AND reference_id=NEW.owner_id AND posting_state='posted')) OR (NEW.owner_type='purchase' AND EXISTS(SELECT 1 FROM ledger_entries WHERE reference_type='purchase' AND reference_id=NEW.owner_id AND posting_state='posted'))",
    ),
  );
  sql.add(
    _guard(
      'history_stock_append',
      'INSERT',
      'stock_movements',
      "EXISTS(SELECT 1 FROM ledger_entries WHERE reference_id=NEW.reference_id AND posting_state='posted' AND (reference_type=NEW.reference_type OR (NEW.reference_type='sale' AND reference_type='sale_cogs') OR (NEW.reference_type='sale_return' AND reference_type='sale_return_cogs')))",
    ),
  );
  sql.add(
    _guard(
      'plan_identity_immutable',
      'UPDATE',
      'installment_plans',
      'NEW.owner_type!=OLD.owner_type OR NEW.owner_id!=OLD.owner_id OR NEW.party_type!=OLD.party_type OR NEW.party_id!=OLD.party_id OR NEW.principal_minor!=OLD.principal_minor OR NEW.interest_minor!=OLD.interest_minor OR NEW.installment_count!=OLD.installment_count OR NEW.created_at!=OLD.created_at',
    ),
  );
  return sql;
}
