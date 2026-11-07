import 'dart:io';

import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final payload in [
    '{"version":2,"draft":null,"editor":{"cash":"١٫"}}',
    '{unreadable',
  ]) {
    test('schema 12 migration preserves draft bytes: $payload', () async {
      final directory = await Directory.systemTemp.createTemp(
        'checkout-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/shop.db');
      final before = AppDatabase(NativeDatabase(file));
      await before.customSelect('SELECT 1').get();
      await before.customStatement(
        'INSERT INTO app_settings(key,value) VALUES (?,?)',
        ['draft.sale.v1', payload],
      );
      await before.customStatement('DROP TABLE checkout_drafts');
      await before.customStatement('PRAGMA user_version=12');
      await before.close();
      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      final uc = V2UseCases(after);
      final row = await uc.activeInvoiceWorkspace('sale');
      expect(row!.payload, payload);
      expect((await uc.invoiceWorkspaces('sale')), hasLength(1));
      expect(
        (await after.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        13,
      );
      expect(
        (await after
            .customSelect(
              "SELECT * FROM app_settings WHERE key='draft.sale.v1'",
            )
            .get()),
        isEmpty,
      );
    });
  }
}
