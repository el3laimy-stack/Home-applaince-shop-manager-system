import '../support/visual_binding.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<
  ({AppDatabase db, V2UseCases uc, ProviderContainer container, String code})
>
loginScreen(
  WidgetTester t, {
  String mode = 'light',
  Size size = const Size(1024, 720),
  ReviewWriteBarrier? barrier,
  bool legacy = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.25;
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
  await uc.bootstrap(createDefaultOwner: legacy);
  var code = '';
  if (!legacy) {
    final setup = await uc.setupInitialOwner(
      fullName: 'مالك تجريبي',
      password: 'example-password',
      shopName: 'محل تجريبي',
    );
    expect(setup, isA<AppSuccess<InitialOwnerSetup>>());
    code = (setup as AppSuccess<InitialOwnerSetup>).value.recoveryCode;
  }
  await uc.updateThemeMode(mode);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      useCasesProvider.overrideWithValue(uc),
      appClockProvider.overrideWithValue(() => DateTime(2026, 11, 8, 12)),
      bootstrapProvider.overrideWith((ref) async {}),
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
        key: ValueKey('login-screen-review'),
        child: ALIkhlasV2App(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (db: db, uc: uc, container: container, code: code);
}

Future<void> captureLogin(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('LOGIN_REVIEW_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('login-screen-review')),
    );
    final img = await boundary.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
  });
}

Finder loginField(String label) => find.widgetWithText(TextField, label);

class ReviewWriteBarrier extends V2WriteBarrier {
  Completer<void>? gate;
  bool failNext = false;
  int calls = 0;
  @override
  Future<T> write<T>(Future<T> Function() action) async {
    calls++;
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw StateError('Synthetic storage failure');
    }
    return super.write(action);
  }
}

Future<void> submitLogin(WidgetTester t) async {
  final button = find.byKey(const ValueKey('login-submit'));
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

Future<void> openRecovery(WidgetTester t) async {
  await t.ensureVisible(find.text('نسيت كلمة المرور؟'));
  await t.tap(find.text('نسيت كلمة المرور؟'));
  await t.pumpAndSettle();
}

Future<void> fillRecovery(WidgetTester t, String code) async {
  for (final e in {
    'رمز الاستعادة': code,
    'كلمة المرور الجديدة': 'replacement-password',
    'تأكيد كلمة المرور': 'replacement-password',
  }.entries) {
    await t.ensureVisible(loginField(e.key));
    await t.enterText(loginField(e.key), e.value);
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
      testWidgets('$mode login at ${small ? '360' : '1024'} and125 percent', (
        t,
      ) async {
        await loginScreen(
          t,
          mode: mode,
          size: small ? const Size(360, 720) : const Size(1024, 720),
        );
        await captureLogin(t, '$mode-${small ? '360' : '1024'}-125');
        expect(find.text('دخول').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'empty fields validate locally without consuming login attempts',
    (t) async {
      final barrier = ReviewWriteBarrier();
      final f = await loginScreen(t, barrier: barrier);
      final calls = barrier.calls;
      await t.enterText(loginField('اسم المستخدم'), ' ');
      await submitLogin(t);
      expect(find.text('اكتب اسم المستخدم'), findsOneWidget);
      expect(find.text('اكتب كلمة المرور'), findsOneWidget);
      expect(
        t.widget<TextField>(loginField('اسم المستخدم')).focusNode!.hasFocus,
        isTrue,
      );
      expect(barrier.calls, calls);
      expect(f.container.read(currentOwnerProvider), isNull);
      await captureLogin(t, 'light-validation');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'password focus, reveal, Enter and Tab preserve the credentials',
    (t) async {
      await loginScreen(t);
      expect(
        t.widget<TextField>(loginField('كلمة المرور')).focusNode!.hasFocus,
        isTrue,
      );
      await t.enterText(loginField('كلمة المرور'), 'example-password');
      await t.tap(find.byTooltip('إظهار كلمة المرور'));
      await t.pumpAndSettle();
      var field = t.widget<TextField>(loginField('كلمة المرور'));
      expect(field.obscureText, isFalse);
      expect(field.controller!.text, 'example-password');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.textDirection, TextDirection.ltr);
      await t.tap(find.byTooltip('إخفاء كلمة المرور'));
      await t.tap(loginField('اسم المستخدم'));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(loginField('كلمة المرور')).focusNode!.hasFocus,
        isTrue,
      );
      t.widget<TextField>(loginField('اسم المستخدم')).focusNode!.requestFocus();
      await t.pump();
      var reachedPassword = false;
      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        reachedPassword |= t
            .widget<TextField>(loginField('كلمة المرور'))
            .focusNode!
            .hasFocus;
      }
      expect(reachedPassword, isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pending login is single, disables editing, then allows correction and success',
    (t) async {
      final barrier = ReviewWriteBarrier();
      final f = await loginScreen(t, barrier: barrier);
      // Login checks only emptiness, so short historical passwords still reach
      // the existing authentication service rather than a new length policy.
      await t.enterText(loginField('كلمة المرور'), 'bad');
      final calls = barrier.calls;
      final gate = Completer<void>();
      barrier.gate = gate;
      final submit = t
          .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
          .onPressed!;
      submit();
      submit();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(barrier.calls, calls + 1);
      expect(t.widget<TextField>(loginField('اسم المستخدم')).enabled, isFalse);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'نسيت كلمة المرور؟'),
            )
            .onPressed,
        isNull,
      );
      await captureLogin(t, 'light-login-busy');
      gate.complete();
      barrier.gate = null;
      await t.pumpAndSettle();
      expect(
        find.text('اسم المستخدم أو كلمة المرور غير صحيحة'),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(loginField('كلمة المرور')).controller!.text,
        'bad',
      );
      expect(f.container.read(currentOwnerProvider), isNull);
      await captureLogin(t, 'light-auth-error');
      await t.enterText(loginField('كلمة المرور'), 'example-password');
      await t.pump();
      expect(find.text('اسم المستخدم أو كلمة المرور غير صحيحة'), findsNothing);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'unexpected login storage failure retains inputs and permits retry',
    (t) async {
      final barrier = ReviewWriteBarrier();
      await loginScreen(t, barrier: barrier);
      await t.enterText(loginField('كلمة المرور'), 'example-password');
      barrier.failNext = true;
      await submitLogin(t);
      expect(find.textContaining('تعذر إكمال الدخول'), findsOneWidget);
      expect(
        t.widget<TextField>(loginField('كلمة المرور')).controller!.text,
        'example-password',
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
            .onPressed,
        isNotNull,
      );
      await captureLogin(t, 'light-storage-error');
      await submitLogin(t);
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'short login with keyboard and text enlargement keeps actions reachable',
    (t) async {
      final f = await loginScreen(t, mode: 'dark', size: const Size(320, 520));
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('login-submit')));
      await submitLogin(t);
      expect(find.text('اكتب كلمة المرور'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('login-recovery')));
      await t.pumpAndSettle();
      expect(
        t.getRect(find.byKey(const ValueKey('login-recovery'))).bottom,
        lessThanOrEqualTo(320),
      );
      expect(find.text('نسيت كلمة المرور؟').hitTestable(), findsOneWidget);
      expect(f.container.read(currentOwnerProvider), isNull);
      await captureLogin(t, 'dark-short-keyboard-200');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('recovery validation is local and cancel retains login input', (
    t,
  ) async {
    final barrier = ReviewWriteBarrier();
    await loginScreen(t, barrier: barrier);
    await t.enterText(loginField('كلمة المرور'), 'kept-login-value');
    await openRecovery(t);
    final calls = barrier.calls;
    await t.tap(find.text('استعادة الدخول'));
    await t.pumpAndSettle();
    expect(find.text('اكتب رمز الاستعادة'), findsOneWidget);
    expect(find.text('كلمة المرور لازم تكون 6 أحرف على الأقل'), findsOneWidget);
    expect(
      t.widget<TextField>(loginField('رمز الاستعادة')).focusNode!.hasFocus,
      isTrue,
    );
    await t.enterText(loginField('رمز الاستعادة'), 'INVALID');
    await t.enterText(loginField('كلمة المرور الجديدة'), '123456');
    await t.enterText(loginField('تأكيد كلمة المرور'), '654321');
    await t.tap(find.text('استعادة الدخول'));
    await t.pumpAndSettle();
    expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
    expect(barrier.calls, calls);
    await captureLogin(t, 'light-recovery-validation');
    await t.tap(find.text('إلغاء'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      t.widget<TextField>(loginField('كلمة المرور')).controller!.text,
      'kept-login-value',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'recovery pending and new code resist dismissal, copy exactly and require acknowledgement',
    (t) async {
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
      final barrier = ReviewWriteBarrier();
      final f = await loginScreen(
        t,
        mode: 'dark',
        size: const Size(360, 720),
        barrier: barrier,
      );
      await openRecovery(t);
      await captureLogin(t, 'dark-recovery-form-360');
      await fillRecovery(t, f.code);
      final gate = Completer<void>();
      barrier.gate = gate;
      final calls = barrier.calls;
      final submit = t
          .widget<FilledButton>(find.byKey(const ValueKey('recovery-submit')))
          .onPressed!;
      submit();
      submit();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(barrier.calls, calls + 1);
      expect(t.widget<TextField>(loginField('رمز الاستعادة')).enabled, isFalse);
      await t.tapAt(const Offset(5, 5));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('جارٍ الاستعادة...'), findsOneWidget);
      await captureLogin(t, 'dark-recovery-busy-360');
      gate.complete();
      barrier.gate = null;
      await t.pumpAndSettle();
      expect(find.text('رمز الاستعادة الجديد'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.binding.handlePopRoute();
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('رمز الاستعادة الجديد'), findsOneWidget);
      final code = t.widget<SelectableText>(
        find.byKey(const ValueKey('recovery-new-code')),
      );
      expect(code.textDirection, TextDirection.ltr);
      expect(code.data, isNot(f.code));
      await t.ensureVisible(find.text('نسخ الرمز'));
      await t.tap(find.text('نسخ الرمز'));
      await t.pumpAndSettle();
      expect(copied, code.data);
      expect(find.text('تم نسخ الرمز'), findsOneWidget);
      expect(f.container.read(currentOwnerProvider), isNull);
      await captureLogin(t, 'dark-recovery-new-code-360');
      final confirmedCode = t
          .widget<SelectableText>(
            find.byKey(const ValueKey('recovery-new-code')),
          )
          .data!;
      await t.tap(find.text('حفظت الرمز، عودة للدخول'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('confirm-recovery-code')),
        confirmedCode,
      );
      await t.tap(find.text('تأكيد الرمز'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      t.view.physicalSize = const Size(1024, 720);
      await t.pumpAndSettle();
      await t.enterText(loginField('كلمة المرور'), 'replacement-password');
      await submitLogin(t);
      expect(find.text('يومية المحل'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'recovery write failure retains inputs and can retry in short keyboard viewport',
    (t) async {
      final barrier = ReviewWriteBarrier();
      final f = await loginScreen(
        t,
        size: const Size(360, 640),
        barrier: barrier,
      );
      await openRecovery(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await fillRecovery(t, f.code);
      barrier.failNext = true;
      await t.ensureVisible(find.text('استعادة الدخول'));
      await t.tap(find.text('استعادة الدخول'));
      await t.pumpAndSettle();
      expect(find.textContaining('تعذر إكمال الاستعادة'), findsOneWidget);
      expect(
        t.widget<TextField>(loginField('رمز الاستعادة')).controller!.text,
        f.code,
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('recovery-submit')))
            .onPressed,
        isNotNull,
      );
      await captureLogin(t, 'light-recovery-error-keyboard');
      await t.tap(find.text('استعادة الدخول'));
      await t.pumpAndSettle();
      expect(find.text('رمز الاستعادة الجديد'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy owner still enters mandatory password change before dashboard',
    (t) async {
      final f = await loginScreen(t, legacy: true);
      await t.enterText(loginField('كلمة المرور'), 'owner123');
      await submitLogin(t);
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
      expect(find.text('يومية المحل'), findsNothing);
      await t.enterText(
        loginField('كلمة المرور الجديدة'),
        'replacement-password',
      );
      await t.enterText(
        loginField('تأكيد كلمة المرور'),
        'replacement-password',
      );
      await t.tap(find.text('حفظ ومتابعة'));
      await t.pumpAndSettle();
      expect(find.text('احفظ رمز الاستعادة'), findsOneWidget);
      expect(
        f.container.read(currentOwnerProvider)!.mustChangePassword,
        isTrue,
      );
      final confirmedCode = t
          .widget<SelectableText>(
            find.byKey(const ValueKey('change-recovery-code')),
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
      expect(
        f.container.read(currentOwnerProvider)!.mustChangePassword,
        isFalse,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'server lock message wraps in a narrow viewport and theme changes keep inputs',
    (t) async {
      final f = await loginScreen(t, size: const Size(360, 720));
      await f.db
          .into(f.db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: 'security.login.lockedUntil',
              value: DateTime(2026, 11, 8, 12, 15).toIso8601String(),
            ),
          );
      await t.enterText(loginField('كلمة المرور'), 'example-password');
      await submitLogin(t);
      expect(
        find.textContaining('تم إيقاف محاولات الدخول مؤقتًا'),
        findsOneWidget,
      );
      await captureLogin(t, 'light-login-locked-360');
      await t.ensureVisible(find.byKey(const ValueKey('theme-toggle')));
      await t.tap(find.byKey(const ValueKey('theme-toggle')));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(loginField('كلمة المرور')).controller!.text,
        'example-password',
      );
      expect(
        find.textContaining('تم إيقاف محاولات الدخول مؤقتًا'),
        findsOneWidget,
      );
      expect(f.container.read(currentOwnerProvider), isNull);
      expect(t.takeException(), isNull);
    },
  );
}
