import 'package:sqlite3/sqlite3.dart';

/// A fixture labelled v11 or older must not retain columns introduced in v12.
void removeV12Columns(Database database) {
  database.execute('DROP INDEX IF EXISTS idx_posted_ledger_created');
  database.execute('DROP INDEX IF EXISTS idx_posted_document_source');
  final modern = database.select(
    "SELECT name FROM sqlite_master WHERE type='trigger'",
  );
  for (final row in modern) {
    database.execute('DROP TRIGGER "${row['name']}"');
  }
  if (database
      .select('PRAGMA table_info(ledger_entries)')
      .any((row) => row['name'] == 'posting_state')) {
    database.execute('ALTER TABLE ledger_entries DROP COLUMN posting_state');
  }
  database.execute('DROP TABLE IF EXISTS migration_baselines');
  if (database
      .select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='operation_receipts'",
      )
      .isNotEmpty) {
    // Reconstruct the old settings receipt storage when manufacturing an old
    // schema from a modern financial fixture; never discard retry evidence.
    database.execute(
      'INSERT OR IGNORE INTO app_settings(key,value) SELECT receipt_key,raw_payload FROM operation_receipts',
    );
  }
  database.execute('DROP TABLE IF EXISTS operation_receipts');
  for (final table in ['sale_items', 'purchase_items']) {
    for (final column in [
      'product_name_snapshot',
      'product_barcode_snapshot',
      'identity_snapshot_origin',
    ]) {
      database.execute('ALTER TABLE $table DROP COLUMN $column');
    }
  }
  database.execute('ALTER TABLE shifts DROP COLUMN opening_ledger_entry_id');
  database.execute(
    'ALTER TABLE shifts DROP COLUMN cash_delta_before_upgrade_minor',
  );
}
