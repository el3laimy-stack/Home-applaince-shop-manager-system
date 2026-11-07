import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/drift.dart';
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class PauseAfterSnapshot extends QueryInterceptor {
  bool armed = false;
  final snapshotReady = Completer<void>();
  final releaseSnapshot = Completer<void>();

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (armed && statement.startsWith('VACUUM INTO')) {
      armed = false;
      snapshotReady.complete();
      await releaseSnapshot.future;
    }
  }
}

void main() {
  test(
    'missing manifest asset is rejected while the live database stays usable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'audit-missing-asset-',
      );
      addTearDown(() => root.delete(recursive: true));
      final sourceDb = AppDatabase(
        NativeDatabase(File('${root.path}/source.db')),
      );
      addTearDown(sourceDb.close);
      final source = V2UseCases(sourceDb);
      final image = await File(
        '${root.path}/image.png',
      ).writeAsBytes([1, 2, 3]);
      await source.createProduct(
        name: 'Image',
        imagePath: image.path,
        salePriceMinor: 100,
        openingQty: 0,
        openingCostMinor: 0,
      );
      final bundle = await source.createPortableBackup(
        Directory('${root.path}/backups'),
      );
      final archive = ZipDecoder().decodeBytes(await bundle.readAsBytes());
      final rebuilt = Archive();
      for (final entry in archive) {
        if (entry.name == 'manifest.json') {
          final manifest =
              jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
          manifest['assets'] = [];
          rebuilt.addFile(
            ArchiveFile.string('manifest.json', jsonEncode(manifest)),
          );
        } else {
          rebuilt.addFile(entry);
        }
      }
      await bundle.writeAsBytes(ZipEncoder().encode(rebuilt));
      final live = AppDatabase(NativeDatabase(File('${root.path}/live.db')));
      addTearDown(live.close);
      final target = V2UseCases(live);
      await target.updateShopSettings(shopName: 'Live store');
      await expectLater(
        target.restoreFromPortableBackup(bundle),
        throwsA(isA<FormatException>()),
      );
      expect(target.databaseClosedForRestore, isFalse);
      expect((await target.shopSettings()).shopName, 'Live store');
    },
  );

  test(
    'portable backup keeps assets consistent with its database snapshot during product edits',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'audit-portable-race-',
      );
      addTearDown(() => root.delete(recursive: true));
      final sourceDir = await Directory('${root.path}/source').create();
      final oldImage = await File(
        '${sourceDir.path}/original.png',
      ).writeAsBytes([1, 2, 3]);
      final newImage = await File(
        '${sourceDir.path}/replacement.png',
      ).writeAsBytes([4, 5, 6]);
      final pause = PauseAfterSnapshot();
      final sourceDb = AppDatabase(
        NativeDatabase(File('${sourceDir.path}/shop.db')).interceptWith(pause),
      );
      addTearDown(sourceDb.close);
      final source = V2UseCases(sourceDb);
      final product =
          (await source.createProduct(
                    name: 'Washer',
                    salePriceMinor: 10000,
                    openingQty: 0,
                    openingCostMinor: 0,
                    imagePath: oldImage.path,
                  )
                  as AppSuccess<Product>)
              .value;
      pause.armed = true;
      final backup = source.createPortableBackup(
        Directory('${root.path}/backups'),
      );
      await pause.snapshotReady.future;
      // An ordinary, authorized product edit while the completed SQLite snapshot
      // is awaiting its continuation. No snapshot or archive bytes are altered.
      final edit = await source.updateProduct(
        id: product.id,
        name: product.name,
        barcode: product.barcode,
        imagePath: newImage.path,
        salePriceMinor: product.salePriceMinor,
        minStockQty: 1,
      );
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
      expect(
        imageExists,
        isTrue,
        reason:
            'A successful portable backup must include the image referenced by its database snapshot.',
      );
    },
  );
}
