import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/printing/sale_receipt_pdf.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/checkout.dart';

Future<
  ({
    AppDatabase db,
    V2UseCases uc,
    ProviderContainer container,
    int Function() saleWrites,
  })
>
start(
  WidgetTester t, {
  int products = 2,
  bool rejectSale = true,
  Completer<void>? saleGate,
  Future<ReceiptPrintOutcome> Function(ReceiptPrintJob)? printer,
}) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 8, 12));
  await uc.bootstrap(createDefaultOwner: false);
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'review',
          passwordHash: 'not-used',
          fullName: 'Review',
          mustChangePassword: const Value(false),
        ),
      );
  final owner = await db.select(db.users).getSingle();
  for (var i = 1; i <= products; i++) {
    final r = await uc.createProduct(
      operationKey: uc.newOpeningStockOperationKey(),
      name: 'صنف تجريبي Review$i',
      category: i.isEven ? 'Even' : 'Odd',
      salePriceMinor: 10000,
      openingQty: 10,
      openingCostMinor: 7000,
    );
    expect(r, isA<AppSuccess<Product>>());
  }
  final shift = await uc.openShift(0, operationKey: uc.newShiftOperationKey());
  expect(shift, isA<AppSuccess<Shift>>());
  final snapshot = await t.runAsync(() => uc.workbenchSnapshot());
  var saleWrites = 0;
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      useCasesProvider.overrideWithValue(uc),
      appClockProvider.overrideWithValue(() => DateTime(2026, 11, 8, 12)),
      bootstrapProvider.overrideWith((ref) async {}),
      if (printer != null)
        receiptDocumentPrinterProvider.overrideWithValue(printer),
      workbenchProvider.overrideWith((ref) async => snapshot!),
      saleWriterProvider.overrideWithValue(({
        operationKey,
        customerId,
        required items,
        required payments,
        installmentTerms,
        required discountMinor,
      }) async {
        saleWrites++;
        if (rejectSale) {
          return const AppFailure<int>('Review: sale has not committed');
        }
        if (saleGate != null) await saleGate.future;
        return uc.submitPendingSale(
          PendingSale(
            operationKey: operationKey!,
            customerId: customerId,
            items: items,
            payments: payments,
            installmentTerms: installmentTerms,
            discountMinor: discountMinor,
          ),
        );
      }),
    ],
  );
  container.read(currentOwnerProvider.notifier).setOwner(owner);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    container.dispose();
  });
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: ValueKey('invoice-review'),
        child: ALIkhlasV2App(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (db: db, uc: uc, container: container, saleWrites: () => saleWrites);
}

Finder money(String label) => find.widgetWithText(TextField, label);
String text(WidgetTester t, Finder f) =>
    t.widget<TextField>(f).controller!.text;
void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('INVOICE_REVIEW_DIR') == '') return;
    final loader = FontLoader('Cairo');
    for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Cairo-$name.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  additionalTests();
  testWidgets('purchase keeps an entered wallet payment after quantity edit', (
    t,
  ) async {
    await start(t);
    await tapSection(t, 'المشتريات');
    await t.enterText(quantityInput(1), '1');
    await t.pumpAndSettle();
    await reachCheckout(t);
    await t.enterText(money('محفظة'), '25');
    await t.pumpAndSettle();
    await t.tap(find.text('العودة للأصناف'));
    await t.pumpAndSettle();
    await t.enterText(quantityInput(1), '2');
    await t.pumpAndSettle();
    await reachCheckout(t);
    expect(
      text(t, money('محفظة')),
      '25',
      reason:
          'Editing quantity must not silently erase a manually entered wallet payment',
    );
  });
  testWidgets('clearing a wallet draft resets the new sale to cash full', (
    t,
  ) async {
    await start(t);
    await tapSection(t, 'البيع');
    await t.enterText(quantityInput(1), '1');
    await t.pumpAndSettle();
    await reachCheckout(t, payment: 'محفظة');
    await t.tap(find.text('حفظ مسودة'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'مسح المسودة'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'مسح المسودة'));
    await t.pumpAndSettle();
    await t.enterText(quantityInput(1), '1');
    await t.pumpAndSettle();
    await reachCheckout(t);
    expect(
      find.text('نقدي بالكامل'),
      findsOneWidget,
      reason:
          'A new invoice after deleting a draft must use the documented cash default',
    );
  });
  testWidgets('returning an uncommitted request restores automatic cash state', (
    t,
  ) async {
    await start(t);
    await tapSection(t, 'البيع');
    await t.enterText(quantityInput(1), '٢');
    await t.pumpAndSettle();
    await reachCheckout(t);
    expect(text(t, money('كاش')), '200.00');
    await t.tap(find.widgetWithText(FilledButton, 'تأكيد تسجيل البيع'));
    await t.pumpAndSettle();
    await t.tap(find.text('العودة لتعديل المسودة'));
    await t.pumpAndSettle();
    await t.tap(find.text('العودة للأصناف'));
    await t.pumpAndSettle();
    await t.enterText(quantityInput(1), '3');
    await t.pumpAndSettle();
    await reachCheckout(t);
    expect(
      text(t, money('كاش')),
      '300.00',
      reason:
          'The original draft used automatic cash, so recovery must retain it',
    );
  });
  testWidgets('Tab leaves the final quantity field', (t) async {
    await start(t);
    await tapSection(t, 'البيع');
    await t.tap(quantityInput(2));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(quantityInput(2)).focusNode!.hasFocus,
      isFalse,
      reason:
          'Tab at the final row must proceed to another control rather than trap focus',
    );
  });
  for (final section in ['البيع', 'المشتريات']) {
    testWidgets(
      '$section: a new suspended invoice does not inherit selected-only filtering',
      (t) async {
        await start(t);
        await tapSection(t, section);
        await t.enterText(quantityInput(1), '1');
        await t.pumpAndSettle();
        final search = find.widgetWithText(
          TextField,
          'بحث بالاسم أو الكود أو الباركود · F2',
        );
        await t.enterText(search, 'Review1');
        await t.pumpAndSettle();
        await t.tap(find.text('كل التصنيفات'));
        await t.pumpAndSettle();
        await t.tap(find.text('Odd').last);
        await t.pumpAndSettle();
        await t.tap(find.text('المختار فقط (1)'));
        await t.pumpAndSettle();
        await t.tap(find.text('تعليق وفاتورة جديدة'));
        await t.pumpAndSettle();
        expect(
          find.text('لا توجد أصناف مطابقة'),
          findsNothing,
          reason:
              'A fresh empty invoice must show available products, not inherit the prior selected-only filter',
        );
        expect(quantityInput(1), findsOneWidget);
        expect(quantityInput(2), findsOneWidget);
        expect(text(t, search), '');
        expect(find.text('كل التصنيفات'), findsOneWidget);
      },
    );
  }
}

Future<void> remount(WidgetTester t, ProviderContainer container) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: ValueKey('invoice-review'),
        child: ALIkhlasV2App(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void additionalTests() {
  testWidgets(
    'legacy v2 purchase wallet disables the old incorrect automatic cash flag',
    (t) async {
      final f = await start(t);
      await tapSection(t, 'المشتريات');
      await t.enterText(quantityInput(1), '1');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.enterText(money('محفظة'), '25');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      final row = (await f.uc.activeInvoiceWorkspace('purchase'))!;
      final payload = decodeWorkspace(row.payload);
      payload['editor']['automaticCash'] =
          true; // Persisted by 1.2.0 even after editing the wallet.
      await f.uc.saveInvoiceWorkspace(
        kind: 'purchase',
        id: row.id,
        expectedRevision: row.revision,
        payload: jsonEncode(payload),
      );
      await remount(t, f.container);
      await tapSection(t, 'المشتريات');
      await t.pumpAndSettle();
      expect(text(t, money('محفظة')), '25');
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('محفظة')), '25');
      expect(text(t, money('كاش')), '70.00');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      final restored = (await f.uc.activeInvoiceWorkspace('purchase'))!;
      expect(
        decodeWorkspace(restored.payload)['editor']['automaticCash'],
        isFalse,
      );
    },
  );

  for (final section in ['البيع', 'المشتريات']) {
    testWidgets('$section: manual cash survives quantities and restart', (
      t,
    ) async {
      final f = await start(t);
      await tapSection(t, section);
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      await t.enterText(money('كاش'), '٥٠');
      await t.pumpAndSettle();
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      await t.enterText(quantityInput(1), '3');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '٥٠');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      await remount(t, f.container);
      await tapSection(t, section);
      await t.pumpAndSettle();
      expect(text(t, money('كاش')), '٥٠');
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      await t.enterText(quantityInput(1), '4');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '٥٠');
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
      expect(await f.db.select(f.db.purchaseInvoices).get(), isEmpty);
    });
    testWidgets(
      '$section: failed save retains edits and retry suspends latest data',
      (t) async {
        final f = await start(t);
        await tapSection(t, section);
        await t.enterText(quantityInput(1), '1');
        await t.tap(find.text('حفظ مسودة'));
        await t.pumpAndSettle();
        await f.db.customStatement('PRAGMA query_only=ON');
        try {
          await t.enterText(quantityInput(1), '٣');
          await t.tap(find.text('تعليق وفاتورة جديدة'));
          await t.pumpAndSettle();
          expect(text(t, quantityInput(1)), '٣');
          final rows = await f.db.select(f.db.checkoutDrafts).get();
          expect(rows, hasLength(1));
          expect(rows.single.state, 'editing');
          expect(find.textContaining('تعذر حفظ الفاتورة'), findsWidgets);
        } finally {
          await f.db.customStatement('PRAGMA query_only=OFF');
        }
        await t.tap(find.text('تعليق وفاتورة جديدة'));
        await t.pumpAndSettle();
        final kind = section == 'البيع' ? 'sale' : 'purchase';
        final row = (await f.uc.invoiceWorkspaces(kind)).single;
        expect(row.state, 'suspended');
        expect(decodeWorkspace(row.payload)['editor']['quantities']['1'], '٣');
        expect(text(t, quantityInput(1)), '');
        expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
        expect(await f.db.select(f.db.purchaseInvoices).get(), isEmpty);
      },
    );
  }
  testWidgets(
    'purchase recovery restores automatic cash from workspace editor',
    (t) async {
      final f = await start(t);
      await tapSection(t, 'المشتريات');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '140.00');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      final draft = (await f.uc.purchaseDraft())!;
      await f.uc.stagePendingPurchase(
        PendingPurchase(
          operationKey: f.uc.newPurchaseOperationKey(),
          items: draft.items,
          payments: [PaymentInput(PaymentMethod.cash, draft.cashMinor)],
        ),
      );
      await remount(t, f.container);
      await tapSection(t, 'المشتريات');
      await t.tap(find.text('العودة لتعديل المسودة'));
      await t.pumpAndSettle();
      await t.tap(find.text('العودة للأصناف'));
      await t.pumpAndSettle();
      await t.enterText(quantityInput(1), '3');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '210.00');
      expect(await f.db.select(f.db.purchaseInvoices).get(), isEmpty);
    },
  );
  for (final section in ['البيع', 'المشتريات']) {
    testWidgets(
      '$section: Shift Tab leaves first quantity and Tab leaves final cell',
      (t) async {
        await start(t);
        await tapSection(t, section);
        await t.tap(quantityInput(1));
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(quantityInput(1)).focusNode!.hasFocus,
          isFalse,
        );
        final last = section == 'البيع' ? quantityInput(2) : costInput(2);
        await t.tap(last);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        expect(t.widget<TextField>(last).focusNode!.hasFocus, isFalse);
      },
    );
  }
  testWidgets(
    'legacy draft preserves manual payment without inferring automatic cash',
    (t) async {
      final f = await start(t);
      await f.uc.saveInvoiceWorkspace(
        kind: 'sale',
        payload: SaleDraft(
          items: [
            const SaleLineInput(productId: 1, qty: 1, unitPriceMinor: 10000),
          ],
          cashMinor: 10000,
          walletMinor: 0,
          discountMinor: 0,
          interestMinor: 0,
          installmentCount: 3,
          firstDueDate: DateTime(2026, 12, 8),
          periodDays: 30,
          savedAt: DateTime(2026, 11, 8),
        ).encode(),
      );
      await remount(t, f.container);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await reachCheckout(t);
      expect(text(t, money('كاش')), '100.00');
    },
  );
  testWidgets(
    '100 of 200 without barcodes survives restart, commits once and reprints safely',
    (t) async {
      final gate = Completer<void>();
      final printed = <ReceiptPrintJob>[];
      final f = await start(
        t,
        products: 200,
        rejectSale: false,
        saleGate: gate,
        printer: (job) async {
          printed.add(job);
          return [
            ReceiptPrintOutcome.cancelled,
            ReceiptPrintOutcome.failed,
            ReceiptPrintOutcome.submitted,
          ][printed.length - 1];
        },
      );
      await tapSection(t, 'البيع');
      final search = find.widgetWithText(
        TextField,
        'بحث بالاسم أو الكود أو الباركود · F2',
      );
      final selectionWatch = Stopwatch()..start();
      for (var i = 1; i <= 100; i++) {
        await t.enterText(search, 'Review$i');
        await t.pump();
        await t.enterText(quantityInput(i), i == 1 ? '٣' : '1');
        await t.pump();
      }
      selectionWatch.stop();
      await t.enterText(search, '');
      await t.pumpAndSettle();
      expect(find.text('100 نوع · 102 قطعة'), findsOneWidget);
      await reachCheckout(t, payment: 'نقدي ومحفظة');
      await t.enterText(money('خصم الفاتورة'), '٢٠');
      await t.enterText(money('كاش'), '١٠٠٠٠');
      await t.enterText(money('محفظة'), '١٨٠');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      final before = (await f.uc.activeInvoiceWorkspace('sale'))!.payload;
      await remount(t, f.container);
      await tapSection(t, 'البيع');
      await t.pumpAndSettle();
      expect(find.text('100 نوع · 102 قطعة'), findsOneWidget);
      expect(text(t, money('خصم الفاتورة')), '٢٠');
      expect(text(t, money('كاش')), '١٠٠٠٠');
      expect(text(t, money('محفظة')), '١٨٠');
      expect((await f.uc.activeInvoiceWorkspace('sale'))!.payload, before);
      await captureReview(t, '01-saved-100-items');
      final confirm = find.widgetWithText(FilledButton, 'تأكيد تسجيل البيع');
      await t.tap(confirm);
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(f.saleWrites(), 1);
      gate.complete();
      await t.pumpAndSettle();
      final invoice = (await f.db.select(f.db.saleInvoices).get()).single;
      expect(invoice.totalMinor, 1018000);
      expect(invoice.paidMinor, 1018000);
      expect(invoice.remainingMinor, 0);
      expect(await f.db.select(f.db.saleItems).get(), hasLength(100));
      expect(await f.uc.saleDraft(), isNull);
      expect(await f.db.select(f.db.payments).get(), hasLength(2));
      final ledgerCount = (await f.db.select(f.db.ledgerEntries).get()).length;
      for (var attempt = 0; attempt < 3; attempt++) {
        await t.tap(find.widgetWithText(FilledButton, 'طباعة'));
        await t.pumpAndSettle();
        expect(await f.db.select(f.db.saleInvoices).get(), hasLength(1));
        expect(await f.db.select(f.db.payments).get(), hasLength(2));
        expect(
          await f.db.select(f.db.ledgerEntries).get(),
          hasLength(ledgerCount),
        );
      }
      expect(printed, hasLength(3));
      expect(identical(printed[0], printed[1]), isTrue);
      expect(identical(printed[1], printed[2]), isTrue);
      expect(printed[0].receipt.lines, hasLength(100));
      expect(
        find.text('تم إرسال طلب الطباعة. الفاتورة محفوظة.'),
        findsOneWidget,
      );
      final products = await f.db.select(f.db.products).get();
      expect(products.firstWhere((p) => p.id == 1).stockQty, 7);
      expect(products.firstWhere((p) => p.id == 100).stockQty, 9);
      expect(products.firstWhere((p) => p.id == 101).stockQty, 10);
      await captureReview(t, '02-reprinted-100-items');
      const reviewDir = String.fromEnvironment('INVOICE_REVIEW_DIR');
      if (reviewDir.isNotEmpty) {
        await t.runAsync(() async {
          await File('$reviewDir/workflow-metrics.json').writeAsString(
            jsonEncode({
              'environment':
                  'Flutter widget test, Cairo fonts, 1280x800, synthetic memory database',
              'products': 200,
              'selectedProducts': 100,
              'pieces': 102,
              'selectionMilliseconds': selectionWatch.elapsedMilliseconds,
              'saleWrites': f.saleWrites(),
              'printedAttempts': printed.length,
              'note':
                  'Scripted debug-test duration, not customer task time or a production-device benchmark.',
            }),
          );
        });
      }
      expect(t.takeException(), isNull);
    },
  );
}

Future<void> captureReview(WidgetTester tester, String name) async {
  const path = String.fromEnvironment('INVOICE_REVIEW_DIR');
  if (path.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('invoice-review')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
