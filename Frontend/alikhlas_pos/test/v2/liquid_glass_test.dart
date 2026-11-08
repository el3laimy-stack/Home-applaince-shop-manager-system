import '../support/visual_binding.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:alikhlas_pos/v2/app/app_theme.dart';
import 'package:alikhlas_pos/v2/app/design_tokens.dart';
import 'package:alikhlas_pos/v2/app/liquid_glass.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/printing/sale_receipt_pdf.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../support/checkout.dart';
import 'invoice_readiness_test.dart' show start, remount, text, money;

void main() {
  initializeVisualTests();
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final dark in [false, true]) {
    test(
      '${dark ? 'dark' : 'light'} text, controls and primary actions maintain contrast',
      () {
        final c = LiquidGlassColors(dark: dark);
        for (final background in [Colors.black, Colors.white, c.stage]) {
          final stage = Color.alphaBlend(
            c.stage.withValues(alpha: .84),
            background,
          );
          for (final chrome in [false, true]) {
            for (final stop in c.surfaceGradient(chrome: chrome).colors) {
              final surface = Color.alphaBlend(stop, stage);
              expect(contrast(c.ink, surface), greaterThanOrEqualTo(4.5));
              expect(contrast(c.muted, surface), greaterThanOrEqualTo(4.5));
            }
          }
        }
        expect(contrast(c.ink, c.control), greaterThanOrEqualTo(4.5));
        expect(contrast(c.primary, c.selected), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      },
    );

    testWidgets(
      '${dark ? 'dark' : 'light'} respects high contrast and reduced motion',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: buildV2Theme(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(
                highContrast: true,
                disableAnimations: true,
              ),
              child: const Scaffold(
                body: LiquidGlassSurface(
                  enableBlur: true,
                  child: SizedBox(
                    width: 300,
                    height: 180,
                    child: Text('فاتورة واضحة'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        final gesture = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        await gesture.addPointer(location: const Offset(700, 500));
        await gesture.moveTo(const Offset(80, 80));
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, isFalse);
        await gesture.removePointer();
        expect(t.takeException(), isNull);
      },
    );
  }

  test(
    'appearance persists across database reopening and rejects invalid values',
    () async {
      final dir = await Directory.systemTemp.createTemp('appearance-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/shop.db');
      var db = AppDatabase(NativeDatabase(file));
      var uc = V2UseCases(db);
      expect(await uc.themeMode(), 'light');
      await uc.updateThemeMode('dark');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      uc = V2UseCases(db);
      expect(await uc.themeMode(), 'dark');
      expect(() => uc.updateThemeMode('unknown'), throwsArgumentError);
      expect(await uc.themeMode(), 'dark');
      await uc.updateThemeMode('system');
      expect(await uc.themeMode(), 'system');
    },
  );

  testWidgets(
    'theme switch preserves invoice editor, manual payments and focus',
    (t) async {
      final f = await start(t);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '٣');
      final price = find.descendant(
        of: find.byKey(const ValueKey('checkout-price-1')),
        matching: find.byType(TextField),
      );
      await t.enterText(price, '١٢٠٫٥٠');
      await t.pumpAndSettle();
      final controller = t.widget<TextField>(quantityInput(1)).controller;
      final focus = t.widget<TextField>(price).focusNode;
      await f.container.read(appThemeModeProvider.notifier).change('dark');
      await t.pumpAndSettle();
      expect(
        identical(t.widget<TextField>(quantityInput(1)).controller, controller),
        isTrue,
      );
      expect(identical(t.widget<TextField>(price).focusNode, focus), isTrue);
      expect(focus!.hasFocus, isTrue);
      expect(text(t, price), '١٢٠٫٥٠');
      await reachCheckout(t);
      await t.enterText(money('كاش'), '٥٠');
      await t.tap(find.byKey(const ValueKey('theme-toggle')));
      await t.pumpAndSettle();
      expect(text(t, money('كاش')), '٥٠');
      await t.tap(find.text('حفظ مسودة'));
      await t.pumpAndSettle();
      await remount(t, f.container);
      await tapSection(t, 'البيع');
      expect(text(t, money('كاش')), '٥٠');
      expect((await f.uc.saleDraft())!.items.single.unitPriceMinor, 12050);
      expect(await f.db.select(f.db.saleInvoices).get(), isEmpty);
    },
  );

  testWidgets(
    'failed preference save leaves current appearance and invoice intact',
    (t) async {
      final f = await start(t);
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      await f.db.customStatement('PRAGMA query_only=ON');
      try {
        await t.tap(find.byKey(const ValueKey('theme-toggle')));
        await t.pumpAndSettle();
        expect(f.container.read(appThemeModeProvider).asData!.value, 'light');
        expect(text(t, quantityInput(1)), '2');
        expect(find.text('تعذر حفظ المظهر. أعد المحاولة.'), findsOneWidget);
      } finally {
        await f.db.customStatement('PRAGMA query_only=OFF');
      }
    },
  );

  testWidgets(
    'system mode follows desktop brightness without overwriting preference',
    (t) async {
      final f = await start(t);
      await f.container.read(appThemeModeProvider.notifier).change('system');
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
      await t.pumpAndSettle();
      expect(
        Theme.of(
          t.element(find.byKey(const ValueKey('theme-toggle'))),
        ).brightness,
        Brightness.dark,
      );
      t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await t.pumpAndSettle();
      expect(
        Theme.of(
          t.element(find.byKey(const ValueKey('theme-toggle'))),
        ).brightness,
        Brightness.light,
      );
      expect(await f.uc.themeMode(), 'system');
    },
  );

  for (final mode in ['light', 'dark']) {
    testWidgets(
      '$mode screens are readable and blur count stays bounded with a large catalog',
      (t) async {
        final f = await start(t, products: 1000);
        final products = await f.db.select(f.db.products).get();
        await f.uc.saveSaleDraft(
          SaleDraft(
            items: [
              for (final p in products.take(100))
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
        await f.container.read(appThemeModeProvider.notifier).change(mode);
        await t.pumpAndSettle();
        for (final section in [
          ('اليومية', 'dashboard'),
          ('البيع', 'pos'),
          ('المشتريات', 'purchase'),
          ('المخزون', 'inventory'),
          ('العملاء والموردون', 'parties'),
          ('الأقساط', 'installments'),
          ('الفواتير والمرتجعات', 'invoices'),
          ('التقارير', 'reports'),
          ('الإعدادات', 'settings'),
          ('النسخ الاحتياطي', 'backup'),
        ]) {
          await tapSection(t, section.$1);
          expect(t.takeException(), isNull, reason: '$mode ${section.$1}');
          expect(
            find.byType(BackdropFilter).evaluate().length,
            lessThanOrEqualTo(4),
          );
          await t.runAsync(() => capture(t, '$mode-${section.$2}'));
          if (mode == 'dark' &&
              const ['dashboard', 'pos', 'reports'].contains(section.$2)) {
            await expectLater(
              find.byKey(const ValueKey('invoice-review')),
              matchesGoldenFile('goldens/ios_dark_${section.$2}.png'),
            );
          }
        }
        t.view.physicalSize = const Size(1024, 720);
        t.platformDispatcher.textScaleFactorTestValue = 1.25;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await tapSection(t, 'البيع');
        await t.enterText(quantityInput(1), '1');
        await t.pumpAndSettle();
        await reachCheckout(t);
        expect(find.text('100 نوع · 100 قطعة'), findsOneWidget);
        await f.container
            .read(appThemeModeProvider.notifier)
            .change(mode == 'light' ? 'dark' : 'light');
        await t.pumpAndSettle();
        await f.container.read(appThemeModeProvider.notifier).change(mode);
        await t.pumpAndSettle();
        expect(text(t, money('كاش')), '10000.00');
        expect(find.text('100 نوع · 100 قطعة'), findsOneWidget);
        expect(find.text('تأكيد تسجيل البيع').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() => capture(t, '$mode-payment-125'));
      },
    );
  }

  for (final mode in ['light', 'dark']) {
    testWidgets(
      '$mode receipt stays printable and keeps original invoice identity',
      (t) async {
        var printed = 0;
        final f = await start(
          t,
          rejectSale: false,
          printer: (job) async {
            printed++;
            expect(job.receipt.lines, hasLength(1));
            expect(job.receipt.invoice.totalMinor, 10000);
            return ReceiptPrintOutcome.submitted;
          },
        );
        await f.container.read(appThemeModeProvider.notifier).change(mode);
        await t.pumpAndSettle();
        await tapSection(t, 'البيع');
        await t.enterText(quantityInput(1), '1');
        await t.pumpAndSettle();
        await reachCheckout(t);
        await t.tap(find.text('تأكيد تسجيل البيع'));
        await t.pumpAndSettle();
        expect(find.text('الفرع: الفرع الرئيسي'), findsOneWidget);
        expect(find.textContaining('فاتورة بيع S-'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() => capture(t, '$mode-receipt'));
        await t.tap(find.widgetWithText(FilledButton, 'طباعة'));
        await t.pumpAndSettle();
        expect(printed, 1);
        expect(await f.db.select(f.db.saleInvoices).get(), hasLength(1));
      },
    );
  }

  testWidgets(
    'pointer reflection settles without moving inputs or stealing focus',
    (t) async {
      final f = await start(t);
      await f.container.read(appThemeModeProvider.notifier).change('dark');
      await tapSection(t, 'البيع');
      await t.enterText(quantityInput(1), '2');
      await t.pumpAndSettle();
      final rect = t.getRect(quantityInput(1));
      final focus = t.widget<TextField>(quantityInput(1)).focusNode!;
      expect(focus.hasFocus, isTrue);
      final pointer = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(0, 0));
      await pointer.moveTo(rect.center);
      await t.pumpAndSettle();
      await pointer.moveTo(rect.center + const Offset(30, 0));
      await t.pumpAndSettle();
      expect(t.getRect(quantityInput(1)), rect);
      expect(focus.hasFocus, isTrue);
      expect(text(t, quantityInput(1)), '2');
      expect(t.binding.hasScheduledFrame, isFalse);
      expect(t.takeException(), isNull);
      await t.runAsync(() => capture(t, 'dark-pointer-reflection'));
      await pointer.removePointer();
    },
  );

  testWidgets('saved dark appearance is used on login after provider reload', (
    t,
  ) async {
    final f = await start(t);
    await t.pumpWidget(const SizedBox());
    await f.uc.updateThemeMode('dark');
    f.container.invalidate(appThemeModeProvider);
    f.container.read(currentOwnerProvider.notifier).setOwner(null);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: const RepaintBoundary(
          key: ValueKey('invoice-review'),
          child: ALIkhlasV2App(),
        ),
      ),
    );
    for (
      var frame = 0;
      frame < 50 &&
          find.widgetWithText(TextField, 'اسم المستخدم').evaluate().isEmpty;
      frame++
    ) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(find.widgetWithText(TextField, 'اسم المستخدم'), findsOneWidget);
    expect(
      Theme.of(
        t.element(find.byKey(const ValueKey('theme-toggle'))),
      ).brightness,
      Brightness.dark,
    );
    await t.pumpAndSettle();
    await t.runAsync(() => capture(t, 'dark-login'));
    await expectLater(
      find.byKey(const ValueKey('invoice-review')),
      matchesGoldenFile('goldens/ios_dark_login.png'),
    );
  });
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

Future<void> capture(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('LIQUID_REVIEW_DIR');
  if (dir.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('invoice-review')),
  );
  final img = await boundary.toImage();
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final target = File('$dir/$name.png');
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes!.buffer.asUint8List());
  img.dispose();
}
