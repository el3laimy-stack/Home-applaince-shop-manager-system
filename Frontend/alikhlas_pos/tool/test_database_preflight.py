"""Real SQLite diagnostic tests, NOT Flutter or historical migration fixtures.

Run: python3 -m unittest discover -s tool -p 'test_database_preflight.py' -v
"""

import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

import database_preflight as preflight


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "snapshot.db"
        self.version = 16
        self.make_schema()

    def make_schema(self, version=16):
        self.version = version
        self.path.unlink(missing_ok=True)
        with sqlite3.connect(self.path) as db:
            db.execute(f"PRAGMA user_version={version}")
            for table, spec in preflight.CONTRACT["tables"].items():
                if spec["since"] > version:
                    continue
                columns = []
                for name, column in spec["columns"].items():
                    if column["since"] > version:
                        continue
                    constraints = "" if column["nullable"] else " NOT NULL"
                    if name == "id" or (table == "app_settings" and name == "key"):
                        constraints += " PRIMARY KEY"
                    reference = column.get("references")
                    if reference:
                        constraints += f' REFERENCES {reference["table"]}({reference["column"]})'
                    columns.append(f'"{name}" {column["storage"]}{constraints}')
                db.execute(f'CREATE TABLE "{table}" ({",".join(columns)})')

    def sql(self, sql, parameters=()):
        with sqlite3.connect(self.path) as db:
            db.execute(sql, parameters)

    def insert(self, table, **values):
        row = {}
        for name, rule in preflight.CONTRACT["tables"][table]["columns"].items():
            if rule["since"] <= self.version:
                row[name] = (None if rule["nullable"] else
                             (1 if rule["storage"] == "integer" else "fixture"))
        row.update(values)
        columns = ",".join(f'"{name}"' for name in row)
        self.sql(f'INSERT INTO "{table}" ({columns}) VALUES ({",".join("?" for _ in row)})',
                 tuple(row.values()))

    def report(self):
        return preflight.inspect_snapshot(self.path)

    def codes(self):
        return {issue["code"] for issue in self.report()["issues"]}

    def test_empty_current_shape_is_only_diagnostics_completed(self):
        result = self.report()
        self.assertEqual(result["status"], "diagnostics_completed")
        self.assertEqual(result["issues"], [])
        self.assertIn("not_migration_acceptance", result["scope"])

    def test_inspection_does_not_write_input_or_create_sidecars(self):
        original = self.path.read_bytes()
        files = set(self.path.parent.iterdir())
        self.report()
        self.report()
        self.assertEqual(original, self.path.read_bytes())
        self.assertEqual(files, set(self.path.parent.iterdir()))

    def test_missing_input_is_not_created(self):
        self.path.unlink()
        self.assertEqual(self.codes(), {"snapshot_not_found"})
        self.assertFalse(self.path.exists())

    def test_symlink_loop_does_not_leak_input_path_in_traceback(self):
        loop = self.path.parent / "PRIVATE_PATH_LOOP"
        try:
            loop.symlink_to(loop)
        except (OSError, NotImplementedError):
            self.skipTest("This platform cannot create symlinks")
        result = preflight.inspect_snapshot(loop)
        self.assertEqual(result["status"], "blocked")
        self.assertNotIn("PRIVATE_PATH", json.dumps(result))

    def test_refuses_wal_and_rollback_journal(self):
        for suffix in ("-wal", "-journal"):
            with self.subTest(suffix=suffix):
                sidecar = Path(str(self.path) + suffix)
                sidecar.write_bytes(b"committed evidence")
                self.assertEqual(self.codes(), {"snapshot_has_journal"})
                self.assertEqual(sidecar.read_bytes(), b"committed evidence")
                sidecar.unlink()

    def test_corruption_is_blocked_without_echoing_contents(self):
        self.path.write_bytes(b"private customer and password")
        result = self.report()
        self.assertEqual(result["status"], "blocked")
        self.assertNotIn("private", json.dumps(result))

    def test_unsupported_new_and_unversioned_input(self):
        for version in (0, 2, 17):
            self.sql(f"PRAGMA user_version={version}")
            self.assertEqual(self.codes(), {"unsupported_schema_version"})

    def test_known_legacy_shapes_do_not_require_future_columns(self):
        # Synthetic versioned shape, not evidence of original historical DDL.
        for version in range(3, 17):
            with self.subTest(version=version):
                self.make_schema(version)
                self.assertEqual(self.report()["issues"], [])

    def test_current_ledger_draft_is_reported(self):
        self.insert("ledger_entries", posting_state="draft")
        self.assertIn("unposted_ledger", self.codes())

    def test_current_blocked_receipt_remains_evidence(self):
        self.insert("operation_receipts", receipt_key="operation.future.original", status="blocked",
                    raw_payload="private original", block_reason="unknown", fingerprint=None,
                    namespace=None, operation_key=None, result_kind=None, result_value=None)
        self.assertIn("stored_receipt_barrier", self.codes())
        self.assertNotIn("private original", json.dumps(self.report()))

    def test_missing_table_and_missing_column_block(self):
        self.sql("DROP TABLE purchase_items")
        self.sql("ALTER TABLE products DROP COLUMN inventory_value_minor")
        self.assertIn("missing_or_unsupported_table", self.codes())
        self.assertIn("missing_column", self.codes())

    def test_view_cannot_impersonate_expected_table(self):
        self.sql("DROP TABLE products")
        self.sql("CREATE VIEW products AS SELECT 1 AS id")
        self.assertIn("missing_or_unsupported_table", self.codes())

    def test_integer_affinity_real_and_text_fail_before_arithmetic(self):
        for value in (1.5, "not a number"):
            with self.subTest(value=value):
                self.insert("sale_items", qty=value)
                self.assertIn("storage_type", self.codes())
                self.sql("DELETE FROM sale_items")

    def test_zero_and_negative_quantities(self):
        for table in ("sale_items", "purchase_items", "sale_return_items", "purchase_return_items"):
            self.insert(table, qty=0)
        self.assertEqual(sum(i["code"] == "nonpositive_quantity" for i in self.report()["issues"]), 4)

    def test_duplicate_null_opening_target_and_multiple_open_shifts(self):
        self.insert("opening_balances", id=1, balance_type="cash", party_id=None)
        self.insert("opening_balances", id=2, balance_type="cash", party_id=None)
        self.insert("shifts", id=1, status="open")
        self.insert("shifts", id=2, status="open")
        self.assertIn("duplicate_target", self.codes())
        self.assertIn("multiple_open_shifts", self.codes())

    def test_polymorphic_reference_is_detected_without_sql_fk(self):
        self.insert("payments", owner_type="sale", owner_id=987)
        self.assertIn("orphan_reference", self.codes())
        self.assertNotIn("foreign_keys", self.codes())

    def test_reference_to_document_type_from_future_version_is_blocked(self):
        self.make_schema(3)
        self.insert("ledger_entries", reference_type="opening_balance", reference_id=99)
        self.assertIn("reference_target_unavailable", self.codes())

    def test_receipt_with_target_not_yet_in_this_schema_is_blocked(self):
        self.make_schema(3)
        self.insert("app_settings", key="operation.financial_correction.abc", value=json.dumps(
            {"fingerprint": "unchanged", "id": 7}))
        self.assertIn("receipt_target_unavailable", self.codes())

    def test_declared_foreign_key_violation_is_detected(self):
        self.insert("sale_items", sale_id=456)
        self.assertIn("foreign_keys", self.codes())

    def test_receipt_scalar_count_is_not_looked_up_as_product_id(self):
        self.insert("app_settings", key="operation.product_csv_import.batch", value=json.dumps(
            {"fingerprint": "preserved", "id": 5}))
        self.assertEqual(self.report()["issues"], [])

    def test_receipt_legacy_alias_replays_diagnostic_contract(self):
        self.insert("shifts", id=7, status="closed")
        self.insert("sale_invoices", id=23, customer_id=None, shift_id=7)
        self.insert("app_settings", key="operation.sale.abc", value=json.dumps(
            {"fingerprint": "legacy", "saleId": 23}))
        self.assertNotIn("receipt_result_missing", self.codes())
        self.assertNotIn("unreadable_receipt_barrier", self.codes())

    def test_explicit_null_receipt_id_uses_legacy_alias(self):
        self.insert("purchase_invoices", id=37, supplier_id=None, shift_id=None)
        self.insert("app_settings", key="operation.purchase.abc", value=json.dumps(
            {"fingerprint": "legacy", "id": None, "purchaseId": 37}))
        self.assertNotIn("receipt_result_missing", self.codes())
        self.assertNotIn("unreadable_receipt_barrier", self.codes())

    def test_dotted_namespace_and_missing_receipt_result(self):
        self.insert("app_settings", key="operation.shift.open.key", value=json.dumps(
            {"fingerprint": "preserved", "id": 12}))
        self.assertIn("receipt_result_missing", self.codes())
        self.assertNotIn("unknown_receipt_namespace", self.codes())

    def test_unknown_receipt_is_warning_and_not_discarded(self):
        self.insert("app_settings", key="operation.future.abc", value="secret raw content")
        result = self.report()
        self.assertEqual(result["status"], "diagnostics_completed")
        self.assertIn("unknown_receipt_namespace", self.codes())
        self.assertNotIn("secret raw content", json.dumps(result))

    def test_malformed_and_huge_receipts_are_safe_barriers(self):
        for raw in ("broken", "[]", "null", '{"id":true,"fingerprint":"x"}',
                    json.dumps({"id": 1 << 100, "fingerprint": "x"})):
            with self.subTest(raw=raw):
                self.insert("app_settings", key="operation.sale.abc", value=raw)
                self.assertIn("unreadable_receipt_barrier", self.codes())
                self.assertNotIn("snapshot_unreadable", self.codes())
                self.sql("DELETE FROM app_settings")

    def test_legacy_backfill_overflow_uses_exact_arithmetic(self):
        self.make_schema(9)
        self.insert("products", stock_qty=2, avg_cost_minor=preflight.MAX_INT)
        self.assertIn("legacy_backfill_overflow", self.codes())

    def test_balanced_ledger_does_not_impose_global_reference_uniqueness(self):
        self.insert("products", id=9)
        for entry in (1, 2):
            self.insert("ledger_entries", id=entry, reference_type="opening_stock", reference_id=9)
            self.insert("ledger_lines", id=2*entry, entry_id=entry, account_code="cash", debit_minor=7,
                        credit_minor=0, party_type=None, party_id=None)
            self.insert("ledger_lines", id=2*entry+1, entry_id=entry, account_code="capital", debit_minor=0,
                        credit_minor=7, party_type=None, party_id=None)
        self.assertNotIn("ledger_unbalanced", self.codes())
        self.assertNotIn("duplicate_target", self.codes())

    def test_ledger_accumulates_without_wrapping_int64(self):
        self.insert("products", id=1)
        self.insert("ledger_entries", reference_type="opening_stock", reference_id=1)
        for identity, debit, credit in ((1, preflight.MAX_INT, 0), (2, 1, 0),
                                        (3, 0, preflight.MAX_INT), (4, 0, 1)):
            self.insert("ledger_lines", id=identity, entry_id=1, account_code="cash",
                        debit_minor=debit, credit_minor=credit, party_type=None, party_id=None)
        self.assertIn("ledger_entry_overflow", self.codes())
        self.assertNotIn("ledger_unbalanced", self.codes())

    def test_zero_or_unbalanced_ledger_entry(self):
        self.insert("ledger_entries", reference_type="expense", reference_id=1)
        self.assertIn("ledger_unbalanced", self.codes())

    def test_report_never_echoes_private_names_or_paths(self):
        self.insert("customers", name="PRIVATE_CUSTOMER", phone="PRIVATE_PHONE")
        self.insert("users", username="PRIVATE_USERNAME", password_hash="PRIVATE_HASH")
        text = json.dumps(self.report())
        self.assertNotIn("PRIVATE_", text)
        self.assertNotIn(str(self.path), text)

    def test_cli_preserves_blocked_exit_status_and_input_hash(self):
        self.insert("sale_items", qty=-1)
        digest = hashlib.sha256(self.path.read_bytes()).digest()
        result = subprocess.run([sys.executable, str(Path(preflight.__file__)), "--snapshot", str(self.path)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "blocked")
        self.assertEqual(digest, hashlib.sha256(self.path.read_bytes()).digest())


if __name__ == "__main__":
    unittest.main()
