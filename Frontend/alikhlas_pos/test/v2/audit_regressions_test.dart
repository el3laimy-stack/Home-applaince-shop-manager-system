import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> ok<T>(Future<AppResult<T>> future) async =>
    (await future as AppSuccess<T>).value;

void main() {
  late AppDatabase db;
  late V2UseCases uc;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    uc = V2UseCases(db);
  });
  tearDown(() => db.close());

  Future<Product> product({
    String name = 'Original appliance',
    String? barcode,
    int qty = 2,
  }) => ok(
    uc.createProduct(
      operationKey: uc.newOpeningStockOperationKey(),
      name: name,
      barcode: barcode,
      salePriceMinor: 10000,
      openingQty: qty,
      openingCostMinor: 7000,
    ),
  );

  test('dashboard net profit includes installment interest', () async {
    final p = await product();
    final c = await ok(uc.createCustomer(name: 'Customer'));
    await ok(
      uc.createSale(
        operationKey: uc.newSaleOperationKey(),
        customerId: c.id,
        items: [SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 10000)],
        payments: [],
        installmentTerms: InstallmentTerms(
          partyId: c.id,
          count: 1,
          firstDueDate: DateTime.now(),
          interestMinor: 1000,
        ),
      ),
    );
    final d = await uc.dashboardSnapshot();
    final report = await uc.periodReport(
      start: DateTime(2020),
      end: DateTime(2030),
    );
    expect(d.grossProfitMinor, report.profitMinor);
  });

  test('supplier summary and statement use consistent balance sign', () async {
    final p = await product(qty: 0);
    final s = await ok(uc.createSupplier(name: 'Supplier'));
    await ok(
      uc.createPurchase(
        operationKey: uc.newPurchaseOperationKey(),
        supplierId: s.id,
        items: [
          PurchaseLineInput(productId: p.id, qty: 2, unitCostMinor: 5000),
        ],
        payments: [],
      ),
    );
    final summary = (await uc.workbenchSnapshot()).supplierBalances.single;
    final statement = await uc.partyStatement(
      partyType: 'supplier',
      partyId: s.id,
    );
    expect(summary.balanceMinor, statement.last.balanceMinor);
  });

  test('supplier invoice details show purchase returns', () async {
    final p = await product(qty: 0);
    final s = await ok(uc.createSupplier(name: 'Supplier'));
    final purchase = await ok(
      uc.createPurchase(
        operationKey: uc.newPurchaseOperationKey(),
        supplierId: s.id,
        items: [
          PurchaseLineInput(productId: p.id, qty: 2, unitCostMinor: 5000),
        ],
        payments: [],
      ),
    );
    final item = (await db.select(db.purchaseItems).get()).single;
    await ok(
      uc.createPurchaseReturn(
        operationKey: uc.newPurchaseReturnOperationKey(),
        purchaseId: purchase,
        purchaseItemQuantities: {item.id: 1},
        settlementMethod: PaymentMethod.installment,
      ),
    );
    final statement = await uc.partyStatement(
      partyType: 'supplier',
      partyId: s.id,
    );
    final details = statement.first.invoiceDetails!;
    expect(details.returnedMinor, 5000);
    expect(statement.last.invoiceDetails, isNotNull);
  });

  test(
    'historical receipt preserves product name after catalogue edit',
    () async {
      final p = await product();
      final sale = await ok(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 10000),
          ],
          payments: [PaymentInput(PaymentMethod.wallet, 10000)],
        ),
      );
      await ok(
        uc.updateProduct(
          id: p.id,
          name: 'Completely different appliance',
          barcode: p.barcode,
          salePriceMinor: 10000,
          minStockQty: 1,
        ),
      );
      final receipt = await uc.saleReceipt(sale);
      expect(receipt.lines.single.productName, 'Original appliance');
    },
  );

  test(
    'manual or imported auto-format barcode does not block automatic products',
    () async {
      await product(barcode: 'AK-${DateTime.now().year}-00001', qty: 0);
      final result = await uc.createProduct(
        name: 'Automatic product',
        salePriceMinor: 10000,
        openingQty: 0,
        openingCostMinor: 0,
      );
      expect(result, isA<AppSuccess<Product>>());
    },
  );

  test('large numeric input returns validation error without throwing', () {
    expect(
      parseMoneyInput('999999999999999999999999999999999999').isValid,
      isFalse,
    );
  });

  test('money input does not silently overflow', () {
    final result = parseMoneyInput('92233720368547759');
    expect(result.isValid, isFalse);
  });

  test('daily alerts include all due installments beyond twelve', () async {
    final p = await product();
    final c = await ok(uc.createCustomer(name: 'Customer'));
    await ok(
      uc.createSale(
        operationKey: uc.newSaleOperationKey(),
        customerId: c.id,
        items: [SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 10000)],
        payments: [],
        installmentTerms: InstallmentTerms(
          partyId: c.id,
          count: 13,
          firstDueDate: DateTime.now().subtract(const Duration(days: 30)),
          periodDays: 1,
        ),
      ),
    );
    final snapshot = await uc.workbenchSnapshot();
    expect(snapshot.dueInstallments.length, 12);
    expect(snapshot.installmentAlerts.overdueCount, 13);
  });

  test(
    'reopening shift in same stored second does not recount prior cash',
    () async {
      final stamp = DateTime.now();
      uc = V2UseCases(db, clock: () => stamp);
      final p = await product();
      await ok(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      await ok(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 10000),
          ],
          payments: [PaymentInput(PaymentMethod.cash, 10000)],
        ),
      );
      await ok(uc.closeShift(10000, operationKey: uc.newShiftOperationKey()));
      await ok(uc.openShift(10000, operationKey: uc.newShiftOperationKey()));
      final closed = await ok(
        uc.closeShift(10000, operationKey: uc.newShiftOperationKey()),
      );
      expect(closed.differenceMinor, 0);
    },
  );
}
