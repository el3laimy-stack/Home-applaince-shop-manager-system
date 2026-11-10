import 'dart:io';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:alikhlas_pos/v2/data/raw_database_validation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (var version = 3; version <= 15; version++) {
    test(
      'original schema $version preserves identifiers, raw settings and exact values',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'historical-schema-',
        );
        final file = File('${directory.path}/shop.db');
        final raw = sqlite3.open(file.path);
        raw.execute(
          File('test/fixtures/schema_v$version.sql').readAsStringSync(),
        );
        raw.execute(
          "INSERT INTO app_settings VALUES ('operation.unknown.keep','{unreadable original bytes}');",
        );
        if (version < 13) {
          raw.execute(
            "INSERT INTO app_settings VALUES ('draft.sale.v1','{unreadable draft}');",
          );
        }
        raw.execute(
          "INSERT INTO customers(id,name) VALUES (71,'historical customer');",
        );
        raw.execute(
          "INSERT INTO products(id,name,stock_qty,sale_price_minor,avg_cost_minor) VALUES (41,'historical product',3,100,7);",
        );
        if (version >= 10) {
          raw.execute('UPDATE products SET inventory_value_minor=21');
        }
        raw.execute(
          "INSERT INTO ledger_entries(id,reference_type,reference_id,description) VALUES (31,'opening_stock',41,'original posting');",
        );
        raw.execute(
          "INSERT INTO ledger_lines(entry_id,account_code,debit_minor,credit_minor) VALUES (31,'inventory',21,0),(31,'capital',0,21);",
        );
        raw.close();
        final recovery = MigrationRecovery(
          file,
          targetVersion: kAppDatabaseSchemaVersion,
        );
        await recovery.prepareForOpen();
        final db = AppDatabase(NativeDatabase(file));
        try {
          expect(
            (await db.select(db.products).get()).single.inventoryValueMinor,
            21,
          );
          expect((await db.select(db.customers).get()).single.id, 71);
          expect((await db.select(db.ledgerEntries).get()).single.id, 31);
          expect(
            (await db
                    .customSelect(
                      "SELECT value FROM app_settings WHERE key='operation.unknown.keep'",
                    )
                    .getSingle())
                .data['value'],
            '{unreadable original bytes}',
          );
          if (version < 13) {
            expect(
              (await db.select(db.checkoutDrafts).get()).single.payload,
              '{unreadable draft}',
            );
          }
          expect(await recovery.marker.exists(), false);
        } finally {
          await db.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }

  for (final invalid in ["2.5", "'non numeric'"]) {
    test(
      'raw storage $invalid fails before generated mapping or schema writes',
      () async {
        final raw = sqlite3.openInMemory();
        raw.execute(File('test/fixtures/schema_v9.sql').readAsStringSync());
        raw.execute(
          "INSERT INTO products(name,stock_qty,sale_price_minor) VALUES ('bad',$invalid,100)",
        );
        final model = AppDatabase(NativeDatabase.memory());
        try {
          await expectLater(
            validateRawDatabase(sqliteReader(raw), model, version: 9),
            throwsA(isA<DatabaseContractViolation>()),
          );
        } finally {
          raw.close();
          await model.close();
        }
      },
    );
  }

  test(
    'pre10 overflowing backfill rolls back, preserves markers and recovers original',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'historical-overflow-',
      );
      final file = File('${directory.path}/shop.db');
      final raw = sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v9.sql').readAsStringSync());
      raw.execute(
        "INSERT INTO products(name,stock_qty,sale_price_minor,avg_cost_minor) VALUES ('overflow',2,1,9223372036854775807)",
      );
      raw.close();
      final recovery = MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      );
      await recovery.prepareForOpen();
      final db = AppDatabase(NativeDatabase(file));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<DatabaseMigrationFailedDuringUpgrade>()),
      );
      await db.close();
      expect(await recovery.marker.exists(), true);
      await expectLater(
        recovery.prepareForOpen(),
        throwsA(isA<DatabaseMigrationFailed>()),
      );
      final restored = sqlite3.open(file.path);
      expect(restored.select('PRAGMA user_version').single.values.single, 9);
      expect(
        restored
            .select('SELECT avg_cost_minor FROM products')
            .single
            .values
            .single,
        9223372036854775807,
      );
      expect(
        restored
            .select('PRAGMA table_info(products)')
            .any((r) => r['name'] == 'inventory_value_minor'),
        false,
      );
      restored.close();
      await directory.delete(recursive: true);
    },
  );
  for (final invalid in ['zero-expense', 'account-overflow']) {
    test('old $invalid is rejected before writes and acceptance', () async {
      final directory = await Directory.systemTemp.createTemp(
        'contract-refusal-',
      );
      final file = File('${directory.path}/shop.db');
      final raw = sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v13.sql').readAsStringSync());
      if (invalid == 'zero-expense') {
        raw.execute(
          "INSERT INTO expenses(description,amount_minor,method) VALUES ('bad',0,'wallet')",
        );
      } else {
        for (var id = 1; id <= 2; id++) {
          raw.execute(
            "INSERT INTO products(id,name,stock_qty,sale_price_minor,avg_cost_minor,inventory_value_minor) VALUES (?,'large',1,1,9223372036854775807,9223372036854775807)",
            [id],
          );
          raw.execute(
            "INSERT INTO ledger_entries(id,reference_type,reference_id,description) VALUES (?,'opening_stock',?,'large')",
            [id, id],
          );
          raw.execute(
            "INSERT INTO ledger_lines(entry_id,account_code,debit_minor,credit_minor) VALUES (?,'inventory',9223372036854775807,0),(?,'capital',0,9223372036854775807)",
            [id, id],
          );
        }
      }
      raw.close();
      final recovery = MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      );
      await recovery.prepareForOpen();
      final db = AppDatabase(NativeDatabase(file));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<DatabaseMigrationFailedDuringUpgrade>()),
      );
      await db.close();
      expect(await recovery.marker.exists(), true);
      final unchanged = sqlite3.open(file.path);
      expect(unchanged.select('PRAGMA user_version').single.values.single, 13);
      unchanged.close();
      await directory.delete(recursive: true);
    });
  }
}
