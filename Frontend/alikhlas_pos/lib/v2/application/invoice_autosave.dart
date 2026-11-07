import 'dart:async';

import '../data/app_database.dart';
import 'v2_use_cases.dart';

/// One ordered writer per open editor. Switching editors must await [flush].
class InvoiceAutosave {
  InvoiceAutosave(this.useCases, this.kind, {required this.onChanged});

  final V2UseCases useCases;
  final String kind;
  final void Function() onChanged;
  CheckoutDraft? row;
  Object? error;
  Timer? _timer;
  Future<void>? _running;
  String? _pending;
  String? _label;
  bool _disposed = false;

  bool get dirty => _pending != null || _running != null;
  bool get saving => _running != null;

  void mark(String payload, {String? label}) {
    if (_disposed) return;
    _pending = payload;
    _label = label;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      unawaited(flush().catchError((Object _) {}));
    });
    onChanged();
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_disposed) return Future.error(StateError('Editor closed'));
    if (_running != null) return _running!;
    final task = _drain();
    _running = task;
    // Keep the cleanup in the returned future, including failure paths.
    return _running = task.whenComplete(() {
      _running = null;
      if (!_disposed) onChanged();
    });
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final payload = _pending!;
      final label = _label;
      _pending = null;
      try {
        row = await useCases.saveInvoiceWorkspace(
          kind: kind,
          id: row?.id,
          expectedRevision: row?.revision,
          payload: payload,
          label: label,
        );
        error = null;
      } catch (failure) {
        // Do not replace a newer edit with the snapshot whose write failed.
        _pending ??= payload;
        error = failure;
        rethrow;
      }
    }
  }

  /// Only call after a flushed suspend/delete or a staged durable submission.
  void reset([CheckoutDraft? next]) {
    if (saving) throw StateError('Wait for autosave before switching editors');
    _timer?.cancel();
    _pending = null;
    row = next;
    error = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// Registered by the mounted editor; all navigation/close paths share it.
class InvoiceDepartureCoordinator {
  final _handlers = <String, Future<void> Function()>{};
  void register(String kind, Future<void> Function() handler) =>
      _handlers[kind] = handler;
  void unregister(String kind, Future<void> Function() handler) {
    if (_handlers[kind] == handler) _handlers.remove(kind);
  }

  Future<bool> flush(String kind) async {
    final handler = _handlers[kind];
    if (handler == null) return false;
    await handler();
    return true;
  }
}
