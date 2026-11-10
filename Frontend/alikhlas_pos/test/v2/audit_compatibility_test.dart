import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'legacy_schema_fixture.dart';

Future<T> ok<T>(Future<AppResult<T>> result) async =>
    (await result as AppSuccess<T>).value;

void main() {
  test('inventory allocation uses exact intermediates beyond int64', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final uc = V2UseCases(db);
    final product = await ok(
      uc.createProduct(
        operationKey: 'stock-large',
        name: 'Exact',
        salePriceMinor: 1,
        openingQty: 10,
        openingCostMinor: 900000000000000000,
      ),
    );
    final sale = await ok(
      uc.createSale(
        operationKey: 'large-cost-sale',
        items: [
          SaleLineInput(productId: product.id, qty: 9, unitPriceMinor: 1),
        ],
        payments: [PaymentInput(PaymentMethod.wallet, 9)],
      ),
    );
    final line = await db.select(db.saleItems).getSingle();
    expect(line.costMinor, 8100000000000000000);
    for (var i = 0; i < 3; i++) {
      await ok(
        uc.createSaleReturn(
          operationKey: 'large-return-$i',
          saleId: sale,
          saleItemQuantities: {line.id: 3},
          refundMethod: PaymentMethod.wallet,
        ),
      );
    }
    expect(
      (await db.select(db.products).getSingle()).inventoryValueMinor,
      9000000000000000000,
    );
    expect((await uc.dashboardSnapshot()).cogsMinor, 0);
  });

  test(
    'due counters use remaining scheduled amounts and the injected calendar day',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 7, 23));
      final product = await ok(
        uc.createProduct(
          operationKey: 'due-stock',
          name: 'Due',
          salePriceMinor: 200,
          openingQty: 1,
          openingCostMinor: 100,
        ),
      );
      final customer = await ok(uc.createCustomer(name: 'Due customer'));
      await ok(
        uc.createSale(
          operationKey: 'due-sale',
          customerId: customer.id,
          items: [
            SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 200),
          ],
          payments: [],
          installmentTerms: InstallmentTerms(
            partyId: customer.id,
            count: 3,
            firstDueDate: DateTime(2026, 11, 6),
            periodDays: 1,
          ),
        ),
      );
      final plan = await db.select(db.installmentPlans).getSingle();
      await ok(
        uc.collectInstallment(
          operationKey: 'due-payment',
          planId: plan.id,
          amountMinor: 70,
          method: PaymentMethod.wallet,
        ),
      );
      final snapshot = await uc.workbenchSnapshot();
      expect(snapshot.installmentAlerts.overdueCount, 0);
      expect(snapshot.installmentAlerts.dueTodayCount, 1);
      expect(snapshot.dueInstallments.first.remainingMinor, 62);
    },
  );

  test(
    'money boundaries round-trip exactly and checked arithmetic never wraps',
    () {
      for (final value in [maxMoneyMinor, minMoneyMinor, BigInt.from(12550)]) {
        final money = Money(value.toInt());
        final input = money.formatPlain(symbol: '').replaceAll(',', '').trim();
        expect(
          parseMoneyInput(input, allowNegative: true).minorUnits,
          value.toInt(),
        );
        expect(
          normalizeArabicDigits(money.format()),
          contains((value.abs() % BigInt.from(100)).toString().padLeft(2, '0')),
        );
      }
      expect(parseMoneyInput('92233720368547758.08').isValid, isFalse);
      expect(
        parseMoneyInput('-92233720368547758.09', allowNegative: true).isValid,
        isFalse,
      );
      expect(
        () => addMinor(maxMoneyMinor.toInt(), 1),
        throwsA(isA<MoneyRangeException>()),
      );
      expect(
        () => multiplyMinor(maxMoneyMinor.toInt(), 2),
        throwsA(isA<MoneyRangeException>()),
      );
    },
  );

  test(
    'overflowing sale and purchase leave no rows, stock changes, or receipts',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db);
      final product = await ok(
        uc.createProduct(
          operationKey: 'stock',
          name: 'Overflow',
          salePriceMinor: 1,
          openingQty: 2,
          openingCostMinor: 1,
        ),
      );
      final before = await db.select(db.ledgerEntries).get();
      expect(
        await uc.createSale(
          operationKey: 'overflow-sale',
          items: [
            SaleLineInput(
              productId: product.id,
              qty: 2,
              unitPriceMinor: maxMoneyMinor.toInt(),
            ),
          ],
          payments: [],
        ),
        isA<AppFailure<int>>(),
      );
      expect(
        await uc.createPurchase(
          operationKey: 'overflow-purchase',
          items: [
            PurchaseLineInput(
              productId: product.id,
              qty: 2,
              unitCostMinor: maxMoneyMinor.toInt(),
            ),
          ],
          payments: [],
        ),
        isA<AppFailure<int>>(),
      );
      expect(await db.select(db.saleInvoices).get(), isEmpty);
      expect(await db.select(db.purchaseInvoices).get(), isEmpty);
      expect((await db.select(db.products).getSingle()).stockQty, 2);
      expect(await db.select(db.ledgerEntries).get(), before);
      expect(
        (await db.select(db.appSettings).get()).where(
          (row) => row.key.contains('overflow-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'CSV generation reserves explicit barcodes appearing later in the batch',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db, clock: () => DateTime(2026));
      final rows = await uc.previewProductCsv(
        'name,barcode,category,sale_price,opening_qty,unit_cost,min_stock_qty\nAutomatic,,,100,0,0,1\nExplicit,AK-2026-00001,,100,0,0,1\n',
      );
      expect(rows.canImport, isTrue);
      await ok(
        uc.importProductCsv(operationKey: 'csv-reserved', rows: rows.rows),
      );
      final products = await db.select(db.products).get();
      expect(products.map((row) => row.barcode).toSet(), {
        'AK-2026-00001',
        'AK-2026-00002',
      });
    },
  );

  test('purchase cash refund remains distinct from debt settlement', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final uc = V2UseCases(db);
    final product = await ok(
      uc.createProduct(
        name: 'Return',
        salePriceMinor: 100,
        openingQty: 0,
        openingCostMinor: 0,
      ),
    );
    final supplier = await ok(uc.createSupplier(name: 'Supplier'));
    final id = await ok(
      uc.createPurchase(
        operationKey: 'purchase',
        supplierId: supplier.id,
        items: [
          PurchaseLineInput(productId: product.id, qty: 2, unitCostMinor: 100),
        ],
        payments: [],
      ),
    );
    final item = await db.select(db.purchaseItems).getSingle();
    await ok(
      uc.createPurchaseReturn(
        operationKey: 'refund',
        purchaseId: id,
        purchaseItemQuantities: {item.id: 1},
        settlementMethod: PaymentMethod.wallet,
      ),
    );
    final details = (await uc.partyStatement(
      partyType: 'supplier',
      partyId: supplier.id,
    )).last.invoiceDetails!;
    expect(details.returnedMinor, 100);
    expect(details.liquidRefundMinor, 100);
    expect(details.debtSettlementMinor, 0);
    expect(details.remainingMinor, 200);
    expect(
      partyBalanceText('supplier', -100, plain: true),
      contains('لنا عند المورد'),
    );
    expect(
      partyBalanceText('customer', -100, plain: true),
      contains('للعميل لدينا'),
    );
  });

  for (var version = 3; version <= 11; version++) {
    test(
      'schema $version upgrades history and open shift to v12 without financial changes',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'audit-upgrade-$version-',
        );
        addTearDown(() => root.delete(recursive: true));
        final file = File('${root.path}/shop.db');
        var db = AppDatabase(NativeDatabase(file));
        final uc = V2UseCases(db);
        final product = await ok(
          uc.createProduct(
            operationKey: 'seed',
            name: 'Original',
            salePriceMinor: 100,
            openingQty: 2,
            openingCostMinor: 70,
          ),
        );
        await ok(uc.openShift(500, operationKey: 'open'));
        await ok(
          uc.createSale(
            operationKey: 'sale',
            items: [
              SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 100),
            ],
            payments: [PaymentInput(PaymentMethod.cash, 100)],
          ),
        );
        await ok(
          uc.createPurchase(
            operationKey: 'purchase',
            items: [
              PurchaseLineInput(
                productId: product.id,
                qty: 1,
                unitCostMinor: 70,
              ),
            ],
            payments: [PaymentInput(PaymentMethod.wallet, 70)],
            allowNegativeBalance: true,
          ),
        );
        final before = await uc.dashboardSnapshot();
        await db.close();
        final raw = sqlite.sqlite3.open(file.path);
        removeV12Columns(raw);
        raw.execute(
          "UPDATE products SET name = 'Name at upgrade', barcode = NULL",
        );
        if (version < 11) {
          raw.execute('DROP TABLE financial_correction_reversals');
        }
        if (version < 10) {
          raw.execute('DROP TRIGGER IF EXISTS products_nonnegative_insert');
          raw.execute('DROP TRIGGER IF EXISTS products_nonnegative_update');
          raw.execute('ALTER TABLE products DROP COLUMN inventory_value_minor');
          raw.execute('ALTER TABLE sale_items DROP COLUMN cost_minor');
          raw.execute('ALTER TABLE sale_return_items DROP COLUMN cost_minor');
        }
        if (version < 9) raw.execute('DROP TABLE financial_corrections');
        if (version < 8) {
          raw.execute('DROP TABLE purchase_return_items');
          raw.execute('DROP TABLE purchase_returns');
        }
        if (version < 7) raw.execute('DROP TABLE opening_balances');
        if (version < 6) raw.execute('DROP TABLE inventory_adjustments');
        if (version < 5) {
          raw.execute('ALTER TABLE products DROP COLUMN image_path');
        }
        if (version < 4) raw.execute('DROP TABLE expenses');
        raw.execute('PRAGMA user_version = $version');
        raw.close();
        db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        final migrated = V2UseCases(db);
        await migrated.bootstrap();
        final after = await migrated.dashboardSnapshot();
        expect(after.cashMinor, before.cashMinor);
        expect(after.inventoryMinor, before.inventoryMinor);
        expect(after.expectedOpenShiftCashMinor, 600);
        final sale = await db.select(db.saleItems).getSingle();
        final purchase = await db.select(db.purchaseItems).getSingle();
        expect(sale.productNameSnapshot, 'Name at upgrade');
        expect(purchase.productNameSnapshot, 'Name at upgrade');
        expect(sale.identitySnapshotOrigin, 'legacy_backfill');
        expect(sale.productBarcodeSnapshot, isNull);
        expect(
          (await migrated.saleReceipt(sale.saleId)).hasLegacyProductIdentity,
          isTrue,
        );
        await ok(
          migrated.updateProduct(
            id: product.id,
            name: 'Later',
            barcode: 'later',
            salePriceMinor: 200,
            minStockQty: 1,
          ),
        );
        expect(
          (await migrated.saleReceipt(sale.saleId)).lines.single.productName,
          'Name at upgrade',
        );
        expect(
          (await migrated.saleReceipt(sale.saleId)).lines.single.productBarcode,
          isNull,
        );
        expect(
          await migrated.createSale(
            operationKey: 'sale',
            items: [
              SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 100),
            ],
            payments: [PaymentInput(PaymentMethod.cash, 100)],
          ),
          isA<AppSuccess<int>>(),
        );
        final closed = await ok(
          migrated.closeShift(600, operationKey: 'close'),
        );
        expect(closed.differenceMinor, 0);
        expect((await migrated.dataIntegrityAudit()).isConsistent, isTrue);
      },
    );
  }
}
