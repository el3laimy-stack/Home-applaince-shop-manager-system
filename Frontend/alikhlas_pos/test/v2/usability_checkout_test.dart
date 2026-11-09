import '../support/checkout.dart';
import 'package:flutter/services.dart';
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    '200 products, 100 selections without barcode, exact quantities and cash review',
    (tester) async {
      final f = await start(tester, 200);
      await tapSection(tester, 'البيع');
      await tester.pumpAndSettle();
      final search = find.widgetWithText(
        TextField,
        'بحث بالاسم أو الكود أو الباركود · F2',
      );
      for (var i = 1; i <= 100; i++) {
        await tester.enterText(search, 'DEMO-${i.toString().padLeft(3, '0')}');
        await tester.pump();
        final qty = find.descendant(
          of: find.byKey(ValueKey('checkout-qty-$i')),
          matching: find.byType(TextField),
        );
        await tester.enterText(qty, i == 1 ? '٣' : '1');
        await tester.pump();
      }
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('100 نوع · 102 قطعة'), findsOneWidget);
      await tester.tap(find.text('حفظ مسودة'));
      await tester.pumpAndSettle();
      final draft = await f.uc.saleDraft();
      expect(draft!.items, hasLength(100));
      expect(draft.items.first.qty, 3);
      expect(draft.cashMinor, 1020000);
      await tester.tap(find.text('مراجعة ودفع'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة الدفع'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'كاش'))
            .controller!
            .text,
        '10200.00',
      );
      expect(find.text('تأكيد تسجيل البيع').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
    },
  );

  testWidgets(
    'purchase selects 100 of 200 products with quantities and costs without barcode',
    (tester) async {
      final f = await start(tester, 200);
      await tapSection(tester, 'المشتريات');
      final search = find.widgetWithText(
        TextField,
        'بحث بالاسم أو الكود أو الباركود · F2',
      );
      for (var i = 1; i <= 100; i++) {
        await tester.enterText(search, 'DEMO-${i.toString().padLeft(3, '0')}');
        await tester.pump();
        await tester.enterText(quantityInput(i), '٢');
        if (i == 1) await tester.enterText(costInput(i), '٧٥');
        await tester.pump();
      }
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('100 نوع · 200 قطعة'), findsOneWidget);
      await tester.tap(find.text('حفظ مسودة'));
      await tester.pumpAndSettle();
      final draft = (await f.uc.purchaseDraft())!;
      expect(draft.items, hasLength(100));
      expect(draft.items.first.unitCostMinor, 7500);
      expect(draft.cashMinor, 1401000);
      await reachCheckout(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'كاش'))
            .controller!
            .text,
        '14010.00',
      );
      expect(await f.db.select(f.db.purchaseInvoices).get(), isEmpty);
      expect(
        (await f.db.select(f.db.products).get()).every((p) => p.stockQty == 10),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard searches Arabic, selects highlighted results, and tabs through virtual rows',
    (tester) async {
      final f = await start(tester, 20);
      await tapSection(tester, 'البيع');
      final catalog = (await f.uc.workbenchSnapshot()).products
          .where((p) => p.isActive)
          .toList();
      final search = find.widgetWithText(
        TextField,
        'بحث بالاسم أو الكود أو الباركود · F2',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, 'مُنتَج تَجريبي ١٩');
      await tester.pumpAndSettle();
      expect(quantityInput(19), findsOneWidget);
      expect(quantityInput(1), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final raw = (await f.uc.activeInvoiceWorkspace('sale'));
      // Autosave is debounced; explicit save below proves the chosen result.
      expect(raw == null || raw.kind == 'sale', isTrue);
      await tester.tap(find.text('حفظ مسودة'));
      await tester.pumpAndSettle();
      expect((await f.uc.saleDraft())!.items.single.productId, 19);
      await tester.tap(quantityInput(1));
      await tester.pumpAndSettle();
      // Each row now has quantity then sale price before the next row.
      for (var i = 0; i < 18; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<TextField>(quantityInput(catalog[9].id))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(quantityInput(catalog[15].id).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
    },
  );

  testWidgets(
    'invalid raw quantities survive autosave, suspension, and resuming another invoice',
    (tester) async {
      final f = await start(tester, 2);
      await tapSection(tester, 'البيع');
      await tester.pumpAndSettle();
      final qty = find.descendant(
        of: find.byKey(const ValueKey('checkout-qty-1')),
        matching: find.byType(TextField),
      );
      await tester.enterText(qty, '-');
      await tester.tap(find.text('حفظ مسودة'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'مراجعة ودفع'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('تعليق وفاتورة جديدة'));
      await tester.pumpAndSettle();
      await tester.enterText(qty, '2');
      await tester.tap(find.text('حفظ مسودة'));
      await tester.pumpAndSettle();
      final rows = await f.uc.invoiceWorkspaces('sale');
      expect(rows, hasLength(2));
      await tester.tap(find.text('الفواتير المعلقة'));
      await tester.pumpAndSettle();
      final old = rows.singleWhere((r) => r.state == 'suspended');
      await tester.tap(find.text(old.label).last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(qty).controller!.text, '-');
      expect(await f.db.select(f.db.stockMovements).get(), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<({AppDatabase db, V2UseCases uc})> start(
  WidgetTester tester,
  int products,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 7, 12));
  await uc.bootstrap(createDefaultOwner: true);
  final owner = await ok(uc.login('owner', 'owner123'));
  await ok(uc.changePassword(owner.id, 'usability-password'));
  await ok(uc.openShift(0, operationKey: uc.newShiftOperationKey()));
  for (var i = 1; i <= products; i++) {
    await ok(
      uc.createProduct(
        operationKey: uc.newOpeningStockOperationKey(),
        name: 'منتج تجريبي $i',
        barcode: 'DEMO-${i.toString().padLeft(3, '0')}',
        category: i.isEven ? 'أجهزة صغيرة' : 'أجهزة كبيرة',
        salePriceMinor: 10000,
        openingQty: 10,
        openingCostMinor: 7000,
      ),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appClockProvider.overrideWithValue(() => DateTime(2026, 11, 7, 12)),
      ],
      child: const ALIkhlasV2App(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'كلمة المرور'),
    'usability-password',
  );
  await tester.tap(find.text('دخول'));
  await tester.pumpAndSettle();
  return (db: db, uc: uc);
}

Future<T> ok<T>(Future<AppResult<T>> action) async {
  final result = await action;
  if (result is AppSuccess<T>) return result.value;
  if (result is AppFailure<T>) fail(result.message);
  throw StateError('$result');
}
