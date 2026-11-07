import 'package:sqlite3/sqlite3.dart';

/// A fixture labelled v11 or older must not retain columns introduced in v12.
void removeV12Columns(Database database) {
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
