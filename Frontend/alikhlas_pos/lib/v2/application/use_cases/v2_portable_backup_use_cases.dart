part of '../v2_use_cases.dart';

class _PortableAsset {
  const _PortableAsset({
    required this.kind,
    required this.sourcePath,
    required this.archivePath,
    required this.sha256,
  });

  final String kind;
  final String sourcePath;
  final String archivePath;
  final String sha256;

  Map<String, String> toJson() => {
    'kind': kind,
    'sourcePath': sourcePath,
    'archivePath': archivePath,
    'sha256': sha256,
  };

  factory _PortableAsset.fromJson(Object source) {
    if (source is! Map) throw const FormatException('فهرس الصور غير صالح.');
    final kind = source['kind'];
    final sourcePath = source['sourcePath'];
    final archivePath = source['archivePath'];
    final digest = source['sha256'];
    if ((kind != 'product' && kind != 'background') ||
        sourcePath is! String ||
        archivePath is! String ||
        digest is! String ||
        !_safeArchivePath(archivePath) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('فهرس الصور غير صالح.');
    }
    return _PortableAsset(
      kind: kind,
      sourcePath: sourcePath,
      archivePath: archivePath,
      sha256: digest,
    );
  }
}

bool _safeArchivePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/')) return false;
  final segments = normalized.split('/');
  return !segments.any(
    (segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains(':'),
  );
}

extension V2PortableBackupUseCases on V2UseCases {
  static const _manifestPath = 'manifest.json';
  static const _databasePath = 'database.db';
  static const _maxArchiveBytes = 512 * 1024 * 1024;
  static const _maxExtractedBytes = 1024 * 1024 * 1024;
  static const _maxArchiveEntries = 10000;

  Future<File> createPortableBackup(Directory destination) async {
    if (_backupRunning ||
        _automaticBackupRunning ||
        _restoreRunning ||
        databaseClosedForRestore) {
      throw StateError('انتظر انتهاء النسخ أو الاسترجاع الحالي.');
    }
    _backupRunning = true;
    Directory? staging;
    try {
      await destination.create(recursive: true);
      staging = await destination.createTemp('alikhlas-portable-');
      final database = File(p.join(staging.path, _databasePath));
      await _writeDatabaseSnapshot(database);
      final assets = await _stagePortableAssets(staging, database);
      final databaseDigest = await _sha256File(database);
      await File(p.join(staging.path, _manifestPath)).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'createdAt': clock().toIso8601String(),
          'database': {'path': _databasePath, 'sha256': databaseDigest},
          'assets': [for (final asset in assets) asset.toJson()],
        }),
        flush: true,
      );
      final stamp = clock().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final target = File(
        p.join(destination.path, 'alikhlas-portable-$stamp.zip'),
      );
      final partial = File('${target.path}.partial');
      final encoder = ZipFileEncoder();
      await encoder.zipDirectory(staging, filename: partial.path);
      await partial.rename(target.path);
      backupWarning = null;
      return target;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      _backupRunning = false;
    }
  }

  Future<void> restoreFromPortableBackup(File bundle) async {
    if (_backupRunning ||
        _automaticBackupRunning ||
        _restoreRunning ||
        databaseClosedForRestore) {
      throw StateError('انتظر انتهاء النسخ أو أعد فتح التطبيق بعد الاسترجاع.');
    }
    _restoreRunning = true;
    try {
      await _withRestoreWriteBarrier(() => _restorePortableBundle(bundle));
    } finally {
      _restoreRunning = false;
    }
  }

  List<(String, String)> _portableImageReferences(sqlite.Database database) => [
    for (final row in database.select(
      'SELECT image_path FROM products WHERE image_path IS NOT NULL AND trim(image_path) != \'\'',
    ))
      ('product', row['image_path'] as String),
    for (final row in database.select(
      "SELECT value FROM app_settings WHERE key = 'ui.backgroundImagePath' AND trim(value) != ''",
    ))
      ('background', row['value'] as String),
  ];

  Future<List<_PortableAsset>> _stagePortableAssets(
    Directory staging,
    File snapshot,
  ) async {
    final assets = <_PortableAsset>[];
    final reader = sqlite.sqlite3.open(
      snapshot.path,
      mode: sqlite.OpenMode.readOnly,
    );
    late List<(String, String)> paths;
    try {
      paths = _portableImageReferences(reader);
    } finally {
      reader.close();
    }
    final seen = <String>{};
    for (final (kind, sourcePath) in paths) {
      if (!seen.add('$kind\u0000$sourcePath')) {
        continue;
      }
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw FormatException(
          'تعذر تضمين الصورة المحفوظة: ${p.basename(sourcePath)}',
        );
      }
      // Hash the staged bytes, never a live file that might change before copy.
      final temporary = File(
        p.join(staging.path, 'asset-${assets.length}.partial'),
      );
      await source.copy(temporary.path);
      final digest = await _sha256File(temporary);
      final extension = p.extension(source.path).toLowerCase();
      final archivePath = 'assets/$kind/$digest$extension';
      final staged = File(p.joinAll([staging.path, ...archivePath.split('/')]));
      if (!await staged.exists()) {
        await staged.parent.create(recursive: true);
        await temporary.rename(staged.path);
      }
      if (await temporary.exists()) await temporary.delete();
      assets.add(
        _PortableAsset(
          kind: kind,
          sourcePath: sourcePath,
          archivePath: archivePath,
          sha256: digest,
        ),
      );
    }
    return assets;
  }

  Future<void> _restorePortableBundle(File bundle) async {
    if (!await bundle.exists() || (await bundle.length()) > _maxArchiveBytes) {
      throw const FormatException(
        'حزمة النسخ غير موجودة أو أكبر من الحد المسموح.',
      );
    }
    final currentDatabase = await _currentDatabaseFile();
    final staging = await currentDatabase.parent.createTemp(
      'restore-portable-',
    );
    try {
      await _extractPortableBundle(bundle, staging);
      final manifest = await _readPortableManifest(staging);
      final candidate = File(p.join(staging.path, _databasePath));
      if (!await candidate.exists()) {
        throw const FormatException('الحزمة لا تحتوي قاعدة البيانات المطلوبة.');
      }
      if (await _sha256File(candidate) != manifest.databaseDigest) {
        throw const FormatException(
          'بصمة قاعدة البيانات في الحزمة لا تطابق محتواها.',
        );
      }
      await _prepareRestoreCandidate(candidate);
      await _installPortableAssets(
        staging: staging,
        candidate: candidate,
        appDataDirectory: currentDatabase.parent,
        assets: manifest.assets,
      );
      _validateCurrentRestoreFile(candidate);
      await _restoreBackupFile(candidate);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _extractPortableBundle(File bundle, Directory staging) async {
    final input = InputFileStream(bundle.path);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > _maxArchiveEntries) {
        throw const FormatException(
          'الحزمة تحتوي عدد ملفات أكبر من الحد المسموح.',
        );
      }
      var totalSize = 0;
      for (final entry in archive) {
        final entryPath = entry.isDirectory
            ? entry.name.replaceFirst(RegExp(r'[/\\]+$'), '')
            : entry.name;
        if (entry.isSymbolicLink || !_safeArchivePath(entryPath)) {
          throw const FormatException('الحزمة تحتوي مسارًا غير آمن.');
        }
        if (entry.isDirectory) continue;
        totalSize += entry.size;
        if (entry.size < 0 || totalSize > _maxExtractedBytes) {
          throw const FormatException('الحزمة أكبر من الحد الآمن للاستخراج.');
        }
        final target = File(p.joinAll([staging.path, ...entryPath.split('/')]));
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
          await entry.close();
        }
      }
    } on ArchiveException {
      throw const FormatException('ملف الحزمة غير صالح أو تالف.');
    } finally {
      await input.close();
    }
  }

  Future<({String databaseDigest, List<_PortableAsset> assets})>
  _readPortableManifest(Directory staging) async {
    try {
      final source = await File(
        p.join(staging.path, _manifestPath),
      ).readAsString();
      final data = jsonDecode(source) as Map<String, dynamic>;
      final database = data['database'];
      final digest = database is Map ? database['sha256'] : null;
      final path = database is Map ? database['path'] : null;
      if (data['formatVersion'] != 1 ||
          path != _databasePath ||
          digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          data['assets'] is! List) {
        throw const FormatException('فهرس الحزمة غير متوافق.');
      }
      return (
        databaseDigest: digest,
        assets: [
          for (final value in data['assets'] as List)
            _PortableAsset.fromJson(value),
        ],
      );
    } on FileSystemException {
      throw const FormatException('الحزمة لا تحتوي فهرسًا صالحًا.');
    } on TypeError {
      throw const FormatException('فهرس الحزمة غير صالح.');
    }
  }

  Future<void> _installPortableAssets({
    required Directory staging,
    required File candidate,
    required Directory appDataDirectory,
    required List<_PortableAsset> assets,
  }) async {
    sqlite.Database? database;
    try {
      database = sqlite.sqlite3.open(candidate.path);
      database.execute('BEGIN;');
      final references = _portableImageReferences(database).toSet();
      final mapped = <(String, String), _PortableAsset>{};
      for (final asset in assets) {
        final key = (asset.kind, asset.sourcePath);
        if (mapped.containsKey(key)) {
          throw const FormatException('فهرس الحزمة يحتوي مراجع صور مكررة.');
        }
        mapped[key] = asset;
      }
      if (!references.every(mapped.containsKey)) {
        throw const FormatException(
          'الحزمة لا تشمل جميع الصور المشار إليها في قاعدة البيانات.',
        );
      }
      for (final asset in assets) {
        final source = File(
          p.joinAll([staging.path, ...asset.archivePath.split('/')]),
        );
        if (!await source.exists() ||
            await _sha256File(source) != asset.sha256) {
          throw const FormatException('بصمة صورة في الحزمة غير مطابقة.');
        }
        final bucket = asset.kind == 'product'
            ? 'product-images'
            : 'backgrounds';
        final target = File(
          p.join(
            appDataDirectory.path,
            bucket,
            'restored-${p.basename(asset.archivePath)}',
          ),
        );
        await target.parent.create(recursive: true);
        if (await target.exists()) {
          if (await _sha256File(target) != asset.sha256) {
            throw const FormatException('يوجد ملف صورة متعارض على هذا الجهاز.');
          }
        } else {
          await source.copy(target.path);
        }
        if (asset.kind == 'product') {
          database.execute(
            'UPDATE products SET image_path = ? WHERE image_path = ?',
            [target.path, asset.sourcePath],
          );
        } else {
          database.execute(
            "UPDATE app_settings SET value = ? WHERE key = 'ui.backgroundImagePath' AND value = ?",
            [target.path, asset.sourcePath],
          );
        }
      }
      database.execute('COMMIT;');
    } catch (_) {
      database?.execute('ROLLBACK;');
      rethrow;
    } finally {
      database?.close();
    }
  }

  Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
