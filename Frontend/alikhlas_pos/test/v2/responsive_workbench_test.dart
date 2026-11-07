import '../support/checkout.dart';
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _customerName = 'أحمد محمد عبد الرحمن — عميل تجريبي';
const _supplierName = 'شركة النور لتجارة وتوريد الأجهزة المنزلية';
const _productName = 'ثلاجة شارب نوفروست ١٨ قدم — فضي';
const _otherProductName = 'غسالة توشيبا فوق أوتوماتيك ١٠ كجم';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final scale in [1.0, 1.25]) {
    testWidgets(
      'party selection, details and exact amounts survive resize at $scale',
      (tester) async {
        final fixture = await _start(tester, scale: scale);
        await tapSection(tester, 'العملاء والموردون');
        await tester.pumpAndSettle();
        await _chooseSupplier(tester);

        tester.view.physicalSize = const Size(1024, 720);
        await tester.pumpAndSettle();
        expect(find.text('اختيار عميل أو مورد'), findsOneWidget);
        expect(
          tester.getSize(find.text(_supplierName)).width,
          greaterThan(300),
        );
        expect(find.textContaining('علينا للمورد'), findsWidgets);
        expect(
          find.widgetWithText(OutlinedButton, 'كشف الحساب').hitTestable(),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'سداد').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // The same search/filter controls work in the picker and persist across
        // layout switches without losing the selected party.
        await tester.tap(find.text('اختيار عميل أو مورد'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'بحث باسم أو هاتف'),
          'النور',
        );
        await tester.tap(find.text('موردين'));
        await tester.pumpAndSettle();
        expect(find.text(_customerName), findsNothing);
        await tester.tap(find.text(_supplierName).last);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1600, 900);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'بحث باسم أو هاتف'),
              )
              .controller!
              .text,
          'النور',
        );
        expect(find.textContaining('علينا للمورد'), findsWidgets);
        expect(tester.takeException(), isNull);

        // Restore the customer using the directory before returning to minimum
        // size, then prove the lower preview can be reached by scrolling.
        await tester.enterText(
          find.widgetWithText(TextField, 'بحث باسم أو هاتف'),
          '',
        );
        await tester.tap(find.text('الكل'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_customerName).first);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1024, 720);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.text(_customerName).first).width,
          greaterThan(300),
        );
        final amount = find.text(const Money(138571).format()).first;
        await Scrollable.ensureVisible(tester.element(amount), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(amount.hitTestable(), findsOneWidget);
        _expectUnabridged(tester, amount);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/responsive_parties_1024_${(scale * 100).round()}.png',
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          (await fixture.db.select(fixture.db.saleInvoices).get()).length,
          1,
        );
      },
    );

    testWidgets(
      'sale cart stays separate from scrollable payment fields at $scale',
      (tester) async {
        final fixture = await _start(tester, scale: scale);
        await tapSection(tester, 'البيع');
        await tester.pumpAndSettle();
        await tester.tap(find.text(_productName));
        await tester.tap(find.text(_otherProductName));
        await tester.pumpAndSettle();
        await _edit(tester, 'كاش', '1000');
        await _edit(tester, 'عدد الأقساط', '4');
        await _edit(tester, 'فائدة اختيارية', '50');

        tester.view.physicalSize = const Size(1024, 720);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('checkout-payment-scroll')),
          findsOneWidget,
        );
        expect(find.text('العودة للأصناف').hitTestable(), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'كاش'))
              .controller!
              .text,
          '1000',
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'عدد الأقساط'))
              .controller!
              .text,
          '4',
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'فائدة اختيارية'),
              )
              .controller!
              .text,
          '50',
        );
        expect(find.text('تأكيد تسجيل البيع').hitTestable(), findsOneWidget);
        expect(find.text('حفظ مسودة').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/responsive_pos_1024_${(scale * 100).round()}.png',
          ),
        );

        // Save a real draft through the resized form and verify durable values.
        await tester.tap(find.text('حفظ مسودة'));
        await tester.pumpAndSettle();
        expect(find.text('تم حفظ المسودة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          (await fixture.db.select(fixture.db.saleInvoices).get()).length,
          1,
        );
        final draft = await fixture.uc.saleDraft();
        expect(draft, isNotNull);
        expect(draft!.items, hasLength(2));
        expect(draft.cashMinor, 100000);
        expect(draft.interestMinor, 5000);
        expect(draft.installmentCount, 4);
      },
    );
  }

  testWidgets(
    'large installment amounts remain fully laid out in the party preview',
    (tester) async {
      await _start(tester, scale: 1.25, largeAmount: true);
      await tapSection(tester, 'العملاء والموردون');
      await tester.pumpAndSettle();
      final amount = find.text(const Money(900000000000000000).format()).last;
      await tester.ensureVisible(amount);
      await tester.pumpAndSettle();
      _expectUnabridged(tester, amount);
      expect(amount.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectUnabridged(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.data!.length),
  );
  for (final box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-0.5));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
  }
}

Future<void> _chooseSupplier(WidgetTester tester) async {
  if (find.text('اختيار عميل أو مورد').evaluate().isNotEmpty) {
    await tester.tap(find.text('اختيار عميل أو مورد'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(_supplierName).last);
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, String label, String value) async {
  await reachCheckout(tester);
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<({AppDatabase db, V2UseCases uc})> _start(
  WidgetTester tester, {
  required double scale,
  bool largeAmount = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 7, 12));
  await uc.bootstrap(createDefaultOwner: true);
  final owner = await _ok(uc.login('owner', 'owner123'));
  await _ok(uc.changePassword(owner.id, 'test-layout-password'));
  await _ok(uc.openShift(5000000, operationKey: uc.newShiftOperationKey()));
  final price = largeAmount ? 900000000000000000 : 2250000;
  final product = await _ok(
    uc.createProduct(
      operationKey: uc.newOpeningStockOperationKey(),
      name: _productName,
      barcode: 'DEMO-001',
      salePriceMinor: price,
      openingQty: 8,
      openingCostMinor: 1575000,
    ),
  );
  await _ok(
    uc.createProduct(
      operationKey: uc.newOpeningStockOperationKey(),
      name: _otherProductName,
      barcode: 'DEMO-002',
      salePriceMinor: 1450000,
      openingQty: 8,
      openingCostMinor: 1015000,
    ),
  );
  final customer = await _ok(
    uc.createCustomer(name: _customerName, phone: '01000000000'),
  );
  final supplier = await _ok(
    uc.createSupplier(name: _supplierName, phone: '01100000000'),
  );
  await _ok(
    uc.createPurchase(
      operationKey: uc.newPurchaseOperationKey(),
      supplierId: supplier.id,
      items: [
        PurchaseLineInput(
          productId: product.id,
          qty: 2,
          unitCostMinor: 1575000,
        ),
      ],
      payments: [],
    ),
  );
  await _ok(
    uc.createSale(
      operationKey: uc.newSaleOperationKey(),
      customerId: customer.id,
      items: [
        SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: price),
      ],
      payments: largeAmount
          ? []
          : [const PaymentInput(PaymentMethod.cash, 450000)],
      installmentTerms: InstallmentTerms(
        partyId: customer.id,
        count: largeAmount ? 1 : 14,
        firstDueDate: DateTime(2026, 11, 7),
        interestMinor: largeAmount ? 0 : 140000,
      ),
    ),
  );
  // Invoice timestamps default to SQLite CURRENT_TIMESTAMP, independently of
  // the use-case clock. Freeze them as well so the visual baseline is stable.
  await db
      .update(db.saleInvoices)
      .write(
        SaleInvoicesCompanion(createdAt: Value(DateTime(2026, 11, 7, 12))),
      );
  await db
      .update(db.purchaseInvoices)
      .write(
        PurchaseInvoicesCompanion(createdAt: Value(DateTime(2026, 11, 7, 12))),
      );
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
    'test-layout-password',
  );
  await tester.tap(find.text('دخول'));
  await tester.pumpAndSettle();
  return (db: db, uc: uc);
}

Future<T> _ok<T>(Future<AppResult<T>> action) async {
  final result = await action;
  if (result is AppSuccess<T>) return result.value;
  if (result is AppFailure<T>) fail(result.message);
  throw StateError('Unexpected result: $result');
}
