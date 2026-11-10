import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late V2UseCases uc;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    uc = V2UseCases(db);
  });
  tearDown(() => db.close());
  Future<int> draft({int amount = 10}) async {
    await db.customStatement(
      "INSERT INTO expenses(description,amount_minor,method) VALUES ('fixture',?,'wallet')",
      [amount],
    );
    final source =
        (await db
                    .customSelect('SELECT MAX(id) AS id FROM expenses')
                    .getSingle())
                .data['id']
            as int;
    await db.customStatement(
      "INSERT INTO ledger_entries(reference_type,reference_id,description) VALUES ('expense',?,'draft')",
      [source],
    );
    return (await db
                .customSelect('SELECT MAX(id) AS id FROM ledger_entries')
                .getSingle())
            .data['id']
        as int;
  }

  Future<void> line(
    int id,
    String account,
    int debit,
    int credit,
  ) => db.customStatement(
    'INSERT INTO ledger_lines(entry_id,account_code,debit_minor,credit_minor) VALUES (?,?,?,?)',
    [id, account, debit, credit],
  );
  Future<void> post(int id) => db.customStatement(
    "UPDATE ledger_entries SET posting_state='posted' WHERE id=?",
    [id],
  );
  test(
    'posting rejects incomplete, zero and unbalanced groups and accepts a balanced group',
    () async {
      final id = await draft();
      await expectLater(post(id), throwsA(isA<SqliteException>()));
      await line(id, 'expenses', 10, 0);
      await expectLater(post(id), throwsA(isA<SqliteException>()));
      await line(id, 'wallet', 0, 9);
      await expectLater(post(id), throwsA(isA<SqliteException>()));
      await db.customStatement(
        "UPDATE ledger_lines SET credit_minor=10 WHERE account_code='wallet'",
      );
      await post(id);
      expect(
        (await db.selectPostedLedgerEntries().get()).single.postingState,
        'posted',
      );
    },
  );
  test(
    'posted headers and lines reject append, move, delete, replace and upsert',
    () async {
      final id = await draft();
      await line(id, 'expenses', 10, 0);
      await line(id, 'wallet', 0, 10);
      await post(id);
      final other = await draft();
      await line(other, 'expenses', 1, 0);
      // Fixed ids are allocated in this isolated fixture: posted1,2 and draft3.
      for (final sql in [
        "UPDATE ledger_entries SET description='changed' WHERE id=$id",
        "UPDATE ledger_entries SET posting_state='draft' WHERE id=$id",
        'DELETE FROM ledger_entries WHERE id=$id',
        "INSERT OR REPLACE INTO ledger_entries(id,reference_type,reference_id,description) VALUES ($id,'expense',1,'replace')",
        "INSERT INTO ledger_entries(id,reference_type,reference_id,description) VALUES ($id,'expense',1,'upsert') ON CONFLICT(id) DO UPDATE SET description='changed'",
        "INSERT INTO ledger_lines(entry_id,account_code,debit_minor) VALUES ($id,'expenses',1)",
        'UPDATE ledger_lines SET debit_minor=9 WHERE id=1',
        'UPDATE ledger_lines SET entry_id=$other WHERE id=1',
        'UPDATE ledger_lines SET entry_id=$id WHERE id=3',
        'DELETE FROM ledger_lines WHERE id=1',
        "INSERT OR REPLACE INTO ledger_lines(id,entry_id,account_code,debit_minor) VALUES (1,$other,'expenses',1)",
        "UPDATE OR REPLACE ledger_lines SET id=1 WHERE id=3",
        "INSERT INTO ledger_lines(id,entry_id,account_code,debit_minor) VALUES (1,$other,'expenses',1) ON CONFLICT(id) DO UPDATE SET entry_id=$other",
      ]) {
        await expectLater(
          db.customStatement(sql),
          throwsA(isA<SqliteException>()),
          reason: sql,
        );
      }
      expect(await db.selectPostedLedgerLines().get(), hasLength(2));
    },
  );
  test(
    'draft is absent from balances, reports, recent entries and shifts but visible to audit',
    () async {
      final shift = await uc.openShift(0, operationKey: 'shift');
      expect(shift, isA<AppSuccess<Shift>>());
      final id = await draft();
      await line(id, 'expenses', 10, 0);
      await line(id, 'wallet', 0, 10);
      var snapshot = await uc.workbenchSnapshot();
      expect(snapshot.dashboard.walletMinor, 0);
      expect(snapshot.dashboard.expensesMinor, 0);
      expect(snapshot.recentLedger, isEmpty);
      expect(
        (await uc.dataIntegrityAudit()).issues.any(
          (i) => i.code == 'ledger_unposted',
        ),
        true,
      );
      final directory = await Directory.systemTemp.createTemp('draft-backup-');
      try {
        await expectLater(
          uc.backupToDirectory(directory),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
      await post(id);
      snapshot = await uc.workbenchSnapshot();
      expect(snapshot.dashboard.walletMinor, -10);
      expect(snapshot.dashboard.expensesMinor, 10);
      expect(snapshot.recentLedger, hasLength(1));
    },
  );
  test(
    'application failure at posting leaves no document, lines, draft or receipt',
    () async {
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        "CREATE TEMP TRIGGER fail_post BEFORE UPDATE OF posting_state ON ledger_entries WHEN NEW.posting_state='posted' BEGIN SELECT RAISE(ABORT,'failure before posting'); END",
      );
      await expectLater(
        uc.recordExpense(
          operationKey: 'fail-post',
          description: 'failed',
          amountMinor: 10,
          method: PaymentMethod.wallet,
          allowNegativeBalance: true,
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await db.select(db.ledgerEntries).get(), isEmpty);
      expect(await db.select(db.ledgerLines).get(), isEmpty);
      expect(await db.select(db.operationReceipts).get(), isEmpty);
    },
  );
}
