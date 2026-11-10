import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());
  test('integer contracts reject REAL and text on INSERT and UPDATE', () async {
    for (final value in ['1.5', "'bad'"]) {
      await expectLater(
        db.customStatement(
          "INSERT INTO products(name,stock_qty,sale_price_minor) VALUES ('bad',$value,100)",
        ),
        throwsA(isA<SqliteException>()),
      );
    }
    await db.customStatement(
      "INSERT INTO products(id,name,sale_price_minor) VALUES (1,'valid',100)",
    );
    for (final assignment in [
      'stock_qty=2.5',
      "avg_cost_minor='bad'",
      'is_active=2',
      'created_at=1.5',
      'inventory_value_minor=1.1',
    ]) {
      await expectLater(
        db.customStatement('UPDATE products SET $assignment WHERE id=1'),
        throwsA(isA<SqliteException>()),
      );
    }
  });
  test('line quantity guards cover updates, including return and purchase lines', () async {
    await db.customStatement(
      "INSERT INTO products(id,name,sale_price_minor) VALUES (1,'fixture',100)",
    );
    await db.customStatement(
      "INSERT INTO sale_invoices(id,invoice_no,subtotal_minor,total_minor,paid_minor,remaining_minor) VALUES (1,'S-1',1,1,1,0)",
    );
    await db.customStatement(
      "INSERT INTO purchase_invoices(id,invoice_no,total_minor,paid_minor,remaining_minor) VALUES (1,'P-1',0,0,0)",
    );
    await db.customStatement(
      "INSERT INTO sale_returns(id,sale_id,return_no,refund_minor) VALUES (1,1,'SR-1',1)",
    );
    await db.customStatement(
      "INSERT INTO purchase_returns(id,purchase_id,return_no,credit_minor) VALUES (1,1,'PR-1',0)",
    );
    for (final spec in [
      [
        'sale_items',
        'sale_id,product_id,qty,unit_price_minor,unit_cost_minor,line_total_minor',
        '1,1,1,1,0,1',
      ],
      [
        'purchase_items',
        'purchase_id,product_id,qty,unit_cost_minor,line_total_minor',
        '1,1,1,0,0',
      ],
      [
        'sale_return_items',
        'return_id,sale_item_id,product_id,qty,unit_price_minor,unit_cost_minor',
        '1,1,1,1,1,0',
      ],
      [
        'purchase_return_items',
        'return_id,purchase_item_id,product_id,qty,unit_cost_minor,inventory_unit_cost_minor',
        '1,1,1,1,0,0',
      ],
    ]) {
      await db.customStatement(
        'INSERT INTO ${spec[0]}(${spec[1]}) VALUES (${spec[2]})',
      );
      for (final qty in ['0', '-1', '1.5', "'bad'"]) {
        await expectLater(
          db.customStatement('UPDATE ${spec[0]} SET qty=$qty'),
          throwsA(isA<SqliteException>()),
        );
      }
    }
  });
  test('one open shift and opening uniqueness handle NULL explicitly', () async {
    await db.customStatement(
      "INSERT INTO shifts(opened_at,opening_cash_minor) VALUES (1,0)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO shifts(opened_at,opening_cash_minor) VALUES (2,0)",
      ),
      throwsA(isA<SqliteException>()),
    );
    await db.customStatement("UPDATE shifts SET status='closed'");
    await db.customStatement(
      "INSERT INTO shifts(opened_at,opening_cash_minor) VALUES (2,0)",
    );
    await db.customStatement(
      "INSERT INTO opening_balances(balance_type,amount_minor) VALUES ('cash',1)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO opening_balances(balance_type,amount_minor) VALUES ('cash',2)",
      ),
      throwsA(isA<SqliteException>()),
    );
    await db.customStatement(
      "INSERT INTO opening_balances(balance_type,amount_minor) VALUES ('wallet',1)",
    );
  });
  test(
    'baseline is immutable through update, delete, REPLACE and UPSERT',
    () async {
      for (final sql in [
        "UPDATE migration_baselines SET value='1'",
        'DELETE FROM migration_baselines',
        "INSERT OR REPLACE INTO migration_baselines VALUES ('inventory_ledger_delta','1',14)",
        "INSERT INTO migration_baselines VALUES ('inventory_ledger_delta','1',14) ON CONFLICT(key) DO UPDATE SET value='1'",
      ]) {
        await expectLater(
          db.customStatement(sql),
          throwsA(isA<SqliteException>()),
        );
      }
    },
  );
  test('opening type, party and due date form one consistent contract', () async {
    for (final values in [
      "'cash',99,5,123",
      "'wallet',NULL,5,123",
      "'customerReceivable',NULL,5,123",
      "'supplierPayable',99,5,123",
    ]) {
      await expectLater(
        db.customStatement(
          'INSERT INTO opening_balances(balance_type,party_id,amount_minor,due_date) VALUES ($values)',
        ),
        throwsA(isA<SqliteException>()),
      );
    }
  });
}
