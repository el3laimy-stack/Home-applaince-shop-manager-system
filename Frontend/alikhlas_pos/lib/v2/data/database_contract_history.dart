// Version origins and declared constraints from original schema history.
const tableIntroduced = <String, int>{
  "migration_baselines": 14,
  "operation_receipts": 15,
  "checkout_drafts": 13,
  "expenses": 4,
  "inventory_adjustments": 6,
  "opening_balances": 7,
  "purchase_returns": 8,
  "purchase_return_items": 8,
  "financial_corrections": 9,
  "financial_correction_reversals": 11,
};
const columnIntroduced = <String, int>{
  "ledger_entries.posting_state": 16,
  "products.image_path": 5,
  "products.inventory_value_minor": 10,
  "shifts.opening_ledger_entry_id": 12,
  "shifts.cash_delta_before_upgrade_minor": 12,
  "sale_items.product_name_snapshot": 12,
  "sale_items.product_barcode_snapshot": 12,
  "sale_items.identity_snapshot_origin": 12,
  "sale_items.cost_minor": 10,
  "purchase_items.product_name_snapshot": 12,
  "purchase_items.product_barcode_snapshot": 12,
  "purchase_items.identity_snapshot_origin": 12,
  "sale_return_items.cost_minor": 10,
};
const declaredForeignKeys = <String, List<List<String>>>{
  "sale_invoices": [
    ["shift_id", "shifts", "id"],
    ["customer_id", "customers", "id"],
  ],
  "sale_items": [
    ["product_id", "products", "id"],
    ["sale_id", "sale_invoices", "id"],
  ],
  "purchase_invoices": [
    ["shift_id", "shifts", "id"],
    ["supplier_id", "suppliers", "id"],
  ],
  "purchase_items": [
    ["product_id", "products", "id"],
    ["purchase_id", "purchase_invoices", "id"],
  ],
  "installment_payments": [
    ["plan_id", "installment_plans", "id"],
  ],
  "sale_returns": [
    ["sale_id", "sale_invoices", "id"],
  ],
  "sale_return_items": [
    ["product_id", "products", "id"],
    ["sale_item_id", "sale_items", "id"],
    ["return_id", "sale_returns", "id"],
  ],
  "stock_movements": [
    ["product_id", "products", "id"],
  ],
  "inventory_adjustments": [
    ["product_id", "products", "id"],
  ],
  "ledger_lines": [
    ["entry_id", "ledger_entries", "id"],
  ],
  "purchase_returns": [
    ["purchase_id", "purchase_invoices", "id"],
  ],
  "purchase_return_items": [
    ["product_id", "products", "id"],
    ["purchase_item_id", "purchase_items", "id"],
    ["return_id", "purchase_returns", "id"],
  ],
  "financial_correction_reversals": [
    ["correction_id", "financial_corrections", "id"],
  ],
};
const declaredUniqueKeys = <String, List<List<String>>>{
  "users": [
    ["username"],
  ],
  "products": [
    ["barcode"],
  ],
  "sale_invoices": [
    ["invoice_no"],
  ],
  "purchase_invoices": [
    ["invoice_no"],
  ],
  "sale_returns": [
    ["return_no"],
  ],
  "purchase_returns": [
    ["return_no"],
  ],
  "financial_correction_reversals": [
    ["correction_id"],
  ],
};
