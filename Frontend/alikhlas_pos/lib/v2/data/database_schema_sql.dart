// Canonical SQL, shared by creation and migration acceptance validation.
const legacyPerformanceIndexes = [
  "CREATE UNIQUE INDEX IF NOT EXISTS idx_one_editing_checkout ON checkout_drafts(kind) WHERE state = 'editing'",
  'CREATE INDEX IF NOT EXISTS idx_checkout_updated ON checkout_drafts(kind, updated_at)',
  'CREATE INDEX IF NOT EXISTS idx_ledger_lines_entry_id ON ledger_lines(entry_id);',
  'CREATE INDEX IF NOT EXISTS idx_ledger_lines_account_code ON ledger_lines(account_code);',
  'CREATE INDEX IF NOT EXISTS idx_ledger_lines_party ON ledger_lines(party_type, party_id);',
  'CREATE INDEX IF NOT EXISTS idx_ledger_entries_created_at ON ledger_entries(created_at);',
  'CREATE INDEX IF NOT EXISTS idx_ledger_entries_reference ON ledger_entries(reference_type, reference_id);',
  'CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON stock_movements(product_id);',
  'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements(reference_type, reference_id);',
  'CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_product_created ON inventory_adjustments(product_id, created_at);',
  'CREATE INDEX IF NOT EXISTS idx_opening_balances_target ON opening_balances(balance_type, party_id);',
  'CREATE INDEX IF NOT EXISTS idx_payments_owner ON payments(owner_type, owner_id);',
  'CREATE INDEX IF NOT EXISTS idx_installment_payments_plan_due ON installment_payments(plan_id, due_date);',
  'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id);',
  'CREATE INDEX IF NOT EXISTS idx_sale_invoices_created_id ON sale_invoices(created_at DESC, id DESC);',
  'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_created_id ON purchase_invoices(created_at DESC, id DESC);',
  'CREATE INDEX IF NOT EXISTS idx_sale_returns_created_at ON sale_returns(created_at);',
  'CREATE INDEX IF NOT EXISTS idx_expenses_created_at ON expenses(created_at);',
  'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);',
  'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);',
  'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(name);',
  'CREATE INDEX IF NOT EXISTS idx_installment_plans_status_created ON installment_plans(status, created_at DESC);',
  'CREATE INDEX IF NOT EXISTS idx_purchase_returns_purchase_id ON purchase_returns(purchase_id);',
  'CREATE INDEX IF NOT EXISTS idx_purchase_return_items_purchase_item_id ON purchase_return_items(purchase_item_id);',
  'CREATE INDEX IF NOT EXISTS idx_financial_corrections_target_created ON financial_corrections(target, created_at);',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_correction_reversals_source ON financial_correction_reversals(correction_id);',
];

const legacyIntegrityGuards = [
  '''
      CREATE TRIGGER IF NOT EXISTS products_nonnegative_insert
      BEFORE INSERT ON products
      WHEN NEW.stock_qty < 0
        OR NEW.min_stock_qty < 0
        OR NEW.sale_price_minor <= 0
        OR NEW.avg_cost_minor < 0
        OR NEW.inventory_value_minor < 0
        OR (NEW.stock_qty = 0 AND NEW.inventory_value_minor != 0)
      BEGIN SELECT RAISE(ABORT, 'Invalid product inventory values'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS products_nonnegative_update
      BEFORE UPDATE OF stock_qty, min_stock_qty, sale_price_minor,
          avg_cost_minor, inventory_value_minor ON products
      WHEN NEW.stock_qty < 0
        OR NEW.min_stock_qty < 0
        OR NEW.sale_price_minor <= 0
        OR NEW.avg_cost_minor < 0
        OR NEW.inventory_value_minor < 0
        OR (NEW.stock_qty = 0 AND NEW.inventory_value_minor != 0)
      BEGIN SELECT RAISE(ABORT, 'Invalid product inventory values'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS shifts_nonnegative_insert
      BEFORE INSERT ON shifts
      WHEN NEW.opening_cash_minor < 0
        OR (NEW.actual_cash_minor IS NOT NULL AND NEW.actual_cash_minor < 0)
      BEGIN SELECT RAISE(ABORT, 'Shift cash cannot be negative'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS shifts_nonnegative_update
      BEFORE UPDATE OF opening_cash_minor, actual_cash_minor ON shifts
      WHEN NEW.opening_cash_minor < 0
        OR (NEW.actual_cash_minor IS NOT NULL AND NEW.actual_cash_minor < 0)
      BEGIN SELECT RAISE(ABORT, 'Shift cash cannot be negative'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS sale_items_positive_quantity
      BEFORE INSERT ON sale_items
      WHEN NEW.qty <= 0
      BEGIN SELECT RAISE(ABORT, 'Sale item quantity must be positive'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS purchase_items_positive_quantity
      BEFORE INSERT ON purchase_items
      WHEN NEW.qty <= 0
      BEGIN SELECT RAISE(ABORT, 'Purchase item quantity must be positive'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS sale_return_items_positive_quantity
      BEFORE INSERT ON sale_return_items
      WHEN NEW.qty <= 0
      BEGIN SELECT RAISE(ABORT, 'Sale return item quantity must be positive'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS purchase_return_items_positive_quantity
      BEFORE INSERT ON purchase_return_items
      WHEN NEW.qty <= 0
      BEGIN SELECT RAISE(ABORT, 'Purchase return item quantity must be positive'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS ledger_lines_valid_insert
      BEFORE INSERT ON ledger_lines
      WHEN NEW.debit_minor < 0
        OR NEW.credit_minor < 0
        OR (NEW.debit_minor > 0 AND NEW.credit_minor > 0)
      BEGIN SELECT RAISE(ABORT, 'Invalid ledger line values'); END;
      ''',
  '''
      CREATE TRIGGER IF NOT EXISTS ledger_lines_valid_update
      BEFORE UPDATE OF debit_minor, credit_minor ON ledger_lines
      WHEN NEW.debit_minor < 0
        OR NEW.credit_minor < 0
        OR (NEW.debit_minor > 0 AND NEW.credit_minor > 0)
      BEGIN SELECT RAISE(ABORT, 'Invalid ledger line values'); END;
      ''',
];
