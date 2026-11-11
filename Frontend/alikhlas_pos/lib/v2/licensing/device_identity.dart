import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Returns an opaque device identifier. Never uploads hardware identifiers.
///
/// This is copy resistance, not a defense against patched binaries or cloned
/// virtual machines. A hardware/OS reinstall may require license re-issuance.
class DeviceIdentity {
  const DeviceIdentity({this.rawDeviceIdForTesting});

  final Future<String> Function()? rawDeviceIdForTesting;

  Future<String> fingerprint() async {
    final raw = (await (rawDeviceIdForTesting?.call() ?? _platformId()))
        .trim()
        .toLowerCase();
    if (raw.isEmpty || raw.replaceAll(RegExp(r'[0\-| ]'), '').isEmpty) {
      throw const DeviceIdentityException('تعذر قراءة بصمة هذا الجهاز.');
    }
    return sha256
        .convert(utf8.encode('ALIKHLAS-POS-DEVICE-V1\n$raw'))
        .toString()
        .toUpperCase();
  }

  Future<String> _platformId() async {
    if (Platform.isWindows) {
      // Both values are machine-specific; neither MAC nor disk drive letter is
      // used, so changing the printer/network card does not revoke a license.
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference='Stop'; "
            r"$g=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid; "
            r"$u=(Get-CimInstance Win32_ComputerSystemProduct).UUID; "
            r"Write-Output ($g+'|'+$u)",
      ]).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) {
        throw const DeviceIdentityException('تعذر قراءة معرف Windows.');
      }
      final id = (result.stdout as String).trim();
      final parts = id.split('|');
      if (parts.length != 2 ||
          parts.any((x) => x.trim().isEmpty) ||
          parts[1].toLowerCase() == 'ffffffff-ffff-ffff-ffff-ffffffffffff') {
        throw const DeviceIdentityException('معرف الجهاز غير صالح.');
      }
      return 'windows:$id';
    }
    if (Platform.isLinux) {
      for (final path in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        final file = File(path);
        if (await file.exists()) {
          final id = (await file.readAsString()).trim();
          if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(id) &&
              !RegExp(r'^0+$').hasMatch(id)) {
            return 'linux:$id';
          }
        }
      }
      throw const DeviceIdentityException('تعذر قراءة معرف Linux.');
    }
    throw const DeviceIdentityException('الترخيص متاح لأجهزة Windows وLinux فقط.');
  }
}

class DeviceIdentityException implements Exception {
  const DeviceIdentityException(this.message);
  final String message;

  @override
  String toString() => message;
}
