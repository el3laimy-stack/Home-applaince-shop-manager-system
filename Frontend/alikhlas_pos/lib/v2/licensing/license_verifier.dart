import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Format shared with tool/license_admin.py. Any change requires a v2 format.
const licenseDomain = 'ALIKHLAS-POS-LICENSE-V1\n';
const licenseFormat = 'alikhlas-license-v1';
const licenseProduct = 'alikhlas-pos';

class LicenseResult {
  const LicenseResult(this.valid, this.message, {this.customer, this.licenseId});
  final bool valid;
  final String message;
  final String? customer;
  final String? licenseId;
}

class LicenseVerifier {
  const LicenseVerifier({required this.publicKeyBase64});

  /// This PUBLIC key is injected at build time. Never embed a private key.
  final String publicKeyBase64;

  static const _requiredFields = {
    'product',
    'license_id',
    'customer',
    'device_id',
    'issued_at',
    'expires_at',
  };

  Future<LicenseResult> verify(
    String document,
    String deviceId, {
    DateTime? currentTime,
  }) async {
    try {
      if (publicKeyBase64.trim().isEmpty) {
        return const LicenseResult(false, 'لم يتم تجهيز مفتاح التفعيل لهذا الإصدار. تواصل مع الدعم.');
      }
      final key = base64.decode(publicKeyBase64);
      if (key.length != 32) {
        return const LicenseResult(false, 'مفتاح التحقق من الترخيص غير صالح.');
      }
      final decoded = jsonDecode(document);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 3 ||
          decoded['format'] != licenseFormat ||
          decoded['payload'] is! Map<String, dynamic> ||
          decoded['signature'] is! String) {
        return const LicenseResult(false, 'صيغة ملف التفعيل غير صحيحة.');
      }
      final payload = decoded['payload'] as Map<String, dynamic>;
      if (payload.keys.toSet().difference(_requiredFields).isNotEmpty ||
          _requiredFields.difference(payload.keys.toSet()).isNotEmpty ||
          payload['product'] != licenseProduct ||
          payload['license_id'] is! String ||
          payload['customer'] is! String ||
          payload['device_id'] is! String ||
          payload['issued_at'] is! String ||
          (payload['expires_at'] != null && payload['expires_at'] is! String)) {
        return const LicenseResult(false, 'محتوى الترخيص غير صالح.');
      }
      final licenseId = payload['license_id'] as String;
      final customer = payload['customer'] as String;
      final fingerprint = payload['device_id'] as String;
      if (!RegExp(r'^[a-zA-Z0-9_-]{8,80}$').hasMatch(licenseId) ||
          customer.trim().isEmpty ||
          customer.length > 180 ||
          !RegExp(r'^[A-F0-9]{64}$').hasMatch(fingerprint)) {
        return const LicenseResult(false, 'بيانات العميل أو الجهاز غير صالحة.');
      }
      // A deterministic UTF-8 JSON byte sequence. Keys are sorted exactly as
      // in the offline issuer; non-ASCII customer names are left as UTF-8.
      final canonical = jsonEncode(SplayTreeMap<String, dynamic>.from(payload));
      final signedBytes = utf8.encode('$licenseDomain$canonical');
      final signatureBytes = base64.decode(decoded['signature'] as String);
      if (signatureBytes.length != 64) {
        return const LicenseResult(false, 'توقيع الترخيص غير صالح.');
      }
      final publicKey = SimplePublicKey(key, type: KeyPairType.ed25519);
      final valid = await Ed25519().verify(
        signedBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
      if (!valid) {
        return const LicenseResult(false, 'تم تعديل ملف التفعيل أو لم يصدر من الناشر.');
      }
      if (fingerprint != deviceId) {
        return const LicenseResult(false, 'ملف التفعيل مرتبط بجهاز آخر.');
      }
      final issuedAt = DateTime.tryParse(payload['issued_at'] as String)?.toUtc();
      final expiryValue = payload['expires_at'] as String?;
      final expiresAt =
          expiryValue == null ? null : DateTime.tryParse(expiryValue)?.toUtc();
      final now = (currentTime ?? DateTime.now()).toUtc();
      if (issuedAt == null ||
          !RegExp(r'Z$').hasMatch(payload['issued_at'] as String) ||
          issuedAt.isAfter(now.add(const Duration(days: 1))) ||
          (expiryValue != null &&
              (expiresAt == null || !expiryValue.endsWith('Z')))) {
        return const LicenseResult(false, 'تواريخ الترخيص غير صحيحة.');
      }
      if (expiresAt != null && !expiresAt.isAfter(now)) {
        return const LicenseResult(false, 'انتهت صلاحية الترخيص، تواصل مع الدعم.');
      }
      return LicenseResult(true, 'تم تفعيل البرنامج لهذا الجهاز.', customer: customer, licenseId: licenseId);
    } on FormatException {
      return const LicenseResult(false, 'ملف التفعيل غير صالح أو تالف.');
    } on Object {
      // Failure closed. Do not log license contents or hardware identifiers.
      return const LicenseResult(false, 'تعذر التحقق من ملف التفعيل.');
    }
  }
}
