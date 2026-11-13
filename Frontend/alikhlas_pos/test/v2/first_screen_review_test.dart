import '../support/visual_binding.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({AppDatabase db, V2UseCases uc, ProviderContainer container})>
setupScreen(
  WidgetTester t, {
  String mode = 'light',
  Size size = const Size(1024, 720),
  double scale = 1.25,
  PrinterTestPage? printer,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final uc = V2UseCases(db, clock: () => DateTime(2026, 11, 8, 12));
  await uc.bootstrap(createDefaultOwner: false);
  await uc.updateThemeMode(mode);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      useCasesProvider.overrideWithValue(uc),
      appClockProvider.overrideWithValue(() => DateTime(2026, 11, 8, 12)),
      bootstrapProvider.overrideWith((ref) async {}),
      if (printer != null) printerTestPageProvider.overrideWithValue(printer),
    ],
  );
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    container.dispose();
  });
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: ValueKey('first-screen-review'),
        child: ALIkhlasV2App(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (db: db, uc: uc, container: container);
}

Future<void> captureSetup(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SETUP_REVIEW_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('first-screen-review')),
    );
    final img = await boundary.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
  });
}

Finder setupField(String label) => find.widgetWithText(TextField, label);
Future<void> fillSetup(WidgetTester t) async {
  for (final entry in const {
    'اسم المحل': 'محل تجريبي',
    'اسم المالك': 'مالك تجريبي',
    'كلمة المرور': 'example-password',
    'تأكيد كلمة المرور': 'example-password',
  }.entries) {
    await t.ensureVisible(setupField(entry.key));
    await t.enterText(setupField(entry.key), entry.value);
  }
  await t.pumpAndSettle();
}

Future<void> submitSetup(WidgetTester t) async {
  final button = find.byKey(const ValueKey('setup-submit'));
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
  if (find.text('المتابعة دون نسخ').evaluate().isNotEmpty) {
    await t.tap(find.text('المتابعة دون نسخ'));
    await t.pumpAndSettle();
  }
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
      testWidgets(
        '$mode initial setup at ${small ? '360' : '1024'} and125 percent',
        (t) async {
          await setupScreen(
            t,
            mode: mode,
            size: small ? const Size(360, 720) : const Size(1024, 720),
          );
          await captureSetup(t, '$mode-${small ? '360' : '1024'}-125');
          expect(find.text('حفظ ومتابعة').hitTestable(), findsOneWidget);
          expect(find.text('اختبار الطابعة الآن').hitTestable(), findsNothing);
          expect(find.text('اختيار مجلد النسخ').hitTestable(), findsNothing);
          if (!small) {
            for (final label in [
              'اسم المحل',
              'اسم المالك',
              'كلمة المرور',
              'تأكيد كلمة المرور',
            ]) {
              expect(setupField(label).hitTestable(), findsOneWidget);
            }
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'inline validation shows first invalid field and never creates an account',
    (t) async {
      final f = await setupScreen(t);
      await submitSetup(t);
      expect(find.text('اكتب اسم المحل'), findsOneWidget);
      expect(
        t.widget<TextField>(setupField('اسم المحل')).focusNode!.hasFocus,
        isTrue,
      );
      expect(await f.uc.hasOwner(), isFalse);
      await t.enterText(setupField('اسم المحل'), 'محل');
      await t.enterText(setupField('اسم المالك'), 'مالك');
      await t.enterText(setupField('كلمة المرور'), '123');
      await t.enterText(setupField('تأكيد كلمة المرور'), '456');
      await submitSetup(t);
      expect(
        find.text('كلمة المرور لازم تكون 6 أحرف على الأقل'),
        findsOneWidget,
      );
      expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
      expect(
        t.widget<TextField>(setupField('كلمة المرور')).focusNode!.hasFocus,
        isTrue,
      );
      expect(await f.uc.hasOwner(), isFalse);
      await captureSetup(t, 'light-validation');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('reveal preserves text and focus and Enter follows field order', (
    t,
  ) async {
    await setupScreen(t);
    await t.enterText(setupField('اسم المحل'), 'محل');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(setupField('اسم المالك')).focusNode!.hasFocus,
      isTrue,
    );
    await t.enterText(setupField('اسم المالك'), 'مالك');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    await t.enterText(setupField('كلمة المرور'), 'example-password');
    final focus = t.widget<TextField>(setupField('كلمة المرور')).focusNode!;
    await t.tap(find.byTooltip('إظهار كلمة المرور'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(setupField('كلمة المرور')).obscureText, isFalse);
    expect(
      t.widget<TextField>(setupField('كلمة المرور')).controller!.text,
      'example-password',
    );
    expect(focus.hasFocus, isTrue);
    await t.tap(find.byTooltip('إخفاء كلمة المرور'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(setupField('كلمة المرور')).obscureText, isTrue);
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(setupField('تأكيد كلمة المرور')).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'Tab reaches all required fields in RTL reading order without trapping focus',
    (t) async {
      await setupScreen(t);
      final labels = [
        'اسم المحل',
        'اسم المالك',
        'كلمة المرور',
        'تأكيد كلمة المرور',
      ];
      final visited = <int>[0];
      for (var step = 0; step < 10 && visited.length < 4; step++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        final index = labels.indexWhere(
          (label) => t.widget<TextField>(setupField(label)).focusNode!.hasFocus,
        );
        if (index >= 0 && visited.last != index) visited.add(index);
      }
      expect(visited, [0, 1, 2, 3]);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('create once, copy exact LTR recovery code and explicitly finish', (
    t,
  ) async {
    final f = await setupScreen(t, mode: 'dark', size: const Size(360, 720));
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await fillSetup(t);
    final action = t
        .widget<TextField>(setupField('تأكيد كلمة المرور'))
        .onSubmitted!;
    action('example-password');
    action('example-password');
    await t.pumpAndSettle();
    await t.tap(find.text('المتابعة دون نسخ'));
    await t.pumpAndSettle();
    expect(find.text('احفظ رمز الاستعادة'), findsOneWidget);
    expect(await f.db.select(f.db.users).get(), hasLength(1));
    expect(f.container.read(currentOwnerProvider), isNull);
    final code = t.widget<SelectableText>(
      find.byKey(const ValueKey('setup-recovery-code')),
    );
    expect(code.textDirection, TextDirection.ltr);
    await t.ensureVisible(find.text('نسخ الرمز'));
    await t.tap(find.text('نسخ الرمز'));
    await t.pumpAndSettle();
    expect(copied, code.data);
    expect(find.text('تم نسخ الرمز'), findsOneWidget);
    await captureSetup(t, 'dark-recovery-360');
    // Finish at the next screen's supported desktop size; its redesign is separate.
    t.view.physicalSize = const Size(1024, 720);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('حفظت الرمز، ابدأ العمل'));
    final confirmedCode = t
        .widget<SelectableText>(
          find.byKey(const ValueKey('setup-recovery-code')),
        )
        .data!;
    await t.tap(find.text('حفظت الرمز، ابدأ العمل'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('confirm-recovery-code')),
      confirmedCode,
    );
    await t.tap(find.text('تأكيد الرمز'));
    await t.pumpAndSettle();
    expect(find.text('يومية المحل'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('storage failure retains inputs and permits a successful retry', (
    t,
  ) async {
    final f = await setupScreen(t);
    await fillSetup(t);
    await f.db.customStatement('PRAGMA query_only=ON');
    try {
      await submitSetup(t);
      expect(find.textContaining('تعذر إكمال الحفظ'), findsOneWidget);
      expect(
        t.widget<TextField>(setupField('اسم المحل')).controller!.text,
        'محل تجريبي',
      );
      expect(
        t.widget<TextField>(setupField('كلمة المرور')).controller!.text,
        'example-password',
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('setup-submit')))
            .onPressed,
        isNotNull,
      );
      expect(await f.uc.hasOwner(), isFalse);
      await captureSetup(t, 'light-storage-error');
    } finally {
      await f.db.customStatement('PRAGMA query_only=OFF');
    }
    await submitSetup(t);
    expect(find.text('احفظ رمز الاستعادة'), findsOneWidget);
    expect(await f.db.select(f.db.users).get(), hasLength(1));
  });

  testWidgets(
    'optional printer remains skippable and busy blocks account creation',
    (t) async {
      final gate = Completer<bool>();
      final f = await setupScreen(t, printer: (_) => gate.future);
      await fillSetup(t);
      await t.ensureVisible(find.text('تجهيزات إضافية'));
      await t.tap(find.text('تجهيزات إضافية'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('اختبار الطابعة الآن'));
      await t.tap(find.text('اختبار الطابعة الآن'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('setup-submit')))
            .onPressed,
        isNull,
      );
      expect(t.widget<TextField>(setupField('اسم المحل')).enabled, isFalse);
      expect(await f.uc.hasOwner(), isFalse);
      // Button colors animate between enabled/disabled states. Capture the
      // settled appearance while the native print operation is still pending.
      await t.pump(const Duration(milliseconds: 300));
      await captureSetup(t, 'light-printer-busy');
      gate.complete(false);
      await t.pumpAndSettle();
      expect(find.textContaining('لم تكتمل الطباعة'), findsOneWidget);
      expect(t.widget<TextField>(setupField('اسم المحل')).enabled, isTrue);
      await captureSetup(t, 'light-options-expanded');
      await submitSetup(t);
      expect(find.text('احفظ رمز الاستعادة'), findsOneWidget);
    },
  );

  testWidgets(
    'short window and keyboard insets retain scrolling access to submit',
    (t) async {
      await setupScreen(t, mode: 'dark', size: const Size(320, 520));
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await fillSetup(t);
      await t.ensureVisible(find.byKey(const ValueKey('setup-submit')));
      await t.pumpAndSettle();
      expect(find.text('حفظ ومتابعة').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await captureSetup(t, 'dark-short-keyboard');
    },
  );
}
