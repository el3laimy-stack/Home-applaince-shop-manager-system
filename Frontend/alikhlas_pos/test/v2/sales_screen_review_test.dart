import '../support/visual_binding.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/printing/sale_receipt_pdf.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/checkout.dart';
import 'invoice_readiness_test.dart' as fixture;

Future<void> saleCapture(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SALES_REVIEW_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('invoice-review')),
    );
    final img = await boundary.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
  });
}

Future<void> savedHundred(V2UseCases uc) async {
  await uc.saveSaleDraft(
    SaleDraft(
      items: [
        for (var id = 1; id <= 100; id++)
          SaleLineInput(
            productId: id,
            qty: id == 1 ? 3 : 1,
            unitPriceMinor: id == 1 ? 12050 : 10000,
          ),
      ],
      cashMinor: 1026150,
      walletMinor: 0,
      discountMinor: 0,
      interestMinor: 0,
      installmentCount: 3,
      firstDueDate: DateTime(2026, 12, 8),
      periodDays: 30,
      savedAt: DateTime(2026, 11, 8),
    ),
  );
}

void main() {
  initializeVisualTests();
  setUpAll(() async {
    final fonts = FontLoader('Cairo');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final mode in ['light', 'dark']) {
    for (final small in [false, true]) {
      testWidgets('$mode hundred-line sale at ${small ? '1024' : '1280'}', (
        t,
      ) async {
        final f = await fixture.start(t, products: 200);
        await savedHundred(f.uc);
        await f.container.read(appThemeModeProvider.notifier).change(mode);
        t.view.physicalSize = small
            ? const Size(1024, 720)
            : const Size(1280, 800);
        t.platformDispatcher.textScaleFactorTestValue = small ? 1.25 : 1;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await tapSection(t, 'البيع');
        await saleCapture(t, '$mode-${small ? '1024' : '1280'}-select');
        await t.tap(find.text('مراجعة ودفع'));
        await t.pumpAndSettle();
        final viewport = t.getRect(
          find.byKey(const PageStorageKey('checkout-catalog-scroll')),
        );
        final rows = find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('catalog-row-'),
        );
        final complete = rows.evaluate().where((e) {
          final r = t.getRect(find.byWidget(e.widget));
          return r.top >= viewport.top - 1 && r.bottom <= viewport.bottom + 1;
        }).length;
        expect(complete, greaterThanOrEqualTo(3));
        await saleCapture(t, '$mode-${small ? '1024' : '1280'}-review');
        await t.tap(find.text('متابعة الدفع'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sale-settlement-summary')).hitTestable(),
          findsOneWidget,
        );
        expect(
          t
              .getRect(find.byKey(const ValueKey('sale-settlement-summary')))
              .bottom,
          lessThanOrEqualTo(t.view.physicalSize.height - 18),
        );
        await saleCapture(t, '$mode-${small ? '1024' : '1280'}-payment');
        expect(find.text('100 نوع · 102 قطعة'), findsOneWidget);
        expect(find.text('تأكيد تسجيل البيع').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'empty Enter never adds an item; search, arrows and barcode still choose deliberately',
    (t) async {
      await fixture.start(t, products: 200);
      await tapSection(t, 'البيع');
      final search = fixture.money('بحث بالاسم أو الكود أو الباركود · F2');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.text('0 نوع · 0 قطعة'), findsOneWidget);
      await t.enterText(search, 'Review1');
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(find.text('0 نوع · 0 قطعة'), findsOneWidget);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.text('1 نوع · 1 قطعة'), findsOneWidget);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.text('1 نوع · 1 قطعة'), findsOneWidget);
      await saleCapture(t, 'light-deliberate-selection');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'review zero removes one item and leaves focus on the next quantity; F2 returns to selection',
    (t) async {
      await fixture.start(t, products: 3);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '1');
      await t.enterText(quantityInput(2), '2');
      await t.pumpAndSettle();
      await t.tap(find.text('مراجعة ودفع'));
      await t.pumpAndSettle();
      await t.enterText(quantityInput(1), '0');
      await t.pumpAndSettle();
      expect(quantityInput(1), findsNothing);
      expect(t.widget<TextField>(quantityInput(2)).focusNode!.hasFocus, isTrue);
      expect(find.text('1 نوع · 2 قطعة'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.pumpAndSettle();
      expect(find.text('الخطوة 1 من 3'), findsOneWidget);
      expect(quantityInput(1), findsOneWidget);
      expect(
        t
            .widget<TextField>(
              fixture.money('بحث بالاسم أو الكود أو الباركود · F2'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid price and stock remain editable and block checkout without losing raw text',
    (t) async {
      final f = await fixture.start(t);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '11');
      await t.pumpAndSettle();
      expect(find.textContaining('تتجاوز المخزون'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('sale-next')))
            .onPressed,
        isNull,
      );
      await saleCapture(t, 'light-stock-error');
      await t.enterText(quantityInput(1), '1');
      final price = find.descendant(
        of: find.byKey(const ValueKey('checkout-price-1')),
        matching: find.byType(TextField),
      );
      await t.enterText(price, '12..');
      await t.pumpAndSettle();
      await saleCapture(t, 'light-price-error');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      await fixture.remount(t, f.container);
      await tapSection(t, 'البيع');
      expect(fixture.text(t, price), '12..');
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cash shortfall requires an explicit installment choice before saving',
    (t) async {
      final f = await fixture.start(
        t,
        rejectSale: false,
        printer: (_) async => ReceiptPrintOutcome.cancelled,
        beforeSnapshot: (uc) async {
          expect(
            await uc.createCustomer(name: 'عميل تجريبي'),
            isA<AppSuccess<Customer>>(),
          );
        },
      );
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.enterText(fixture.money('كاش'), '100');
      await t.pumpAndSettle();
      expect(find.textContaining('فيه مبلغ متبقي'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('sale-next')))
            .onPressed,
        isNull,
      );
      expect(f.saleWrites(), 0);
      await saleCapture(t, 'light-payment-mismatch');
      await choosePayment(t, 'تقسيط');
      await t.enterText(fixture.money('كاش'), '100');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('بدون عميل'));
      await t.tap(find.text('بدون عميل'));
      await t.pumpAndSettle();
      await t.tap(find.text('عميل تجريبي').last);
      await t.pumpAndSettle();
      await saleCapture(t, 'light-installment-payment');
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      final invoice = await f.db.select(f.db.saleInvoices).getSingle();
      expect(invoice.totalMinor, 20000);
      expect(invoice.paidMinor, 10000);
      expect(invoice.remainingMinor, 10000);
      expect((await f.db.select(f.db.products).get()).first.stockQty, 8);
      expect(
        (await t.runAsync(() => f.uc.dashboardSnapshot()))!.profitMinor,
        6000,
      );
      expect(find.text('تم حفظ الفاتورة'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'old installment interest never creates a displayed debt after full cash or wallet payment',
    (t) async {
      final f = await fixture.start(
        t,
        rejectSale: false,
        printer: (_) async => ReceiptPrintOutcome.cancelled,
      );
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t, payment: 'تقسيط');
      await t.enterText(fixture.money('فائدة اختيارية'), '100');
      await t.pumpAndSettle();
      await choosePayment(t, 'محفظة');
      var summary = t
          .widget<Text>(find.byKey(const ValueKey('sale-settlement-summary')))
          .data!;
      expect(summary, contains(Money(0).format()));
      expect(summary, contains(Money(20000).format()));
      await choosePayment(t, 'نقدي بالكامل');
      summary = t
          .widget<Text>(find.byKey(const ValueKey('sale-settlement-summary')))
          .data!;
      expect(summary, contains('المتبقي ${Money(0).format()}'));
      await saleCapture(t, 'light-full-payment-after-interest');
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      final invoice = await f.db.select(f.db.saleInvoices).getSingle();
      expect(invoice.remainingMinor, 0);
      expect(invoice.interestMinor, 0);
      expect(invoice.totalMinor, 20000);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'draft write failure is visible outside its menu and preserves entered quantities',
    (t) async {
      final f = await fixture.start(t);
      await tapSection(t, 'البيع');
      await f.db.customStatement('PRAGMA query_only=ON');
      try {
        await t.enterText(quantityInput(1), '٣');
        await t.pump(const Duration(seconds: 2));
        await t.pumpAndSettle();
        expect(find.textContaining('تعذر حفظ المسودة. اضغط'), findsOneWidget);
        expect(fixture.text(t, quantityInput(1)), '٣');
        await saleCapture(t, 'light-draft-storage-error');
      } finally {
        await f.db.customStatement('PRAGMA query_only=OFF');
      }
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      expect((await f.uc.saleDraft())!.items.single.qty, 3);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'PDF preparation failure leaves saved invoice identity and all lines searchable and retryable',
    (t) async {
      var fail = true;
      final f = await fixture.start(
        t,
        rejectSale: false,
        printer: (_) async => ReceiptPrintOutcome.failed,
        jobBuilder: (receipt, profile) async {
          if (fail) throw StateError('synthetic PDF failure');
          return SaleReceiptPdf.document(receipt, profile: profile);
        },
      );
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(1024, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      final invoice = await f.db.select(f.db.saleInvoices).getSingle();
      expect(find.text('تم حفظ الفاتورة'), findsOneWidget);
      expect(find.textContaining(invoice.invoiceNo), findsOneWidget);
      expect(
        find.text('الفاتورة محفوظة. تعذر تجهيز الطباعة، وتقدر تعيد المحاولة.'),
        findsOneWidget,
      );
      expect(find.text('صنف تجريبي Review1'), findsWidgets);
      await saleCapture(t, 'light-saved-pdf-failure');
      fail = false;
      await t.tap(find.text('إعادة تجهيز الطباعة'));
      await t.pumpAndSettle();
      expect(await f.db.select(f.db.saleInvoices).get(), hasLength(1));
      await t.tap(find.widgetWithText(FilledButton, 'طباعة'));
      await t.pumpAndSettle();
      expect(
        find.text('الفاتورة محفوظة، لكن تعذرت الطباعة. يمكنك إعادة المحاولة.'),
        findsOneWidget,
      );
      await saleCapture(t, 'light-saved-print-failure');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'printer double submission is ignored and retry uses the same saved document',
    (t) async {
      final gate = Completer<ReceiptPrintOutcome>();
      final jobs = <ReceiptPrintJob>[];
      final f = await fixture.start(
        t,
        rejectSale: false,
        printer: (job) async {
          jobs.add(job);
          return jobs.length == 1 ? gate.future : ReceiptPrintOutcome.submitted;
        },
      );
      await f.container.read(appThemeModeProvider.notifier).change('dark');
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '1');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      await saleCapture(t, 'dark-saved-receipt');
      final print = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'طباعة'))
          .onPressed!;
      print();
      print();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(jobs, hasLength(1));
      await saleCapture(t, 'dark-print-busy');
      gate.complete(ReceiptPrintOutcome.cancelled);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'طباعة'));
      await t.pumpAndSettle();
      expect(jobs, hasLength(2));
      expect(identical(jobs[0], jobs[1]), isTrue);
      expect(await f.db.select(f.db.saleInvoices).get(), hasLength(1));
      expect(f.saleWrites(), 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'short narrow sale keeps edits through review, payment, and returning to the catalog',
    (t) async {
      await fixture.start(t, products: 4);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(360, 640);
      t.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('sale-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sale-next')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('sale-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sale-next')));
      await t.pumpAndSettle();
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('sale-next')));
      await t.pumpAndSettle();
      expect(find.text('تأكيد تسجيل البيع').hitTestable(), findsOneWidget);
      await saleCapture(t, 'light-narrow-payment-360');
      t.view.resetViewInsets();
      await t.ensureVisible(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(1024, 720);
      await t.pumpAndSettle();
      expect(fixture.text(t, quantityInput(1)), '2');
      expect(find.text('الخطوة 1 من 3'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'long product identity and invalid raw edits stay legible at 125 percent',
    (t) async {
      const name =
          'ثلاجة منزلية نوفروست بمواصفات وموديل طويل جدًا مع تفاصيل اللون والسعة والضمان';
      await fixture.start(
        t,
        beforeSnapshot: (uc) async {
          await (uc.db.update(
            uc.db.products,
          )..where((p) => p.id.equals(1))).write(
            const ProductsCompanion(
              name: Value(name),
              category: Value('أجهزة منزلية'),
            ),
          );
        },
      );
      await tapSection(t, 'البيع');
      t.view.physicalSize = const Size(1024, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      expect(find.byTooltip(name), findsOneWidget);
      await t.longPress(find.text(name));
      await t.pumpAndSettle();
      await saleCapture(t, 'light-long-product-tooltip');
      expect(find.text('0 نوع · 0 قطعة'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pending sale explains that retry verifies the same request and restores the original draft',
    (t) async {
      final f = await fixture.start(t);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '3');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.tap(find.text('تأكيد تسجيل البيع'));
      await t.pumpAndSettle();
      expect(find.text('التحقق من نتيجة حفظ البيع'), findsOneWidget);
      expect(find.text('Review: sale has not committed'), findsOneWidget);
      await saleCapture(t, 'light-pending-verification');
      await t.tap(find.text('العودة لتعديل المسودة'));
      await t.pumpAndSettle();
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      expect(fixture.text(t, quantityInput(1)), '3');
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'closed shift opens from payment without discarding the selected products',
    (t) async {
      final f = await fixture.start(
        t,
        liveSnapshot: true,
        beforeSnapshot: (uc) async {
          expect(
            await uc.closeShift(0, operationKey: uc.newShiftOperationKey()),
            isA<AppSuccess<Shift>>(),
          );
        },
      );
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      final action = find.text('فتح وردية والعودة للفاتورة');
      await t.ensureVisible(action);
      await t.tap(action);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(find.text('اكتب المبلغ، ولو مفيش كاش اكتب صفر'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'الرصيد الافتتاحي'),
        '0',
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(find.text('1 نوع · 2 قطعة'), findsOneWidget);
      expect(
        (await t.runAsync(() => f.uc.dashboardSnapshot()))!.openShift,
        isNotNull,
      );
      expect(fixture.text(t, fixture.money('كاش')), '200.00');
      await saleCapture(t, 'light-opened-shift-kept-sale');
      expect(t.takeException(), isNull);
    },
  );
}

Future<void> choosePayment(WidgetTester t, String label) async {
  final selector = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField && w.decoration.labelText == 'طريقة الدفع',
  );
  await t.ensureVisible(selector);
  await t.tap(selector);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}
