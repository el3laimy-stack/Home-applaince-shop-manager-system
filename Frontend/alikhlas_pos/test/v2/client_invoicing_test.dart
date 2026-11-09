import 'dart:io';
import 'dart:ui' as ui;

import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/printing/sale_receipt_pdf.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/checkout.dart';
import 'invoice_readiness_test.dart' show start, remount, text, money;

Finder priceInput(int id) => find.descendant(
  of: find.byKey(ValueKey('checkout-price-$id')),
  matching: find.byType(TextField),
);

Future<T> success<T>(Future<AppResult<T>> result) async =>
    (await result as AppSuccess<T>).value;

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('CLIENT_REVIEW_DIR') == '') return;
    final loader = FontLoader('Cairo');
    for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Cairo-$name.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'invoice price survives restart and commits without changing catalog',
    (t) async {
      final f = await start(t, rejectSale: false);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '٣');
      await t.enterText(priceInput(1), '١٢٠٫٥٠');
      await t.pumpAndSettle();
      expect(find.text('يتبقى 7'), findsOneWidget);
      expect((await f.db.select(f.db.products).get()).first.stockQty, 10);
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      await remount(t, f.container);
      await tapSection(t, 'البيع');
      expect(text(t, priceInput(1)), '١٢٠٫٥٠');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '361.50');
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      final receipt = await f.uc.saleReceipt(
        (await f.db.select(f.db.saleInvoices).getSingle()).id,
      );
      expect(receipt.lines.single.unitPriceMinor, 12050);
      expect(receipt.lines.single.qty, 3);
      final product = (await f.db.select(f.db.products).get()).first;
      expect(product.salePriceMinor, 10000);
      expect(product.stockQty, 7);
      await t.tap(find.widgetWithText(TextButton, 'إغلاق'));
      await t.pumpAndSettle();
      expect(text(t, priceInput(1)), '100.00');
      expect(f.saleWrites(), 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid raw price survives restart and blocks checkout, stock still enforced',
    (t) async {
      final f = await start(t);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '1');
      await t.enterText(priceInput(1), '12..');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      await remount(t, f.container);
      await tapSection(t, 'البيع');
      expect(text(t, priceInput(1)), '12..');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'مراجعة ودفع'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(priceInput(1), '120');
      await t.enterText(quantityInput(1), '11');
      await t.pumpAndSettle();
      expect(find.textContaining('تتجاوز المخزون'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'مراجعة ودفع'),
            )
            .onPressed,
        isNull,
      );
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
    },
  );

  testWidgets('price change preserves manually entered payment', (t) async {
    await start(t);
    await tapSection(t, 'البيع');
    await t.enterText(quantityInput(1), '1');
    await t.pumpAndSettle();
    await reachCheckout(t);
    await t.enterText(money('كاش'), '50');
    await t.tap(find.text('العودة للأصناف'));
    await t.pumpAndSettle();
    await t.enterText(priceInput(1), '125');
    await t.pumpAndSettle();
    await reachCheckout(t);
    expect(text(t, money('كاش')), '50');
  });

  for (final scale in [1.0, 1.25]) {
    testWidgets(
      '100 selected types in a 1000 item catalog at 1024 with scale $scale',
      (t) async {
        final f = await start(t, products: 1000);
        final rows = await f.db.select(f.db.products).get();
        await f.uc.saveSaleDraft(
          SaleDraft(
            items: [
              for (final p in rows.take(100))
                SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 10000),
            ],
            cashMinor: 1000000,
            walletMinor: 0,
            discountMinor: 0,
            interestMinor: 0,
            installmentCount: 3,
            firstDueDate: DateTime(2026, 12, 8),
            periodDays: 30,
            savedAt: DateTime(2026, 11, 8),
          ),
        );
        await remount(t, f.container);
        t.view.physicalSize = const Size(1024, 720);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await tapSection(t, 'البيع');
        await t.pumpAndSettle();
        expect(find.text('100 نوع · 100 قطعة'), findsOneWidget);
        await t.enterText(priceInput(1), '120');
        await t.tap(find.text('مراجعة ودفع'));
        await t.pumpAndSettle();
        expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
        expect(t.takeException(), isNull);
        await t.runAsync(
          () => screenshot(t, 'catalog-${(scale * 100).round()}'),
        );
      },
    );
  }

  for (final outcome in ReceiptPrintOutcome.values) {
    testWidgets(
      'automatic print $outcome is attempted once and never duplicates sale',
      (t) async {
        var printed = 0;
        final f = await start(
          t,
          rejectSale: false,
          printer: (job) async {
            printed++;
            expect(job.receipt.shopSettings.branchName, 'فرع تجريبي');
            return outcome;
          },
        );
        await success(
          f.uc.updateShopSettings(
            shopName: 'محل تجريبي',
            branchName: 'فرع تجريبي',
          ),
        );
        await f.uc.saveReceiptPrintProfile(
          const ReceiptPrintProfile(autoPrintAfterSale: true),
        );
        await tapSection(t, 'البيع');
        await t.enterText(quantityInput(1), '1');
        await t.pumpAndSettle();
        await reachCheckout(t);
        await t.tap(find.text('تأكيد تسجيل البيع'));
        await t.pumpAndSettle();
        expect(printed, 1);
        expect(find.text('الفرع: فرع تجريبي'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(TextField, 'بحث داخل الفاتورة'),
          'Review',
        );
        await t.pumpAndSettle();
        expect(printed, 1);
        expect(await f.db.select(f.db.saleInvoices).get(), hasLength(1));
        expect(f.saleWrites(), 1);
        expect(t.takeException(), isNull);
        await t.runAsync(() => screenshot(t, 'receipt-${outcome.name}'));
        await t.tap(find.widgetWithText(TextButton, 'إغلاق'));
        await t.pumpAndSettle();
        await tapSection(t, 'الفواتير والمرتجعات');
        await t.tap(find.text('تفاصيل وطباعة').first);
        await t.pumpAndSettle();
        expect(
          printed,
          1,
          reason: 'Opening history must not start another automatic print',
        );
      },
    );
  }

  test(
    'new sale and purchase keep shop identity, legacy invoices use settings',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db);
      await success(
        uc.updateShopSettings(shopName: 'متجر أول', branchName: 'فرع أول'),
      );
      await success(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      final p = await success(
        uc.createProduct(
          operationKey: uc.newOpeningStockOperationKey(),
          name: 'صنف',
          salePriceMinor: 15000,
          openingQty: 10,
          openingCostMinor: 10000,
        ),
      );
      final saleId = await success(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 15000),
          ],
          payments: const [PaymentInput(PaymentMethod.cash, 15000)],
        ),
      );
      final purchaseId = await success(
        uc.createPurchase(
          operationKey: uc.newPurchaseOperationKey(),
          items: [
            PurchaseLineInput(productId: p.id, qty: 1, unitCostMinor: 10000),
          ],
          payments: const [PaymentInput(PaymentMethod.cash, 10000)],
        ),
      );
      final issuedAt = (await uc.saleReceipt(saleId)).invoice.createdAt;
      await success(
        uc.updateShopSettings(shopName: 'متجر جديد', branchName: 'فرع جديد'),
      );
      expect((await uc.saleReceipt(saleId)).shopSettings.shopName, 'متجر أول');
      expect((await uc.saleReceipt(saleId)).shopSettings.branchName, 'فرع أول');
      expect(
        (await uc.purchaseReceipt(purchaseId)).shopSettings.branchName,
        'فرع أول',
      );
      expect((await uc.saleReceipt(saleId)).invoice.createdAt, issuedAt);
      await db.customStatement('DELETE FROM app_settings WHERE key = ?', [
        'invoice.sale.$saleId.shop',
      ]);
      expect((await uc.saleReceipt(saleId)).shopSettings.shopName, 'متجر جديد');
      expect((await uc.saleReceipt(saleId)).invoice.createdAt, issuedAt);
      expect(
        await uc.updateShopSettings(shopName: 'اسم', branchName: ' '),
        isA<AppFailure<ShopSettingsSnapshot>>(),
      );
    },
  );

  test(
    'gross profit differs from net and later purchase does not revalue old sales',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db);
      await success(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      final p = await success(
        uc.createProduct(
          operationKey: uc.newOpeningStockOperationKey(),
          name: 'صنف',
          salePriceMinor: 15000,
          openingQty: 2,
          openingCostMinor: 10000,
        ),
      );
      await success(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 15000),
          ],
          payments: const [PaymentInput(PaymentMethod.cash, 14000)],
          discountMinor: 1000,
        ),
      );
      await success(
        uc.recordExpense(
          operationKey: uc.newExpenseOperationKey(),
          description: 'تجربة',
          amountMinor: 500,
          method: PaymentMethod.cash,
        ),
      );
      final before = await uc.dashboardSnapshot();
      expect(before.tradingGrossProfitMinor, 4000);
      expect(before.profitMinor, 3500);
      await success(
        uc.createPurchase(
          operationKey: uc.newPurchaseOperationKey(),
          items: [
            PurchaseLineInput(productId: p.id, qty: 1, unitCostMinor: 20000),
          ],
          payments: const [],
          supplierId: await db
              .into(db.suppliers)
              .insert(SuppliersCompanion.insert(name: 'مورد تجريبي')),
        ),
      );
      final after = await uc.dashboardSnapshot();
      expect(after.tradingGrossProfitMinor, before.tradingGrossProfitMinor);
      expect(after.profitMinor, before.profitMinor);
      final period = await uc.periodReport(
        start: DateTime(2000),
        end: DateTime(2100),
      );
      expect(period.tradingGrossProfitMinor, 4000);
      expect(period.profitMinor, 3500);
    },
  );

  test(
    'shift close backs up even before interval and failure does not undo close',
    () async {
      final dir = await Directory.systemTemp.createTemp('client-close-backup-');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 8, 12));
      final destination = Directory('${dir.path}/backups');
      await uc.setBackupDirectory(destination.path);
      await uc.runAutomaticBackupIfDue();
      await success(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      await success(uc.closeShift(0, operationKey: uc.newShiftOperationKey()));
      final copies = await destination
          .list()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      expect(copies, hasLength(2));
      final copy = AppDatabase(
        NativeDatabase(
          File(copies.singleWhere((f) => f.path.endsWith('-1.db')).path),
        ),
      );
      expect((await copy.select(copy.shifts).getSingle()).status, 'closed');
      await copy.close();
      final obstruction = await File(
        '${dir.path}/device',
      ).writeAsString('unavailable');
      await uc.setBackupDirectory('${obstruction.path}/backups');
      await success(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      expect(
        await uc.closeShift(0, operationKey: uc.newShiftOperationKey()),
        isA<AppSuccess<Shift>>(),
      );
      expect(await uc.currentShift(), isNull);
      expect(uc.backupWarning, isNotNull);
      expect(
        (await db.select(db.appSettings).get())
            .singleWhere((s) => s.key == 'backup.lastSuccessAt')
            .value,
        DateTime(2026, 11, 8, 12).toIso8601String(),
      );
    },
  );

  testWidgets(
    'Tab moves quantity to sale price to next row, then leaves final price',
    (t) async {
      await start(t);
      await tapSection(t, 'البيع');
      await t.tap(quantityInput(1));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(priceInput(1)).focusNode!.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(quantityInput(2)).focusNode!.hasFocus, isTrue);
      await t.tap(priceInput(2));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(priceInput(2)).focusNode!.hasFocus, isFalse);
    },
  );

  testWidgets(
    'long shop and branch headers remain usable at 1024 and 125 percent',
    (t) async {
      final f = await start(t, rejectSale: false);
      const shop =
          'متجر تجريبي للأجهزة والأدوات المنزلية والكهربائية والمفروشات';
      const branch = 'الفرع الرئيسي في عنوان تجريبي طويل لاختبار عرض الفاتورة';
      await success(
        f.uc.updateShopSettings(shopName: shop, branchName: branch),
      );
      t.view.physicalSize = const Size(1024, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '1');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      expect(find.text(shop), findsOneWidget);
      expect(find.text('الفرع: $branch'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'إغلاق').hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.runAsync(() => screenshot(t, 'receipt-long-header-125'));
    },
  );

  test(
    'pending close creates a committed external copy that restores stock and receipt identity',
    () async {
      final dir = await Directory.systemTemp.createTemp('client-restore-');
      addTearDown(() => dir.delete(recursive: true));
      final live = File('${dir.path}/live.db');
      var db = AppDatabase(NativeDatabase(live));
      addTearDown(() => db.close());
      var uc = V2UseCases(db);
      await success(
        uc.updateShopSettings(shopName: 'متجر تجريبي', branchName: 'فرع محفوظ'),
      );
      await success(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
      final product = await success(
        uc.createProduct(
          operationKey: uc.newOpeningStockOperationKey(),
          name: 'صنف للاستعادة',
          salePriceMinor: 15000,
          openingQty: 10,
          openingCostMinor: 10000,
        ),
      );
      final saleId = await success(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: product.id, qty: 3, unitPriceMinor: 15000),
          ],
          payments: const [PaymentInput(PaymentMethod.cash, 45000)],
        ),
      );
      await uc.setBackupDirectory('${dir.path}/external');
      final request = await uc.stagePendingFinancialOperation(
        PendingFinancialOperation.closeShift(
          operationKey: uc.newShiftOperationKey(),
          actualCashMinor: 45000,
        ),
      );
      await success(uc.submitPendingFinancialOperation(request));
      final backup =
          (await Directory('${dir.path}/external').list().toList()).single
              as File;
      await success(
        uc.updateShopSettings(
          shopName: 'اسم تغير لاحقًا',
          branchName: 'فرع جديد',
        ),
      );
      await success(
        uc.openShift(45000, operationKey: uc.newShiftOperationKey()),
      );
      await success(
        uc.createSale(
          operationKey: uc.newSaleOperationKey(),
          items: [
            SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 15000),
          ],
          payments: const [PaymentInput(PaymentMethod.cash, 15000)],
        ),
      );
      await uc.restoreFromBackup(backup);
      db = AppDatabase(NativeDatabase(live));
      uc = V2UseCases(db);
      expect(await uc.currentShift(), isNull);
      expect((await db.select(db.products).getSingle()).stockQty, 7);
      expect(await db.select(db.saleInvoices).get(), hasLength(1));
      expect(
        (await uc.saleReceipt(saleId)).shopSettings.branchName,
        'فرع محفوظ',
      );
      expect((await uc.dashboardSnapshot()).tradingGrossProfitMinor, 15000);
    },
  );
}

Future<void> screenshot(WidgetTester t, String name) async {
  const path = String.fromEnvironment('CLIENT_REVIEW_DIR');
  if (path.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('invoice-review')),
  );
  final img = await boundary.toImage();
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$path/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data!.buffer.asUint8List());
  img.dispose();
}
