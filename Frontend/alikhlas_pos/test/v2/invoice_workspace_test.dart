import 'dart:convert';

import 'package:alikhlas_pos/v2/application/invoice_autosave.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late V2UseCases uc;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    uc = V2UseCases(db);
  });
  tearDown(() => db.close());

  String payload(String text) => jsonEncode({
    'version': 2,
    'draft': null,
    'editor': {'cash': text},
  });

  test(
    'raw invalid text, suspended work, and CAS revisions survive editor switches',
    () async {
      final first = await uc.saveInvoiceWorkspace(
        kind: 'sale',
        payload: payload('١٫'),
        label: 'أحمد',
      );
      await uc.suspendInvoiceWorkspace(first.id);
      final second = await uc.saveInvoiceWorkspace(
        kind: 'sale',
        payload: payload('-'),
        label: 'محمد',
      );
      final resumed = await uc.resumeInvoiceWorkspace(first.id);
      expect(resumed.revision, greaterThan(first.revision));
      expect(decodeWorkspace(resumed.payload)['editor']['cash'], '١٫');
      expect((await uc.invoiceWorkspaces('sale')).length, 2);
      expect((await uc.activeInvoiceWorkspace('sale'))!.id, first.id);
      await expectLater(
        uc.saveInvoiceWorkspace(
          kind: 'sale',
          id: first.id,
          expectedRevision: first.revision,
          payload: payload('2'),
        ),
        throwsA(isA<WorkspaceConflict>()),
      );
      await uc.deleteInvoiceWorkspace(first.id);
      await expectLater(
        uc.saveInvoiceWorkspace(
          kind: 'sale',
          id: first.id,
          expectedRevision: resumed.revision,
          payload: payload('3'),
        ),
        throwsA(isA<WorkspaceConflict>()),
      );
      expect((await uc.resumeInvoiceWorkspace(second.id)).label, 'محمد');
    },
  );

  test(
    'legacy bytes are preserved even when a draft cannot be decoded',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(key: 'draft.sale.v1', value: '{broken'),
          );
      final row = await uc.activeInvoiceWorkspace('sale');
      expect(row!.payload, '{broken');
      expect((await uc.invoiceWorkspaces('sale')).length, 1);
      await expectLater(uc.saleDraft(), throwsFormatException);
      await uc.discardSaleDraft();
      expect(await uc.saleDraft(), isNull);
    },
  );

  test(
    'autosave serializes newer edits and cannot resurrect a deleted draft',
    () async {
      final session = InvoiceAutosave(uc, 'sale', onChanged: () {});
      addTearDown(session.dispose);
      session.mark(payload('1'));
      final firstWrite = session.flush();
      session.mark(payload('12'));
      await firstWrite;
      expect(decodeWorkspace(session.row!.payload)['editor']['cash'], '12');
      final id = session.row!.id;
      await uc.deleteInvoiceWorkspace(id);
      session.mark(payload('123'));
      await expectLater(session.flush(), throwsA(isA<WorkspaceConflict>()));
      expect(await uc.invoiceWorkspaces('sale'), isEmpty);
    },
  );

  test(
    'storage failure keeps the newest raw edit dirty until a successful retry',
    () async {
      final session = InvoiceAutosave(uc, 'purchase', onChanged: () {});
      addTearDown(session.dispose);
      session.mark(payload('1'));
      await session.flush();
      await db.customStatement('PRAGMA query_only=ON');
      session.mark(payload('١٫'));
      await expectLater(session.flush(), throwsA(isA<Exception>()));
      expect(session.dirty, isTrue);
      expect(session.error, isNotNull);
      expect(
        decodeWorkspace(
          (await db.select(db.checkoutDrafts).get()).single.payload,
        )['editor']['cash'],
        '1',
      );
      session.mark(payload('-أحدث'));
      await db.customStatement('PRAGMA query_only=OFF');
      await session.flush();
      expect(session.dirty, isFalse);
      expect(session.error, isNull);
      expect(decodeWorkspace(session.row!.payload)['editor']['cash'], '-أحدث');
    },
  );

  test('acknowledging a sale removes only its submitting workspace', () async {
    final suspended = await uc.saveInvoiceWorkspace(
      kind: 'sale',
      payload: payload('old'),
    );
    await uc.suspendInvoiceWorkspace(suspended.id);
    final active = await uc.saveInvoiceWorkspace(
      kind: 'sale',
      payload: payload('active'),
    );
    final product = await ok(
      uc.createProduct(
        operationKey: uc.newOpeningStockOperationKey(),
        name: 'منتج',
        salePriceMinor: 10000,
        openingQty: 2,
        openingCostMinor: 7000,
      ),
    );
    final customer = await ok(uc.createCustomer(name: 'عميل'));
    final request = await uc.stagePendingSale(
      PendingSale(
        operationKey: uc.newSaleOperationKey(),
        customerId: customer.id,
        items: [
          SaleLineInput(productId: product.id, qty: 1, unitPriceMinor: 10000),
        ],
        payments: [],
        installmentTerms: InstallmentTerms(
          partyId: customer.id,
          count: 1,
          firstDueDate: DateTime(2026, 12),
        ),
      ),
    );
    await expectLater(uc.deleteInvoiceWorkspace(active.id), throwsStateError);
    await ok(uc.submitPendingSale(request));
    expect(await uc.acknowledgePendingSale(request.operationKey), isTrue);
    final remaining = await uc.invoiceWorkspaces('sale');
    expect(remaining.single.id, suspended.id);
    expect((await db.select(db.saleInvoices).get()).length, 1);
  });

  test('uncommitted pending request returns to the same workspace', () async {
    final active = await uc.saveInvoiceWorkspace(
      kind: 'sale',
      payload: payload('active'),
    );
    final request = await uc.stagePendingSale(
      PendingSale(
        operationKey: uc.newSaleOperationKey(),
        items: [
          const SaleLineInput(productId: 1, qty: 1, unitPriceMinor: 10000),
        ],
        payments: [],
      ),
    );
    expect(
      await uc.restoreUncommittedPendingSaleAsDraft(request.operationKey),
      isTrue,
    );
    expect((await uc.activeInvoiceWorkspace('sale'))!.id, active.id);
    expect((await uc.saleDraft())!.items.single.qty, 1);
  });
}

Future<T> ok<T>(Future<AppResult<T>> action) async {
  final result = await action;
  if (result is AppSuccess<T>) return result.value;
  if (result is AppFailure<T>) fail(result.message);
  throw StateError('$result');
}
