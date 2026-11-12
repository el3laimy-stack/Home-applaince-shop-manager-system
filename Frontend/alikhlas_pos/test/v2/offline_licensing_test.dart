import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:alikhlas_pos/v2/licensing/device_identity.dart';
import 'package:alikhlas_pos/v2/licensing/license_gate.dart';
import 'package:alikhlas_pos/v2/licensing/license_service.dart';
import 'package:alikhlas_pos/v2/licensing/license_verifier.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(String, String)> signedLicense({
  required String deviceId,
  String? expiresAt,
}) async {
  final keyPair = await Ed25519().newKeyPair();
  final key = await keyPair.extractPublicKey();
  final payload = <String, dynamic>{
    'product': licenseProduct,
    'license_id': 'LIC-2026-001',
    'customer': 'متجر تجريبي',
    'device_id': deviceId,
    'issued_at': '2026-11-10T00:00:00Z',
    'expires_at': expiresAt,
  };
  final signed = utf8.encode(
    licenseDomain + jsonEncode(SplayTreeMap<String, dynamic>.from(payload)),
  );
  final signature = await Ed25519().sign(signed, keyPair: keyPair);
  return (
    base64.encode(key.bytes),
    jsonEncode({
      'format': licenseFormat,
      'payload': payload,
      'signature': base64.encode(signature.bytes),
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same hardware produces stable opaque fingerprint', () async {
    final first = DeviceIdentity(rawDeviceIdForTesting: () async => 'WIN|UUID');
    final second = DeviceIdentity(rawDeviceIdForTesting: () async => 'win|uuid');
    final fingerprint = await first.fingerprint();
    expect(fingerprint, hasLength(64));
    expect(fingerprint, await second.fingerprint());
    expect(fingerprint, isNot(contains('UUID')));
  });

  test('valid issuer signature permits only the designated computer', () async {
    final (publicKey, doc) = await signedLicense(deviceId: 'A'.padLeft(64, 'A'));
    final verifier = LicenseVerifier(publicKeyBase64: publicKey);
    final now = DateTime.utc(2026, 11, 12);
    expect((await verifier.verify(doc, 'A'.padLeft(64, 'A'), currentTime: now)).valid, true);
    final other = await verifier.verify(doc, 'B'.padLeft(64, 'B'), currentTime: now);
    expect(other.valid, false);
    expect(other.message, contains('آخر'));
  });

  test('tampered document, unknown issuer and missing key fail closed', () async {
    final (publicKey, doc) = await signedLicense(deviceId: 'A'.padLeft(64, 'A'));
    final verifier = LicenseVerifier(publicKeyBase64: publicKey);
    final now = DateTime.utc(2026, 11, 12);
    expect(
      (await verifier.verify(doc.replaceFirst('متجر تجريبي', 'متجر آخر'),
          'A'.padLeft(64, 'A'), currentTime: now)).valid,
      false,
    );
    expect(
      (await const LicenseVerifier(publicKeyBase64: '')
              .verify(doc, 'A'.padLeft(64, 'A'), currentTime: now)).valid,
      false,
    );
    final (anotherKey, _) = await signedLicense(deviceId: 'A'.padLeft(64, 'A'));
    expect(
      (await LicenseVerifier(publicKeyBase64: anotherKey)
          .verify(doc, 'A'.padLeft(64, 'A'), currentTime: now)).valid,
      false,
    );
  });

  test('expired activation is rejected', () async {
    final (publicKey, doc) =
        await signedLicense(deviceId: 'A'.padLeft(64, 'A'), expiresAt: '2026-11-11T00:00:00Z');
    final result = await LicenseVerifier(publicKeyBase64: publicKey)
        .verify(doc, 'A'.padLeft(64, 'A'), currentTime: DateTime.utc(2026, 11, 12));
    expect(result.valid, false);
    expect(result.message, contains('انتهت'));
  });

  test('copying license or SQLite data does not activate another device', () async {
    final dirA = await Directory.systemTemp.createTemp('license-test-a-');
    final dirB = await Directory.systemTemp.createTemp('license-test-b-');
    addTearDown(() async {
      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    });
    final identityA = DeviceIdentity(rawDeviceIdForTesting: () async => 'computer-a');
    final identityB = DeviceIdentity(rawDeviceIdForTesting: () async => 'computer-b');
    final (key, doc) = await signedLicense(deviceId: await identityA.fingerprint());
    final verifier = LicenseVerifier(publicKeyBase64: key);
    final serviceA = LicenseService(
      identity: identityA, verifier: verifier, storageDirectory: () async => dirA,
    );
    final serviceB = LicenseService(
      identity: identityB, verifier: verifier, storageDirectory: () async => dirB,
    );
    expect((await serviceA.check()).result.valid, false);
    expect((await serviceA.importLicense(doc)).valid, true);
    expect((await serviceA.check()).result.valid, true);
    expect((await serviceB.importLicense(doc)).valid, false);
    await File(dirB.path + '/alikhlas.activation.license').writeAsString(doc);
    expect((await serviceB.check()).result.valid, false);
  });

  testWidgets('gate hides shop UI until an authorized license is imported',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('license-ui-');
    addTearDown(() async => dir.delete(recursive: true));
    final identity = DeviceIdentity(rawDeviceIdForTesting: () async => 'computer-a');
    final (key, doc) = await signedLicense(deviceId: await identity.fingerprint());
    final service = LicenseService(
      identity: identity,
      verifier: LicenseVerifier(publicKeyBase64: key),
      storageDirectory: () async => dir,
    );
    await tester.pumpWidget(LicenseGate(
      service: service,
      child: const MaterialApp(home: Scaffold(body: Text('PRIVATE SHOP UI'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE SHOP UI'), findsNothing);
    expect(find.byKey(const ValueKey('license-device-id')), findsOneWidget);
    expect((await service.importLicense(doc)).valid, true);
    await tester.tap(find.byKey(const ValueKey('license-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE SHOP UI'), findsOneWidget);
  });
}
