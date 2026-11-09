import '../support/visual_binding.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/checkout.dart';

Future<({AppDatabase db, V2UseCases uc, ProviderContainer container})>
dashboardScreen(
  WidgetTester t, {
  String mode = 'light',
  Size size = const Size(1024, 720),
  double scale = 1.25,
  bool populated = true,
  Future<WorkbenchSnapshot> Function()? loader,
  FutureOr<WorkbenchSnapshot> Function(WorkbenchSnapshot)? transform,
  DashboardWriteBarrier? barrier,
  bool settle = true,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final uc = V2UseCases(
    db,
    clock: () => DateTime(2026, 11, 8, 12),
    writeBarrier: barrier,
  );
  await uc.bootstrap(createDefaultOwner: false);
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'review',
          passwordHash: 'not-used',
          fullName: 'مالك تجريبي',
          mustChangePassword: const Value(false),
        ),
      );
  await uc.updateThemeMode(mode);
  expect(
    await uc.updateShopSettings(
      shopName: 'الإخلاص — محل تجريبي',
      branchName: 'فرع تجريبي',
    ),
    isA<AppSuccess<ShopSettingsSnapshot>>(),
  );
  if (populated) {
    for (var i = 0; i < 4; i++) {
      expect(
        await uc.createProduct(
          operationKey: uc.newOpeningStockOperationKey(),
          name: [
            'خلاط زجاجي كبير',
            'غلاية كهربائية',
            'طقم مفروشات قطني',
            'مروحة ستاند',
          ][i],
          salePriceMinor: 10000,
          openingQty: i == 0
              ? 4
              : i == 1
              ? 1
              : 8,
          openingCostMinor: 7000,
          minStockQty: 3,
        ),
        isA<AppSuccess<Product>>(),
      );
    }
    expect(
      await uc.openShift(10000, operationKey: uc.newShiftOperationKey()),
      isA<AppSuccess<Shift>>(),
    );
    expect(
      await uc.createSale(
        operationKey: uc.newSaleOperationKey(),
        items: const [
          SaleLineInput(productId: 1, qty: 2, unitPriceMinor: 10000),
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 20000)],
      ),
      isA<AppSuccess<int>>(),
    );
    expect(
      await uc.recordExpense(
        operationKey: uc.newExpenseOperationKey(),
        description: 'توصيل تجريبي',
        amountMinor: 1000,
        method: PaymentMethod.cash,
      ),
      isA<AppSuccess<int>>(),
    );
  }
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      useCasesProvider.overrideWithValue(uc),
      appClockProvider.overrideWithValue(() => DateTime(2026, 11, 8, 12)),
      bootstrapProvider.overrideWith((ref) async {}),
      if (loader != null) workbenchProvider.overrideWith((ref) => loader()),
      if (transform != null)
        workbenchProvider.overrideWith(
          (ref) async => transform(await uc.workbenchSnapshot()),
        ),
    ],
  );
  container
      .read(currentOwnerProvider.notifier)
      .setOwner(await db.select(db.users).getSingle());
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    container.dispose();
  });
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: ValueKey('dashboard-review'),
        child: ALIkhlasV2App(),
      ),
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
  return (db: db, uc: uc, container: container);
}

class DashboardWriteBarrier extends V2WriteBarrier {
  Completer<void>? gate;
  bool failNext = false;
  int calls = 0;
  @override
  Future<T> write<T>(Future<T> Function() action) async {
    calls++;
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw StateError('Synthetic write failure');
    }
    return super.write(action);
  }
}

WorkbenchSnapshot withReviewData(
  WorkbenchSnapshot s, {
  DailySummarySnapshot? summary,
  BackupStatus? backup,
  ShopSettingsSnapshot? shop,
}) => WorkbenchSnapshot(
  dashboard: s.dashboard,
  dailySummary: summary ?? s.dailySummary,
  products: s.products,
  customers: s.customers,
  suppliers: s.suppliers,
  customerBalances: s.customerBalances,
  supplierBalances: s.supplierBalances,
  installmentPlans: s.installmentPlans,
  recentLedger: s.recentLedger,
  recentSales: s.recentSales,
  recentPurchases: s.recentPurchases,
  dueInstallments: s.dueInstallments,
  installmentSummaries: s.installmentSummaries,
  backupStatus: backup ?? s.backupStatus,
  shopSettings: shop ?? s.shopSettings,
  barcodeLabelSettings: s.barcodeLabelSettings,
  uiBackground: s.uiBackground,
  installmentAlerts: s.installmentAlerts,
);

Future<void> dailyScrollTo(WidgetTester t, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const PageStorageKey('daily-page-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await t.scrollUntilVisible(finder, 250, scrollable: scrollable);
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> captureDashboard(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('DASHBOARD_REVIEW_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('dashboard-review')),
    );
    final img = await boundary.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
  });
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
    for (final wide in [true, false]) {
      testWidgets('$mode dashboard at ${wide ? '1280' : '1024'}', (t) async {
        await dashboardScreen(
          t,
          mode: mode,
          size: wide ? const Size(1280, 800) : const Size(1024, 720),
          scale: wide ? 1 : 1.25,
        );
        await captureDashboard(t, '$mode-${wide ? '1280' : '1024'}');
        expect(find.text('يومية المحل'), findsOneWidget);
        expect(find.text('بيع جديد').hitTestable(), findsOneWidget);
        expect(
          t.getRect(find.byKey(const ValueKey('daily-profit'))).bottom,
          lessThan(sizeHeight(t) - 18),
        );
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'daily indicators and expanded balances match the real ledger-backed snapshot',
    (t) async {
      final f = await dashboardScreen(t);
      final snapshot = await t.runAsync(() => f.uc.workbenchSnapshot());
      final summary = snapshot!.dailySummary;
      expect(summary.salesMinor, 20000);
      expect(summary.tradingGrossProfitMinor, 6000);
      expect(summary.profitMinor, 5000);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-sales')),
          matching: find.text(Money(20000).format()),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-profit')),
          matching: find.text(Money(5000).format()),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-invoices')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await dailyScrollTo(t, find.text('تفاصيل اليوم'));
      await t.tap(find.text('تفاصيل اليوم'));
      await t.pumpAndSettle();
      expect(find.text('مجمل ربح البيع'), findsOneWidget);
      await captureDashboard(t, 'light-daily-details');
      await dailyScrollTo(t, find.text('أرصدة المحل الحالية'));
      await t.tap(find.text('أرصدة المحل الحالية'));
      await t.pumpAndSettle();
      expect(find.text('صافي الربح التراكمي'), findsOneWidget);
      await dailyScrollTo(t, find.text('صافي الربح التراكمي'));
      await captureDashboard(t, 'light-current-balances');
      await dailyScrollTo(t, find.text('سجل القيود المحاسبية'));
      await t.tap(find.text('سجل القيود المحاسبية'));
      await t.pumpAndSettle();
      expect(find.text('آخر القيود'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  for (final mode in ['light', 'dark']) {
    testWidgets(
      '$mode empty daily at 360 keeps navigation and all content reachable',
      (t) async {
        await dashboardScreen(
          t,
          mode: mode,
          size: const Size(360, 720),
          populated: false,
        );
        expect(find.text('فتح وردية'), findsOneWidget);
        expect(find.text('إغلاق وردية'), findsNothing);
        expect(find.byTooltip('فتح قائمة الشاشات'), findsOneWidget);
        await captureDashboard(t, '$mode-empty-360');
        await dailyScrollTo(t, find.text('لا توجد أصناف ناقصة'));
        expect(find.text('لا توجد أصناف ناقصة').hitTestable(), findsOneWidget);
        await dailyScrollTo(t, find.text('سجل القيود المحاسبية'));
        await t.tap(find.text('سجل القيود المحاسبية'));
        await t.pumpAndSettle();
        expect(find.text('لا توجد قيود بعد'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'large signed amounts and long identity remain readable at 200 percent and 320 width',
    (t) async {
      await dashboardScreen(
        t,
        mode: 'dark',
        size: const Size(320, 600),
        scale: 2,
        transform: (s) => withReviewData(
          s,
          shop: const ShopSettingsSnapshot(
            shopName:
                'محل تجريبي باسم طويل للأجهزة والأدوات المنزلية والمفروشات',
            branchName: 'فرع تجريبي باسم طويل',
          ),
          summary: DailySummarySnapshot(
            date: s.dailySummary.date,
            salesMinor: 123456789012300,
            cogsMinor: 223456789012300,
            expensesMinor: 1000,
            interestMinor: 0,
            cashNetMinor: 0,
            walletNetMinor: 0,
            purchaseMinor: 0,
            saleCount: 99999,
            purchaseCount: 999,
            returnCount: 99,
          ),
        ),
      );
      final profit = find.byKey(const ValueKey('daily-profit'));
      await dailyScrollTo(t, profit);
      expect(
        find.descendant(
          of: profit,
          matching: find.text(Money(-100000000001000).format()),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: profit, matching: find.byType(FittedBox)),
        findsNothing,
      );
      await captureDashboard(t, 'dark-large-negative-320-200');
      await dailyScrollTo(t, find.text('أرصدة المحل الحالية'));
      await t.tap(find.text('أرصدة المحل الحالية'));
      await t.pumpAndSettle();
      await dailyScrollTo(t, find.text('صافي الربح التراكمي'));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow navigation at 200 percent scrolls through names, selection, help and logout',
    (t) async {
      await dashboardScreen(
        t,
        size: const Size(320, 520),
        scale: 2,
        populated: false,
      );
      await t.tap(find.byTooltip('فتح قائمة الشاشات'));
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
        findsOneWidget,
      );
      await captureDashboard(t, 'light-menu-top-320-200');
      final menu = find.byKey(const ValueKey('side-navigation-scroll'));
      final scrollable = find
          .descendant(of: menu, matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(
        find.text('خروج'),
        180,
        scrollable: scrollable,
      );
      await t.pumpAndSettle();
      expect(find.text('خروج').hitTestable(), findsOneWidget);
      expect(find.text('المساعدة').hitTestable(), findsOneWidget);
      await captureDashboard(t, 'light-menu-bottom-320-200');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      // Other sections still have their desktop layout and are reviewed separately.
      t.view.physicalSize = const Size(1024, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.25;
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('فتح قائمة الشاشات'));
      await t.pumpAndSettle();
      await tapSection(t, 'اليومية');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'quick actions and each alert navigate to the correct desktop section',
    (t) async {
      await dashboardScreen(t);
      for (final entry in [
        ('بيع جديد', 'الخطوة 1 من 3'),
        (
          'شراء جديد',
          'اختيار الأصناف والكميات ← مراجعة المورد والدفع ← تسجيل الشراء',
        ),
        (
          'فواتير المحل',
          'ابحث واعرض الفاتورة الأصلية لإعادة الطباعة أو تسجيل المرتجع',
        ),
        ('تحصيل قسط', 'الأولوية حسب تاريخ السداد: المتأخر أولًا ثم الأقرب'),
      ]) {
        await t.tap(find.text(entry.$1));
        await t.pumpAndSettle();
        expect(find.text('يومية المحل'), findsNothing);
        expect(find.text(entry.$2), findsOneWidget);
        await tapSection(t, 'اليومية');
      }
      for (final entry in [
        ('daily-low-stock-alert', 'منتجات وأسعار ورصيد وحد نقص'),
        (
          'daily-overdue-alert',
          'الأولوية حسب تاريخ السداد: المتأخر أولًا ثم الأقرب',
        ),
        (
          'daily-due-alert',
          'الأولوية حسب تاريخ السداد: المتأخر أولًا ثم الأقرب',
        ),
        ('daily-backup-alert', 'النسخ الاحتياطي'),
      ]) {
        await dailyScrollTo(t, find.byKey(ValueKey(entry.$1)));
        await t.tap(find.byKey(ValueKey(entry.$1)));
        await t.pumpAndSettle();
        expect(find.text('يومية المحل'), findsNothing);
        expect(find.text(entry.$2), findsOneWidget);
        await tapSection(t, 'اليومية');
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'backup state uses recorded time, reports missing time honestly and keeps warnings reachable',
    (t) async {
      var backup = BackupStatus(
        latestBackupPath: '/synthetic/not-a-real-backup-file.db',
        lastSuccessAt: DateTime(2026, 11, 8, 10, 30),
      );
      final f = await dashboardScreen(
        t,
        transform: (s) => withReviewData(s, backup: backup),
      );
      final tile = find.byKey(const ValueKey('daily-backup-alert'));
      expect(
        find.descendant(of: tile, matching: find.text('2026-11-08 10:30')),
        findsOneWidget,
      );
      expect(find.text('not-a-real-backup-file.db'), findsNothing);
      await captureDashboard(t, 'light-backup-time');
      backup = const BackupStatus(
        latestBackupPath: '/synthetic/not-a-real-backup-file.db',
      );
      f.container.invalidate(workbenchProvider);
      await t.pumpAndSettle();
      expect(find.text('نسخة موجودة؛ وقت الحفظ غير متاح'), findsOneWidget);
      backup = const BackupStatus(
        warning:
            'تحذير تجريبي طويل: تعذر حفظ النسخة الأخيرة. راجع مكان حفظ النسخ ومساحة القرص قبل متابعة العمل.',
      );
      t.view.physicalSize = const Size(360, 640);
      f.container.invalidate(workbenchProvider);
      await t.pumpAndSettle();
      expect(find.text('لا توجد نسخة محفوظة'), findsOneWidget);
      await dailyScrollTo(
        t,
        find.byKey(const ValueKey('daily-backup-warning')),
      );
      await captureDashboard(t, 'light-backup-warning-360');
      expect(find.text('إعداد النسخ').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'stock preview labels quantities, limits the preview and keeps the full stock action',
    (t) async {
      final f = await dashboardScreen(t);
      for (var i = 0; i < 6; i++) {
        expect(
          await f.uc.createProduct(
            name: 'صنف ناقص تجريبي $i',
            salePriceMinor: 100,
            openingQty: 0,
            openingCostMinor: 0,
          ),
          isA<AppSuccess<Product>>(),
        );
      }
      f.container.invalidate(workbenchProvider);
      await t.pumpAndSettle();
      await dailyScrollTo(t, find.text('معروض أول 5 من 8 صنف ناقص'));
      expect(find.text('المتاح: 2 • حد التنبيه: 3'), findsOneWidget);
      await captureDashboard(t, 'light-stock-preview');
      expect(find.text('فتح المخزون'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'shift opening validates, cancels without writes, then closing requires the actual counted cash',
    (t) async {
      final f = await dashboardScreen(t, populated: false);
      await t.tap(find.text('فتح وردية'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        (await t.runAsync(() => f.uc.dashboardSnapshot()))!.openShift,
        isNull,
      );
      await t.tap(find.text('إلغاء'));
      await t.pumpAndSettle();
      await t.tap(find.text('فتح وردية'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '100');
      await captureDashboard(t, 'light-shift-open');
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(find.text('إغلاق وردية'), findsOneWidget);
      await t.tap(find.text('إغلاق وردية'));
      await t.pumpAndSettle();
      expect(find.text('المتوقع في الدرج حسب التسجيل'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      t.view.physicalSize = const Size(360, 640);
      t.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(find.text('اكتب المبلغ، ولو مفيش كاش اكتب صفر'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await captureDashboard(t, 'light-shift-close');
      await t.enterText(find.byType(TextField), '90');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      await captureDashboard(t, 'light-shift-after-close');
      expect(find.text('فتح وردية'), findsOneWidget);
      final shift = await f.db.select(f.db.shifts).getSingle();
      expect(shift.actualCashMinor, 9000);
      expect(shift.expectedCashMinor, 10000);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'shift submission is single and unexpected storage failure leaves the screen usable',
    (t) async {
      final barrier = DashboardWriteBarrier();
      final f = await dashboardScreen(t, populated: false, barrier: barrier);
      await t.tap(find.text('فتح وردية'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '0');
      final gate = Completer<void>();
      barrier.gate = gate;
      final calls = barrier.calls;
      final submit = t
          .widget<FilledButton>(find.byKey(const ValueKey('shift-confirm')))
          .onPressed!;
      submit();
      submit();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(barrier.calls, calls + 1);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('daily-shift-action')),
            )
            .onPressed,
        isNull,
      );
      await captureDashboard(t, 'light-shift-busy');
      barrier.failNext = true;
      gate.complete();
      barrier.gate = null;
      await t.pumpAndSettle();
      expect(find.textContaining('تعذر تأكيد نتيجة الوردية'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('daily-shift-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(await f.db.select(f.db.shifts).get(), isEmpty);
      await t.tap(find.text('فتح وردية'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '0');
      await t.tap(find.byKey(const ValueKey('shift-confirm')));
      await t.pumpAndSettle();
      expect(await f.db.select(f.db.shifts).get(), hasLength(1));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'load failure shows a safe message and reload recovers without logout',
    (t) async {
      var fail = true;
      final f = await dashboardScreen(
        t,
        transform: (s) {
          if (fail) throw StateError('SYNTHETIC_PRIVATE_PATH');
          return s;
        },
      );
      expect(find.text('تعذر تحميل بيانات المحل'), findsOneWidget);
      expect(find.textContaining('SYNTHETIC_PRIVATE_PATH'), findsNothing);
      await captureDashboard(t, 'light-load-error');
      fail = false;
      await t.tap(find.text('إعادة التحميل'));
      await t.pumpAndSettle();
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(f.container.read(currentOwnerProvider), isNotNull);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pending snapshot has a loading state and resolves to the daily view',
    (t) async {
      final gate = Completer<WorkbenchSnapshot>();
      final f = await dashboardScreen(
        t,
        loader: () => gate.future,
        settle: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await captureDashboard(t, 'light-loading');
      final snapshot = await t.runAsync(() => f.uc.workbenchSnapshot());
      gate.complete(snapshot!);
      await t.pumpAndSettle();
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}

double sizeHeight(WidgetTester t) => t.view.physicalSize.height;
