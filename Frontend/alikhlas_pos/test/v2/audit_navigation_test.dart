import 'package:alikhlas_pos/v2/app/v2_app.dart';
import 'package:alikhlas_pos/v2/app/v2_providers.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final section in ['البيع', 'الشراء']) {
    testWidgets('backup banner protects an unsaved $section', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final uc = V2UseCases(db);
      final ownerId = await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'owner',
              passwordHash: 'test-only',
              fullName: 'Owner',
              mustChangePassword: const Value(false),
            ),
          );
      final owner = await db.select(db.users).getSingle();
      expect(owner.id, ownerId);
      final created = await uc.createProduct(
        operationKey: 'audit-ui-stock',
        name: 'Audit washer',
        salePriceMinor: 10000,
        openingQty: 2,
        openingCostMinor: 7000,
      );
      expect(created, isA<AppSuccess<Product>>());
      await uc.setBackupDirectory(
        '/tmp/nonexistent-audit-destination-20261107',
      );
      final snapshot = await tester.runAsync(() => uc.workbenchSnapshot());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          useCasesProvider.overrideWithValue(uc),
          bootstrapProvider.overrideWith((ref) async {}),
          workbenchProvider.overrideWith((ref) async => snapshot!),
        ],
      );
      container.read(currentOwnerProvider.notifier).setOwner(owner);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ALIkhlasV2App(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('إعداد النسخ'), findsOneWidget);
      await tester.tap(find.text(section).first);
      await tester.pumpAndSettle();
      await tester.tap(
        section == 'الشراء'
            ? find.byTooltip('إضافة للفاتورة').first
            : find.text('Audit washer').first,
      );
      await tester.pumpAndSettle();
      final beforeCount = find.text('Audit washer').evaluate().length;
      // Control: ordinary section navigation correctly warns about this cart.
      await tester.tap(find.text('اليومية').first);
      await tester.pumpAndSettle();
      expect(find.text('فاتورة $section غير محفوظة'), findsOneWidget);
      await tester.tap(find.text('العودة للفاتورة'));
      await tester.pumpAndSettle();
      // The backup warning's navigation must apply the same guard.
      await tester.tap(find.text('إعداد النسخ'));
      await tester.pumpAndSettle();
      final warnings = find
          .text('فاتورة $section غير محفوظة')
          .evaluate()
          .length;
      expect(
        warnings,
        1,
        reason:
            'Unsaved cart must be protected before navigating through the backup banner.',
      );
      await tester.tap(find.text('العودة للفاتورة'));
      await tester.pumpAndSettle();
      expect(find.text('Audit washer'), findsNWidgets(beforeCount));
      await tester.tap(find.text('إعداد النسخ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مغادرة دون حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('النسخ الاحتياطي'), findsOneWidget);
    });
  }
}
