import 'dart:async';
import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class PauseAfterSnapshot extends QueryInterceptor {
  bool armed = false;
  final snapshotReady = Completer<void>();
  final releaseSnapshot = Completer<void>();

  @override
  Future<void> runCustom(QueryExecutor executor, String statement, List<Object?> args) async {
    await executor.runCustom(statement, args);
    if (armed && statement.startsWith('VACUUM INTO')) {
      armed = false;
      snapshotReady.complete();
      await releaseSnapshot.future;
    }
  }
}

void main() {
  test('portable backup keeps assets consistent with its database snapshot during product edits', () async {
    final root = await Directory.systemTemp.createTemp('audit-portable-race-');
    addTearDown(() => root.delete(recursive: true));
    final sourceDir = await Directory('${root.path}/source').create();
    final oldImage = await File('${sourceDir.path}/original.png').writeAsBytes([1,2,3]);
    final newImage = await File('${sourceDir.path}/replacement.png').writeAsBytes([4,5,6]);
    final pause = PauseAfterSnapshot();
    final sourceDb = AppDatabase(NativeDatabase(File('${sourceDir.path}/shop.db')).interceptWith(pause));
    addTearDown(sourceDb.close);
    final source = V2UseCases(sourceDb);
    final product = (await source.createProduct(name: 'Washer', salePriceMinor: 10000, openingQty: 0, openingCostMinor: 0, imagePath: oldImage.path) as AppSuccess<Product>).value;
    pause.armed = true;
    final backup = source.createPortableBackup(Directory('${root.path}/backups'));
    await pause.snapshotReady.future;
    // An ordinary, authorized product edit while the completed SQLite snapshot
    // is awaiting its continuation. No snapshot or archive bytes are altered.
    final edit = await source.updateProduct(id: product.id, name: product.name, barcode: product.barcode, imagePath: newImage.path, salePriceMinor: product.salePriceMinor, minStockQty: 1);
    expect(edit, isA<AppSuccess<Product>>());
    pause.releaseSnapshot.complete();
    final bundle = await backup;
    await sourceDb.close();
    await sourceDir.delete(recursive: true);

    final targetDir = await Directory('${root.path}/target').create();
    final targetFile = File('${targetDir.path}/shop.db');
    final targetDb = AppDatabase(NativeDatabase(targetFile));
    addTearDown(targetDb.close);
    await V2UseCases(targetDb).restoreFromPortableBackup(bundle);
    final reopened = AppDatabase(NativeDatabase(targetFile));
    addTearDown(reopened.close);
    final restored = await reopened.select(reopened.products).getSingle();
    final imageExists = await File(restored.imagePath!).exists();
    expect(imageExists, isTrue, reason: 'A successful portable backup must include the image referenced by its database snapshot.');
  });
}
