#!/usr/bin/env python3
"""Read-only, aggregate diagnostics for CLOSED database snapshots, versions 3–16.

Never opens the application, migrates a database, repairs rows, or authorizes a
migration. Python's unbounded integers avoid SQLite SUM/multiplication overflow.
Use a snapshot made by the app, not a copy of an open WAL database.
"""

import argparse
from contextlib import closing
import json
from pathlib import Path
import re
import sqlite3


CONTRACT = json.loads(
    (Path(__file__).resolve().parents[1] / "docs/database/schema_contract_v16.json")
    .read_text(encoding="utf-8")
)
MIN_INT, MAX_INT = -(1 << 63), (1 << 63) - 1
ACCOUNTS = {
    "cash", "wallet", "receivables", "payables", "inventory",
    "inventory_variance", "financial_variance", "sales", "cogs", "expenses",
    "interest_income", "capital",
}
RECEIPTS = {
    "sale": ("sale_invoices", "saleId"),
    "purchase": ("purchase_invoices", "purchaseId"),
    "sale_return": ("sale_returns", None),
    "purchase_return": ("purchase_returns", None),
    "opening_stock": ("products", None),
    "inventory_adjustment": ("inventory_adjustments", None),
    "opening_balance": ("opening_balances", None),
    "financial_correction": ("financial_corrections", None),
    "financial_correction_reversal": ("financial_correction_reversals", None),
    "expense": ("expenses", None),
    "installment.customer": ("ledger_entries", None),
    "installment.supplier": ("ledger_entries", None),
    "shift.open": ("shifts", None),
    "shift.close": ("shifts", None),
    "product_csv_import": (None, None),  # Scalar count, NOT a product id.
}
DOCUMENTS = {
    "sale": "sale_invoices", "sale_cogs": "sale_invoices",
    "purchase": "purchase_invoices", "sale_return": "sale_returns",
    "sale_return_cogs": "sale_returns", "purchase_return": "purchase_returns",
    "installment_payment": "installment_plans", "expense": "expenses",
    "opening_stock": "products", "inventory_adjustment": "inventory_adjustments",
    "opening_balance": "opening_balances", "financial_correction": "financial_corrections",
    "financial_correction_reversal": "financial_correction_reversals",
}


def quote(name):
    """Only identifiers from our contract/call sites enter SQL."""
    if not re.fullmatch(r"[a-z_]+", name):
        raise ValueError("Unexpected identifier")
    return f'"{name}"'


class Audit:
    def __init__(self, connection, version):
        self.db, self.version = connection, version
        self.issues, self.columns, self.invalid = [], {}, set()

    def issue(self, code, table=None, column=None, count=1, severity="blocker"):
        # Never report names, numbers, passwords, raw JSON, or database paths.
        if count:
            self.issues.append(dict(code=code, table=table, column=column,
                                    count=count, severity=severity))

    def ready(self, table, *columns):
        return (table in self.columns
                and set(columns) <= self.columns[table]
                and not any((table, c) in self.invalid for c in columns))

    def count(self, sql, parameters=()):
        return self.db.execute(sql, parameters).fetchone()[0]

    def schema_and_types(self):
        tables = {r[0]: r[1] for r in self.db.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='table'")}
        for table, spec in CONTRACT["tables"].items():
            if spec["since"] > self.version:
                continue
            ddl = tables.get(table)
            if ddl is None or re.search(r"\bVIRTUAL\b", ddl, re.I):
                self.issue("missing_or_unsupported_table", table)
                continue
            columns = {r[1] for r in self.db.execute(f"PRAGMA table_info({quote(table)})")}
            self.columns[table] = columns
            for column, rule in spec["columns"].items():
                if rule["since"] > self.version:
                    continue
                if column not in columns:
                    self.issue("missing_column", table, column)
                    continue
                q = quote(column)
                allowed = [rule["storage"]] + (["null"] if rule["nullable"] else [])
                marks = ",".join("?" for _ in allowed)
                count = self.count(
                    f"SELECT count(*) FROM {quote(table)} WHERE typeof({q}) NOT IN ({marks})",
                    allowed)
                self.issue("storage_type", table, column, count)
                if count:
                    self.invalid.add((table, column))
                if rule.get("boolean"):
                    self.issue("boolean_value", table, column, self.count(
                        f"SELECT count(*) FROM {quote(table)} WHERE {q} NOT IN (0,1)"))

    def duplicates(self, table, keys, where="1"):
        if self.ready(table, *keys):
            columns = ",".join(map(quote, keys))
            count = self.count(f"SELECT count(*) FROM (SELECT 1 FROM {quote(table)} "
                               f"WHERE {where} GROUP BY {columns} HAVING count(*)>1)")
            self.issue("duplicate_target", table, count=count)

    def references(self, table, kind, identifier, targets, nullable=False):
        if not self.ready(table, kind, identifier):
            return
        for value, target in targets.items():
            if not self.ready(target, "id"):
                # A target introduced AFTER this version has no schema blocker;
                # a row already claiming that document type must not pass silently.
                self.issue("reference_target_unavailable", table, identifier,
                           self.count(f"SELECT count(*) FROM {quote(table)} "
                                      f"WHERE {quote(kind)}=?", (value,)))
                continue
            count = self.count(
                f"SELECT count(*) FROM {quote(table)} s WHERE s.{quote(kind)}=? "
                f"AND NOT EXISTS (SELECT 1 FROM {quote(target)} t "
                f"WHERE t.id=s.{quote(identifier)})", (value,))
            self.issue("orphan_reference", table, identifier, count)
        marks = ",".join("?" for _ in targets)
        unknown = self.count(
            f"SELECT count(*) FROM {quote(table)} WHERE {quote(kind)} NOT IN ({marks})"
            f" OR ({quote(kind)} IS NULL AND {quote(identifier)} IS NOT NULL)"
            + (f" OR {quote(kind)} IS NULL" if not nullable else ""), tuple(targets))
        self.issue("unknown_reference_type", table, kind, unknown)

    def relations_and_uniqueness(self):
        self.duplicates("installment_plans", ["owner_type", "owner_id"])
        self.duplicates("opening_balances", ["balance_type", "party_id"])
        if self.ready("shifts", "status"):
            self.issue("multiple_open_shifts", "shifts",
                       count=max(0, self.count("SELECT count(*) FROM shifts WHERE status='open'") - 1))
            self.issue("unknown_shift_status", "shifts", count=self.count(
                "SELECT count(*) FROM shifts WHERE status NOT IN ('open','closed')"))
        self.references("payments", "owner_type", "owner_id", {
            "sale": "sale_invoices", "purchase": "purchase_invoices",
            "installment_plan": "installment_plans"})
        self.references("installment_plans", "owner_type", "owner_id", {
            "sale": "sale_invoices", "purchase": "purchase_invoices",
            "opening_balance": "opening_balances"})
        self.references("ledger_entries", "reference_type", "reference_id", DOCUMENTS)
        for table in ("installment_plans", "ledger_lines"):
            self.references(table, "party_type", "party_id", {
                "customer": "customers", "supplier": "suppliers"}, nullable=table == "ledger_lines")
        for prefix in ("sale", "purchase"):
            table = f"{prefix}_return_items"
            headers, items = f"{prefix}_returns", f"{prefix}_items"
            item_id, owner_id = f"{prefix}_item_id", f"{prefix}_id"
            if (self.ready(table, "return_id", item_id, "product_id")
                    and self.ready(headers, "id", owner_id)
                    and self.ready(items, "id", owner_id, "product_id")):
                count = self.count(f"SELECT count(*) FROM {table} r "
                    f"LEFT JOIN {headers} h ON h.id=r.return_id "
                    f"LEFT JOIN {items} i ON i.id=r.{item_id} "
                    f"WHERE h.id IS NULL OR i.id IS NULL "
                    f"OR i.{owner_id}!=h.{owner_id} OR i.product_id!=r.product_id")
                self.issue("return_item_link", table, count=count)

    def quantities_and_backfill(self):
        for table in ("sale_items", "purchase_items", "sale_return_items", "purchase_return_items"):
            if self.ready(table, "qty"):
                self.issue("nonpositive_quantity", table, "qty", self.count(
                    f"SELECT count(*) FROM {table} WHERE qty<=0"))
        if self.version < 10:
            for table, a, b in (("products", "stock_qty", "avg_cost_minor"),
                                ("sale_items", "qty", "unit_cost_minor"),
                                ("sale_return_items", "qty", "unit_cost_minor")):
                if self.ready(table, a, b):
                    count = sum(not MIN_INT <= x*y <= MAX_INT for x, y in self.db.execute(
                        f"SELECT {a},{b} FROM {table}"))
                    self.issue("legacy_backfill_overflow", table, count=count)

    def ledger(self):
        if not (self.ready("ledger_lines", "entry_id", "account_code", "debit_minor", "credit_minor")
                and self.ready("ledger_entries", "id")):
            return
        entries = {r[0]: [0, 0] for r in self.db.execute("SELECT id FROM ledger_entries")}
        invalid, unknown, orphan = 0, 0, 0
        for entry, account, debit, credit in self.db.execute(
                "SELECT entry_id,account_code,debit_minor,credit_minor FROM ledger_lines"):
            invalid += debit < 0 or credit < 0 or (debit > 0 and credit > 0)
            unknown += account not in ACCOUNTS
            if entry not in entries:
                orphan += 1
            else:
                entries[entry][0] += debit
                entries[entry][1] += credit
        self.issue("ledger_line_values", "ledger_lines", count=invalid)
        self.issue("unknown_account", "ledger_lines", "account_code", unknown)
        self.issue("orphan_ledger_line", "ledger_lines", count=orphan)
        self.issue("ledger_unbalanced", "ledger_entries", count=sum(
            debit == 0 or debit != credit for debit, credit in entries.values()))
        self.issue("ledger_entry_overflow", "ledger_entries", count=sum(
            not (MIN_INT <= debit <= MAX_INT and MIN_INT <= credit <= MAX_INT)
            for debit, credit in entries.values()))

    def current_contracts(self):
        if self.version >= 16 and self.ready("ledger_entries", "posting_state"):
            self.issue("unposted_ledger", "ledger_entries", count=self.count(
                "SELECT count(*) FROM ledger_entries WHERE posting_state!='posted'"))
        if self.ready("ledger_lines", "account_code", "debit_minor", "credit_minor"):
            nets = {}
            for account, debit, credit in self.db.execute(
                    "SELECT account_code,debit_minor,credit_minor FROM ledger_lines"):
                nets[account] = nets.get(account, 0) + debit - credit
            self.issue("account_net_overflow", "ledger_lines", count=sum(
                not MIN_INT <= value <= MAX_INT for value in nets.values()))
            self.issue("revenue_sign_overflow", "ledger_lines", count=sum(
                not MIN_INT <= -nets.get(account, 0) <= MAX_INT
                for account in ("sales", "interest_income")))
        if self.version >= 15 and self.ready("operation_receipts", "receipt_key", "status", "raw_payload",
                                             "fingerprint", "result_kind", "result_value"):
            blocked, inconsistent, conflicting = 0, 0, 0
            for key, status, raw, fingerprint, kind, value in self.db.execute(
                    "SELECT receipt_key,status,raw_payload,fingerprint,result_kind,result_value FROM operation_receipts"):
                if status == "blocked":
                    blocked += 1
                    continue
                try:
                    decoded = json.loads(raw)
                    namespace = next((n for n in RECEIPTS if key.startswith(f"operation.{n}.")), None)
                    if namespace is None or not isinstance(decoded, dict):
                        raise ValueError()
                    target, alias = RECEIPTS[namespace]
                    result = decoded.get("id")
                    if result is None and alias is not None:
                        result = decoded.get(alias)
                    if (status != "ready" or type(result) is not int or result < 1
                            or decoded.get("fingerprint") != fingerprint or result != value
                            or (namespace == "product_csv_import" and kind != "scalar_count")):
                        raise ValueError()
                    if self.ready("app_settings", "key", "value"):
                        old = self.db.execute("SELECT value FROM app_settings WHERE key=?", (key,)).fetchone()
                        if old is not None:
                            legacy = json.loads(old[0])
                            old_result = legacy.get("id")
                            if old_result is None and alias is not None:
                                old_result = legacy.get(alias)
                            conflicting += legacy.get("fingerprint") != fingerprint or old_result != value
                except (ValueError, TypeError, AttributeError, RecursionError):
                    inconsistent += 1
            self.issue("stored_receipt_barrier", "operation_receipts", count=blocked, severity="warning")
            self.issue("stored_receipt_contract", "operation_receipts", count=inconsistent)
            self.issue("receipt_source_conflict", "operation_receipts", count=conflicting)

    def receipts(self):
        if not self.ready("app_settings", "key", "value"):
            return
        malformed, unknown, orphan, unavailable = 0, 0, 0, 0
        for key, raw in self.db.execute("SELECT key,value FROM app_settings WHERE key LIKE 'operation.%'"):
            namespace = next((n for n in RECEIPTS if key.startswith(f"operation.{n}.")), None)
            if namespace is None:
                unknown += 1
                continue
            target, legacy = RECEIPTS[namespace]
            try:
                data = json.loads(raw)
                value = data.get("id")
                if value is None and legacy is not None:
                    value = data.get(legacy)  # Dart's ??= also falls back for explicit null.
                if (not isinstance(data.get("fingerprint"), str)
                        or type(value) is not int or not 1 <= value <= MAX_INT):
                    raise ValueError()
            except (ValueError, TypeError, AttributeError, RecursionError):
                malformed += 1
                continue
            if target is not None:
                if self.ready(target, "id"):
                    orphan += not self.count(f"SELECT count(*) FROM {target} WHERE id=?", (value,))
                else:
                    unavailable += 1
        self.issue("unreadable_receipt_barrier", "app_settings", count=malformed)
        self.issue("unknown_receipt_namespace", "app_settings", count=unknown, severity="warning")
        self.issue("receipt_result_missing", "app_settings", count=orphan)
        self.issue("receipt_target_unavailable", "app_settings", count=unavailable)

    def run(self):
        self.schema_and_types()
        self.relations_and_uniqueness()
        self.quantities_and_backfill()
        self.ledger()
        self.receipts()
        self.current_contracts()
        return self.issues


def inspect_snapshot(path):
    report = {"scope": "partial_offline_diagnostics_not_migration_acceptance",
              "schema_version": None, "sqlite_version": sqlite3.sqlite_version,
              "issues": [], "status": "blocked"}
    try:
        path = Path(path).resolve()
        if not path.is_file():
            report["issues"] = [{"code": "snapshot_not_found", "severity": "blocker"}]
            return report
        # immutable mode intentionally ignores WAL: reject sidecars rather than
        # produce a false report on committed transactions absent from the DB file.
        if any(Path(str(path) + suffix).exists() for suffix in ("-wal", "-journal")):
            report["issues"] = [{"code": "snapshot_has_journal", "severity": "blocker"}]
            return report
    except (OSError, RuntimeError):
        report["issues"] = [{"code": "snapshot_unreadable", "severity": "blocker"}]
        return report
    try:
        with closing(sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)) as db:
            db.execute("PRAGMA query_only=ON")
            db.execute("PRAGMA trusted_schema=OFF")
            db.execute("BEGIN")
            if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                report["issues"] = [{"code": "sqlite_integrity", "severity": "blocker"}]
                return report
            version = db.execute("PRAGMA user_version").fetchone()[0]
            report["schema_version"] = version
            if not CONTRACT["minimum_diagnostic_version"] <= version <= CONTRACT["schema_version"]:
                report["issues"] = [{"code": "unsupported_schema_version", "severity": "blocker"}]
                return report
            report["issues"] = Audit(db, version).run()
            count = sum(1 for _ in db.execute("PRAGMA foreign_key_check"))
            if count:
                report["issues"].append(dict(code="foreign_keys", count=count, severity="blocker"))
            report["status"] = ("blocked" if any(i["severity"] == "blocker" for i in report["issues"])
                                else "diagnostics_completed")
    except (sqlite3.Error, OSError, OverflowError):
        # SQLite errors may embed private values. Only emit a stable code.
        report["issues"].append(dict(code="snapshot_unreadable", severity="blocker"))
        report["status"] = "blocked"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, required=True,
                        help="Closed standalone DB backup; never the live shop database.")
    args = parser.parse_args()
    report = inspect_snapshot(args.snapshot)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 2 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
