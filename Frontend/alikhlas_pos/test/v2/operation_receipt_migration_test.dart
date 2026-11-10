import 'dart:convert';
import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/data/migration_recovery.dart';
import 'package:alikhlas_pos/v2/data/operation_receipt_codec.dart';
import 'package:alikhlas_pos/v2/data/operation_receipt_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'canonical namespace, legacy null alias and scalar result contracts',
    () {
      final alias = decodeOperationReceipt(
        'operation.sale.once',
        '{"fingerprint":"original","id":null,"saleId":41}',
      );
      expect(alias.resultValue, 41);
      expect(alias.isReady, true);
      expect(
        decodeOperationReceipt(
          'operation.sale.once',
          '{"fingerprint":"f","id":1,"saleId":2}',
        ).isReady,
        false,
      );
      final dotted = decodeOperationReceipt(
        'operation.installment.customer.once',
        '{"fingerprint":"f","id":99}',
      );
      expect(dotted.namespace, 'installment.customer');
      expect(dotted.operationKey, 'once');
      expect(
        decodeOperationReceipt(
          'operation.product_csv_import.once',
          '{"fingerprint":"f","id":5}',
        ).resultKind,
        'scalar_count',
      );
      for (final key in [
        'operation.future.foo',
        'operation.sale.invalid.key',
      ]) {
        final blocked = decodeOperationReceipt(key, 'original bytes');
        expect(blocked.key, key);
        expect(blocked.rawPayload, 'original bytes');
        expect(blocked.isReady, false);
      }
    },
  );

  test(
    'CSV count survives migration, backup, restore and replay without a product with that id',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'receipt-migrate-',
      );
      final file = File('${directory.path}/shop.db');
      final previewDb = AppDatabase(NativeDatabase.memory());
      final preview = await V2UseCases(previewDb).previewProductCsv(
        '${V2UseCases(previewDb).productCsvTemplate()}${List.generate(
              5,
              (i) => 'Product $i,CODE$i,Group,100,0,0,1\r\n',
            ).join()}',
      );
      await previewDb.close();
      expect(preview.canImport, true);
      final fingerprint = sha256
          .convert(
            utf8.encode(
              jsonEncode(preview.rows.map((r) => r.toJson()).toList()),
            ),
          )
          .toString();
      final payload = jsonEncode({'fingerprint': fingerprint, 'id': 5});
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(File('test/fixtures/schema_v13.sql').readAsStringSync());
      for (var i = 0; i < 5; i++) {
        raw.execute(
          'INSERT INTO products(id,name,barcode,sale_price_minor) VALUES (?,?,?,10000)',
          [(i + 1) * 100, 'Product $i', 'CODE$i'],
        );
      }
      raw.execute('INSERT INTO app_settings VALUES (?,?)', [
        'operation.product_csv_import.once',
        payload,
      ]);
      raw.execute(
        "INSERT INTO app_settings VALUES ('operation.future.opaque','not-json')",
      );
      raw.execute(
        "INSERT INTO app_settings VALUES ('operation.sale.broken','{bad')",
      );
      raw.close();
      await MigrationRecovery(
        file,
        targetVersion: kAppDatabaseSchemaVersion,
      ).prepareForOpen();
      var db = AppDatabase(NativeDatabase(file));
      try {
        var uc = V2UseCases(db);
        final repository = OperationReceiptRepository(db);
        final saved = await repository.find(
          'operation.product_csv_import.once',
        );
        expect(saved!.resultKind, 'scalar_count');
        expect(saved.resultValue, 5);
        final migrated = (await db.select(db.operationReceipts).get())
            .singleWhere(
              (r) => r.receiptKey == 'operation.product_csv_import.once',
            );
        expect(migrated.rawPayload, payload);
        expect(migrated.recordedAt, isNull);
        expect(
          (await repository.find('operation.future.opaque'))!.isReady,
          false,
        );
        expect(
          (await repository.find('operation.sale.broken'))!.isReady,
          false,
        );
        final backup = await uc.backupToDirectory(
          Directory('${directory.path}/backups'),
        );
        await uc.restoreFromBackup(backup);
        db = AppDatabase(NativeDatabase(file));
        uc = V2UseCases(db);
        expect(
          (await uc.importProductCsv(operationKey: 'once', rows: preview.rows)
                  as AppSuccess<int>)
              .value,
          5,
        );
        expect(await db.select(db.products).get(), hasLength(5));
        expect(
          await db.customSelect('SELECT 1 FROM products WHERE id=5').get(),
          isEmpty,
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT value FROM app_settings WHERE key='operation.product_csv_import.once'",
                  )
                  .getSingle())
              .data['value'],
          payload,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'new receipt never bypasses a conflicting or unreadable legacy source',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        const key = 'operation.product_csv_import.conflict';
        final repository = OperationReceiptRepository(db);
        await repository.insert(
          decodeOperationReceipt(key, '{"fingerprint":"new","id":5}'),
        );
        for (final payload in ['{"fingerprint":"old","id":5}', 'not-json']) {
          await db.customStatement(
            'INSERT OR REPLACE INTO app_settings VALUES (?,?)',
            [key, payload],
          );
          expect((await repository.find(key))!.isReady, false);
        }
        expect(await db.select(db.products).get(), isEmpty);
        for (final sql in [
          'DELETE FROM operation_receipts',
          "UPDATE operation_receipts SET result_value=6",
          "INSERT OR REPLACE INTO operation_receipts(receipt_key,status,raw_payload) VALUES ('$key','blocked','bad')",
        ]) {
          await expectLater(
            db.customStatement(sql),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }
      } finally {
        await db.close();
      }
    },
  );
}
