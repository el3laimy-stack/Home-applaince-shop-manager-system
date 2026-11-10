import 'dart:io';
import 'package:alikhlas_pos/v2/core/money.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'stored delta magnitude is checked while signed Money still represents int64 minimum',
    () {
      expect(absoluteMinor(-9223372036854775807), 9223372036854775807);
      expect(
        () => absoluteMinor(-9223372036854775808),
        throwsA(isA<MoneyRangeException>()),
      );
      expect(
        const Money(-9223372036854775808).formatPlain(),
        '-92,233,720,368,547,758.08 ج.م',
      );
    },
  );
  test(
    'SQL delta contracts reject the sole int64 value without a representable positive magnitude',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.customStatement(
          "INSERT INTO products(id,name,sale_price_minor) VALUES (1,'fixture',1)",
        );
        for (final statement in [
          "INSERT INTO financial_corrections(target,delta_minor,reason) VALUES ('wallet',-9223372036854775808,'fixture')",
          "INSERT INTO inventory_adjustments(product_id,previous_qty,counted_qty,unit_cost_minor,value_delta_minor,reason) VALUES (1,1,0,1,-9223372036854775808,'damage')",
        ]) {
          await expectLater(
            db.customStatement(statement),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }
      } finally {
        await db.close();
      }
    },
  );
  test(
    'legacy invalid correction magnitude fails closed without rewriting its historical value',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'legacy-magnitude-',
      );
      final file = File('${directory.path}/shop.db');
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v13.sql').readAsStringSync());
      raw.execute(
        "INSERT INTO financial_corrections(target,delta_minor,reason) VALUES ('wallet',-9223372036854775808,'original')",
      );
      raw.close();
      final recovery = MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      );
      await recovery.prepareForOpen();
      final db = AppDatabase(NativeDatabase(file));
      try {
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<DatabaseMigrationFailedDuringUpgrade>()),
        );
        expect(await recovery.marker.exists(), true);
        final source = sqlite.sqlite3.open(file.path);
        expect(
          source
              .select('SELECT delta_minor FROM financial_corrections')
              .single
              .values
              .single,
          -9223372036854775808,
        );
        source.close();
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
