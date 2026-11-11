import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'license_service.dart';

/// The production entry point wraps the complete app in this gate.
/// Other app widgets remain independently testable with mocked providers.
class LicenseGate extends StatefulWidget {
  const LicenseGate({required this.child, this.service, super.key});
  final Widget child;
  final LicenseService? service;

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  late final LicenseService _service = widget.service ?? LicenseService();
  bool _checking = true;
  bool _importing = false;
  bool _authorized = false;
  String _deviceId = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _checking = true);
    try {
      final status = await _service.check();
      if (!mounted) return;
      setState(() {
        _deviceId = status.deviceId;
        _authorized = status.result.valid;
        _message = status.result.message;
        _checking = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _message = 'تعذر تحديد هوية الجهاز. تواصل مع الدعم الفني.';
        _checking = false;
      });
    }
  }

  Future<void> _importLicense() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['license', 'json'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final selected = selection.files.single;
      final content = selected.bytes != null
          ? utf8.decode(selected.bytes!)
          : await File(selected.path!).readAsString();
      if (content.length > 32768) {
        throw const FormatException('الملف أكبر من الحجم المسموح به.');
      }
      final result = await _service.importLicense(content);
      if (!mounted) return;
      setState(() => _message = result.message);
      if (result.valid) await _reload();
    } on Object {
      if (!mounted) return;
      setState(() => _message = 'تعذر فتح ملف التفعيل. تأكد من اختيار ملف صادر من الدعم.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_authorized) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 590),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'تفعيل ALIkhlas POS',
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'كل جهاز يحتاج ملف ترخيص مستقلًا. أرسل رمز الجهاز إلى الدعم، ثم استورد ملف التفعيل الذي يصلك عبر واتساب أو البريد الإلكتروني.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        const Text('رمز هذا الجهاز', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_checking)
                          const Center(child: CircularProgressIndicator())
                        else
                          SelectableText(
                            _deviceId.isEmpty ? 'غير متاح' : _deviceId,
                            key: const ValueKey('license-device-id'),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _deviceId.isEmpty
                              ? null
                              : () => Clipboard.setData(ClipboardData(text: _deviceId)),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('نسخ رمز الجهاز'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _message,
                          key: const ValueKey('license-status-message'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const ValueKey('license-import'),
                          onPressed: _checking || _importing ? null : _importLicense,
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(_importing ? 'جارٍ التحقق...' : 'استيراد ملف التفعيل'),
                        ),
                        TextButton(
                          key: const ValueKey('license-refresh'),
                          onPressed: _checking ? null : _reload,
                          child: const Text('إعادة فحص الترخيص'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'لا يُحذف أي صنف أو فاتورة أو نسخة احتياطية عند تعذر التفعيل.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
