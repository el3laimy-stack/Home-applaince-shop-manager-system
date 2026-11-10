import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';

void main() {
  test(
    'application cannot commit a revenue balance whose display sign overflows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final uc = V2UseCases(db);
      try {
        final product =
            (await uc.createProduct(
                      operationKey: 'stock',
                      name: 'fixture',
                      salePriceMinor: 1,
                      openingQty: 2,
                      openingCostMinor: 1,
                    )
                    as AppSuccess<Product>)
                .value;
        await uc.openShift(0, operationKey: 'open');
        await uc.createSale(
          operationKey: 'big',
          items: [
            SaleLineInput(
              productId: product.id,
              qty: 1,
              unitPriceMinor: 9223372036854775807,
            ),
          ],
          payments: [PaymentInput(PaymentMethod.cash, 9223372036854775807)],
        );
        final result = await uc.createSale(
          operationKey: 'one',
          items: [
            SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 1),
          ],
          payments: [PaymentInput(PaymentMethod.wallet, 1)],
        );
        Object? dashboardError;
        try {
          await uc.dashboardSnapshot();
        } catch (e) {
          dashboardError = e;
        }
        expect(dashboardError, isNull);
        expect(await db.select(db.saleInvoices).get(), hasLength(1));
        expect((await db.select(db.products).get()).single.stockQty, 1);
        expect(
          await db
              .customSelect(
                "SELECT 1 FROM operation_receipts WHERE receipt_key='operation.sale.one'",
              )
              .get(),
          isEmpty,
        );
        expect(
          result,
          isA<AppFailure<int>>(),
          reason:
              'The second sale must be rejected atomically before posted/receipt success',
        );
      } finally {
        await db.close();
      }
    },
  );
  test('cumulative return guard must not skip a stored id minus one', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final uc = V2UseCases(db);
    try {
      final p =
          (await uc.createProduct(
                    operationKey: 'stock',
                    name: 'fixture',
                    salePriceMinor: 5,
                    openingQty: 2,
                    openingCostMinor: 1,
                  )
                  as AppSuccess<Product>)
              .value;
      final sale =
          (await uc.createSale(
                    operationKey: 'sale',
                    items: [
                      SaleLineInput(productId: p.id, qty: 2, unitPriceMinor: 5),
                    ],
                    payments: [PaymentInput(PaymentMethod.wallet, 10)],
                  )
                  as AppSuccess<int>)
              .value;
      final item = (await db.select(db.saleItems).get()).single;
      await db.customStatement(
        "INSERT INTO sale_returns(sale_id,return_no,refund_minor) VALUES (?,'probe',20)",
        [sale],
      );
      final ret = (await db.select(db.saleReturns).get()).single.id;
      await db.customStatement(
        'DROP TRIGGER identity_sentinel_sale_return_items',
      );
      await db.customStatement(
        'INSERT INTO sale_return_items(id,return_id,sale_item_id,product_id,qty,unit_price_minor,unit_cost_minor,cost_minor) VALUES (-1,?,?,?,2,5,1,2)',
        [ret, item.id, p.id],
      );
      Object? error;
      try {
        await db.customStatement(
          'INSERT INTO sale_return_items(return_id,sale_item_id,product_id,qty,unit_price_minor,unit_cost_minor,cost_minor) VALUES (?,?,?,2,5,1,2)',
          [ret, item.id, p.id],
        );
      } catch (e) {
        error = e;
      }
      final returned =
          (await db
                  .customSelect('SELECT SUM(qty) AS qty FROM sale_return_items')
                  .getSingle())
              .data['qty'];
      expect(returned, 2);
      expect(
        error,
        isNotNull,
        reason:
            'A second return of all units must fail regardless of stored row ids',
      );
    } finally {
      await db.close();
    }
  });
  test(
    'migration cannot grandfather a plan assigned to another invoice customer',
    () async {
      final dir = await Directory.systemTemp.createTemp('review16-party-');
      final file = File('${dir.path}/shop.db');
      final raw = sql.sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v13.sql').readAsStringSync());
      raw.execute(
        "INSERT INTO customers(id,name) VALUES (1,'A'),(2,'B'); INSERT INTO products(id,name,sale_price_minor) VALUES (1,'fixture',5); INSERT INTO sale_invoices(id,invoice_no,customer_id,subtotal_minor,total_minor,paid_minor,remaining_minor) VALUES (1,'probe',1,5,5,0,5); INSERT INTO sale_items(sale_id,product_id,qty,unit_price_minor,unit_cost_minor,line_total_minor) VALUES (1,1,1,5,0,5); INSERT INTO installment_plans(id,owner_type,owner_id,party_type,party_id,principal_minor,total_minor,paid_minor,installment_count) VALUES (1,'sale',1,'customer',2,5,5,0,1); INSERT INTO installment_payments(plan_id,amount_minor,due_date) VALUES (1,5,1); INSERT INTO ledger_entries(id,reference_type,reference_id,description) VALUES (1,'sale',1,'probe'); INSERT INTO ledger_lines(entry_id,account_code,debit_minor,credit_minor,party_type,party_id) VALUES (1,'receivables',5,0,'customer',2),(1,'sales',0,5,NULL,NULL);",
      );
      raw.close();
      final recovery = MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      );
      await recovery.prepareForOpen();
      final db = AppDatabase(NativeDatabase(file));
      try {
        Object? error;
        try {
          await db.customSelect('SELECT 1').get();
        } catch (e) {
          error = e;
        }
        expect(await recovery.marker.exists(), true);
        expect(
          error,
          isA<DatabaseMigrationFailedDuringUpgrade>(),
          reason:
              'A valid customer id is insufficient when it disagrees with the owner invoice',
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'recursive trigger configuration prevents alternate unique replacement',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final uc = V2UseCases(db);
      try {
        final result = await uc.recordOpeningBalance(
          operationKey: 'open',
          type: OpeningBalanceType.cash,
          amountMinor: 10,
        );
        expect(result, isA<AppSuccess<int>>());
        expect(
          (await db.customSelect('PRAGMA recursive_triggers').getSingle())
              .data
              .values
              .single,
          1,
        );
        await expectLater(
          db.customStatement(
            "INSERT OR REPLACE INTO opening_balances(balance_type,amount_minor) VALUES ('cash',20)",
          ),
          throwsA(isA<sql.SqliteException>()),
        );
      } finally {
        await db.close();
      }
    },
  );
}
