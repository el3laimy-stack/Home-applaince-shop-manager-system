import '../support/checkout.dart';
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
  for (final section in ['البيع', 'المشتريات']) {
    testWidgets(
      'navigation and backup banner flush the active $section draft',
      (tester) async {
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
        await tester.tap(find.text('Audit washer').first);
        await tester.pumpAndSettle();
        await tapSection(tester, 'اليومية');
        expect(find.textContaining('غير محفوظة'), findsNothing);
        final kind = section == 'البيع' ? 'sale' : 'purchase';
        final workspace = await uc.activeInvoiceWorkspace(kind);
        expect(workspace, isNotNull);
        await tapSection(tester, section);
        expect(
          tester.widget<TextField>(quantityInput(1)).controller!.text,
          '1',
        );
        await tester.tap(find.text('إعداد النسخ'));
        await tester.pumpAndSettle();
        expect(find.text('النسخ الاحتياطي'), findsWidgets);
        expect((await uc.activeInvoiceWorkspace(kind))!.id, workspace!.id);
        await tapSection(tester, section);
        expect(
          tester.widget<TextField>(quantityInput(1)).controller!.text,
          '1',
        );
        expect(await db.select(db.saleInvoices).get(), isEmpty);
        expect(await db.select(db.purchaseInvoices).get(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
