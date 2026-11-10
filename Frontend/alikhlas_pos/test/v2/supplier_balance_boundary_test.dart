import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';

void main() {
  test(
    'supplier natural balance must remain representable before purchase success',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final uc = V2UseCases(db);
      final dir = await Directory.systemTemp.createTemp('supplier-sign-');
      try {
        final p =
            (await uc.createProduct(
                      operationKey: 'product',
                      name: 'fixture',
                      salePriceMinor: 1,
                      openingQty: 0,
                      openingCostMinor: 0,
                    )
                    as AppSuccess<Product>)
                .value;
        await db.customStatement(
          "INSERT INTO suppliers(id,name) VALUES (1,'supplier')",
        );
        expect(
          await uc.createPurchase(
            operationKey: 'big-buy',
            supplierId: 1,
            items: [
              PurchaseLineInput(
                productId: p.id,
                qty: 1,
                unitCostMinor: 9223372036854775807,
              ),
            ],
            payments: [],
            allowNegativeBalance: true,
          ),
          isA<AppSuccess<int>>(),
        );
        expect(
          await uc.createSale(
            operationKey: 'sell',
            items: [SaleLineInput(productId: p.id, qty: 1, unitPriceMinor: 1)],
            payments: [PaymentInput(PaymentMethod.wallet, 1)],
          ),
          isA<AppSuccess<int>>(),
        );
        final result = await uc.createPurchase(
          operationKey: 'one-buy',
          supplierId: 1,
          items: [PurchaseLineInput(productId: p.id, qty: 1, unitCostMinor: 1)],
          payments: [],
          allowNegativeBalance: true,
        );
        Object? workbenchError;
        try {
          await uc.workbenchSnapshot();
        } catch (e) {
          workbenchError = e;
        }
        Object? backupError;
        try {
          await uc.backupToDirectory(dir);
        } catch (e) {
          backupError = e;
        }
        expect(workbenchError, isNull);
        expect(backupError, isNull);
        expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
        expect((await db.select(db.products).get()).single.stockQty, 0);
        expect(
          await db
              .customSelect(
                "SELECT 1 FROM operation_receipts WHERE receipt_key='operation.purchase.one-buy'",
              )
              .get(),
          isEmpty,
        );
        expect(
          result,
          isA<AppFailure<int>>(),
          reason:
              'Supplier liability maxInt64+1 cannot fit the PartyBalance after reversing the native credit sign',
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
