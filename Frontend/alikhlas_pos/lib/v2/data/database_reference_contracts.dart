// Polymorphic references have explicit, closed namespaces, never a generic FK.
const ledgerReferences = <String, String>{
  'sale': 'sale_invoices',
  'sale_cogs': 'sale_invoices',
  'purchase': 'purchase_invoices',
  'sale_return': 'sale_returns',
  'sale_return_cogs': 'sale_returns',
  'purchase_return': 'purchase_returns',
  'installment_payment': 'installment_plans',
  'expense': 'expenses',
  'opening_stock': 'products',
  'inventory_adjustment': 'inventory_adjustments',
  'opening_balance': 'opening_balances',
  'financial_correction': 'financial_corrections',
  'financial_correction_reversal': 'financial_correction_reversals',
};
const movementReferences = <String, String>{
  'sale': 'sale_invoices',
  'purchase': 'purchase_invoices',
  'sale_return': 'sale_returns',
  'purchase_return': 'purchase_returns',
  'opening_stock': 'products',
  'inventory_adjustment': 'inventory_adjustments',
};
const paymentOwners = <String, String>{
  'sale': 'sale_invoices',
  'purchase': 'purchase_invoices',
  'installment_plan': 'installment_plans',
};
const planOwners = <String, String>{
  'sale': 'sale_invoices',
  'purchase': 'purchase_invoices',
  'opening_balance': 'opening_balances',
};
const partyReferences = <String, String>{
  'customer': 'customers',
  'supplier': 'suppliers',
};

/// Returns a SQL expression true for a valid reference, using only fixed names.
String validReference(
  String alias,
  String type,
  String id,
  Map<String, String> targets, {
  Set<String>? existingTables,
}) => targets.entries
    .where((e) => existingTables == null || existingTables.contains(e.value))
    .map(
      (e) =>
          "($alias.$type='${e.key}' AND EXISTS(SELECT 1 FROM ${e.value} target WHERE target.id=$alias.$id))",
    )
    .join(' OR ');
