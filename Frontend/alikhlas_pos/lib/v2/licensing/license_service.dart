import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_identity.dart';
import 'license_verifier.dart';

class LicenseStatus {
  const LicenseStatus({required this.deviceId, required this.result});
  final String deviceId;
  final LicenseResult result;
}

/// A license is deliberately NOT in SQLite, so importing a backup does not
/// overwrite machine activation. It remains machine-bound if copied anyway.
class LicenseService {
  LicenseService({
    DeviceIdentity? identity,
    LicenseVerifier? verifier,
    Future<Directory> Function()? storageDirectory,
  })  : identity = identity ?? const DeviceIdentity(),
        verifier = verifier ??
            const LicenseVerifier(
              publicKeyBase64: String.fromEnvironment(
                'ALIKHLAS_LICENSE_PUBLIC_KEY',
              ),
            ),
        _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  final DeviceIdentity identity;
  final LicenseVerifier verifier;
  final Future<Directory> Function() _storageDirectory;

  Future<File> _licenseFile() async {
    final directory = await _storageDirectory();
    return File(p.join(directory.path, 'alikhlas.activation.license'));
  }

  Future<LicenseStatus> check() async {
    final deviceId = await identity.fingerprint();
    final file = await _licenseFile();
    if (!await file.exists()) {
      return LicenseStatus(
        deviceId: deviceId,
        result: const LicenseResult(false, 'التطبيق يحتاج إلى تفعيل لهذا الجهاز.'),
      );
    }
    try {
      final document = await file.readAsString();
      final result = await verifier.verify(document, deviceId);
      return LicenseStatus(deviceId: deviceId, result: result);
    } on FileSystemException {
      return LicenseStatus(
        deviceId: deviceId,
        result: const LicenseResult(false, 'تعذر قراءة ملف التفعيل المحلي.'),
      );
    }
  }

  /// Never replace an existing valid license unless the new document verifies.
  Future<LicenseResult> importLicense(String document) async {
    final deviceId = await identity.fingerprint();
    final result = await verifier.verify(document, deviceId);
    if (!result.valid) return result;
    final file = await _licenseFile();
    await file.parent.create(recursive: true);
    // A small signed document; invalid/partial writes fail closed on restart.
    await file.writeAsString(document, flush: true);
    return result;
  }
}
