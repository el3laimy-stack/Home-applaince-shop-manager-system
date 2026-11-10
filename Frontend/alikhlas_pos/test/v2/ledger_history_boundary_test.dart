import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'posted invoice rejects appended issuance payment and stock movement',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final uc = V2UseCases(db);
      final directory = await Directory.systemTemp.createTemp(
        'history-boundary-',
      );
      try {
        final product =
            (await uc.createProduct(
                      operationKey: 'stock',
                      name: 'fixture',
                      salePriceMinor: 5,
                      openingQty: 1,
                      openingCostMinor: 1,
                    )
                    as AppSuccess<Product>)
                .value;
        final sale =
            (await uc.createSale(
                      operationKey: 'sale',
                      items: [
                        SaleLineInput(
                          productId: product.id,
                          qty: 1,
                          unitPriceMinor: 5,
                        ),
                      ],
                      payments: [PaymentInput(PaymentMethod.wallet, 5)],
                    )
                    as AppSuccess<int>)
                .value;
        await expectLater(
          db.customStatement(
            "INSERT INTO payments(owner_type,owner_id,method,amount_minor) VALUES ('sale',?,'wallet',1)",
            [sale],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          db.customStatement(
            "INSERT INTO stock_movements(product_id,type,qty_delta,balance_after,reference_type,reference_id) VALUES (?,'sale',-1,0,'sale',?)",
            [product.id, sale],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(await db.select(db.payments).get(), hasLength(1));
        expect(await db.select(db.stockMovements).get(), hasLength(2));
        expect(await (await uc.backupToDirectory(directory)).exists(), true);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'preserved historical minus-one identities permit auto ids and reject real replacement',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'legacy-negative-identity-',
      );
      final file = File('${directory.path}/shop.db');
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v15.sql').readAsStringSync());
      raw.execute(
        "INSERT INTO expenses(id,description,amount_minor,method) VALUES (1,'old expense',1,'wallet'); INSERT INTO products(id,name,stock_qty,sale_price_minor,avg_cost_minor,inventory_value_minor) VALUES (-1,'old product',1,1,1,1); INSERT INTO ledger_entries(id,reference_type,reference_id,description) VALUES (-1,'expense',1,'old expense'),(-2,'opening_stock',-1,'old product'); INSERT INTO ledger_lines(id,entry_id,account_code,debit_minor,credit_minor) VALUES (-1,-1,'expenses',1,0),(-2,-1,'wallet',0,1),(-3,-2,'inventory',1,0),(-4,-2,'capital',0,1);",
      );
      raw.close();
      await MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      ).prepareForOpen();
      final db = AppDatabase(NativeDatabase(file));
      final uc = V2UseCases(db);
      try {
        final result = await uc.recordExpense(
          operationKey: 'new',
          description: 'new expense',
          amountMinor: 1,
          method: PaymentMethod.wallet,
          allowNegativeBalance: true,
        );
        expect(result, isA<AppSuccess<int>>());
        expect(
          (await db.select(db.ledgerEntries).get()).any(
            (r) => r.id == -1 && r.postingState == 'posted',
          ),
          true,
        );
        expect(
          await uc.createProduct(
            operationKey: 'new-product',
            name: 'new product',
            salePriceMinor: 1,
            openingQty: 0,
            openingCostMinor: 0,
          ),
          isA<AppSuccess<Product>>(),
        );
        await db.customStatement('PRAGMA recursive_triggers=OFF');
        for (final statement in [
          "INSERT OR REPLACE INTO ledger_entries(id,reference_type,reference_id,description) VALUES (-1,'expense',1,'replacement')",
          "INSERT OR REPLACE INTO ledger_lines(id,entry_id,account_code,debit_minor) VALUES (-1,1,'expenses',1)",
          "UPDATE OR REPLACE ledger_lines SET id=-1 WHERE id=1",
          "INSERT OR REPLACE INTO products(id,name,sale_price_minor) VALUES (-1,'replacement',1)",
        ]) {
          await expectLater(
            db.customStatement(statement),
            throwsA(isA<sqlite.SqliteException>()),
            reason: statement,
          );
        }
        expect(
          (await db.select(db.products).get())
              .singleWhere((p) => p.id == -1)
              .name,
          'old product',
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
