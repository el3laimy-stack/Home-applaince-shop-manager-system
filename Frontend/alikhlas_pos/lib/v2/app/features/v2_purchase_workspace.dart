part of '../v2_app.dart';

extension _PurchaseWorkspaceSupport on _PurchaseViewState {
  String? get _quantityError {
    if (_draftUnreadable) {
      return 'المسودة غير مقروءة. يمكنك تصديرها من الفواتير المعلقة، أو بدء فاتورة جديدة.';
    }
    for (final raw in _quantityRaw.values) {
      final qty = int.tryParse(normalizeArabicDigits(raw.trim()));
      if (qty == null || qty < 0) {
        return 'راجع كميات الشراء: استخدم عددًا صحيحًا أو صفرًا لإزالة الصنف.';
      }
    }
    return null;
  }

  void _setQuantity(Product product, String raw) {
    if (_draftUnreadable) return;
    if (_cart.length >= 500 &&
        !_cart.any((l) => l.product.id == product.id) &&
        (int.tryParse(normalizeArabicDigits(raw.trim())) ?? 0) > 0) {
      _showSnack(context, 'الحد الأقصى 500 نوع في الفاتورة الواحدة.');
      return;
    }
    _redraw(() {
      _quantityRaw[product.id] = raw;
      final qty = int.tryParse(normalizeArabicDigits(raw.trim()));
      if (qty == 0) {
        _cart.removeWhere((l) => l.product.id == product.id);
      } else if (qty != null && qty > 0) {
        var line = _cart.where((l) => l.product.id == product.id).firstOrNull;
        if (line == null) {
          line = _PurchaseCartLine(product, quantity: qty);
          _cart.add(line);
          _costRaw.putIfAbsent(product.id, () => line!.costInput);
        }
        line.qty = qty;
        final cost = _costRaw[product.id];
        if (cost != null) {
          line.costInput = cost;
          final parsed = parseMoneyInput(cost);
          if (parsed.isValid) line.costMinor = parsed.minorUnits;
        }
      }
      _syncCash();
      _markDirty();
    });
  }

  void _setCost(Product product, String raw) {
    if (_draftUnreadable) return;
    _redraw(() {
      _costRaw[product.id] = raw;
      final line = _cart.where((l) => l.product.id == product.id).firstOrNull;
      if (line != null) {
        line.costInput = raw;
        final parsed = parseMoneyInput(raw);
        if (parsed.isValid && parsed.minorUnits >= 0) {
          line.costMinor = parsed.minorUnits;
        }
      }
      _syncCash();
      _markDirty();
    });
  }

  void _syncCash() {
    if (!_automaticCash) return;
    final total = _cart.fold<BigInt>(
      BigInt.zero,
      (s, l) => s + BigInt.from(l.qty) * BigInt.from(l.costMinor),
    );
    if (total < BigInt.zero || total > maxMoneyMinor) return;
    _syncingPayment = true;
    _cash.text = total == BigInt.zero ? '' : _minorToInputText(total.toInt());
    _wallet.clear();
    _syncingPayment = false;
  }

  String _workspacePayload() {
    final base = _cart.isEmpty
        ? null
        : PurchaseDraft(
            supplierId: _supplierId,
            items: [
              for (final l in _cart)
                PurchaseLineInput(
                  productId: l.product.id,
                  qty: l.qty,
                  unitCostMinor: math.max(0, l.costMinor),
                ),
            ],
            cashMinor: math.max(0, _parseMoney(_cash.text)),
            walletMinor: math.max(0, _parseMoney(_wallet.text)),
            savedAt: ref.read(appClockProvider)(),
          );
    return jsonEncode({
      'version': 2,
      'draft': base == null ? null : jsonDecode(base.encode()),
      'editor': {
        'cash': _cash.text,
        'wallet': _wallet.text,
        'automaticCash': _automaticCash,
        'reviewing': _reviewing,
        'paying': _paying,
        'quantities': {
          for (final e in _quantityRaw.entries) '${e.key}': e.value,
        },
        'costs': {for (final e in _costRaw.entries) '${e.key}': e.value},
      },
    });
  }

  void _restoreWorkspaceState(PurchaseDraft? draft, {bool unreadable = false}) {
    _restoringEditor = true;
    try {
      if (draft != null) _restoreDraft(draft);
      if (_workspace.row != null && !unreadable) {
        try {
          _restoreEditor(_workspace.row!.payload);
        } catch (_) {
          unreadable = true;
        }
      }
    } finally {
      _restoringEditor = false;
    }
    _draftUnreadable = unreadable;
    if (unreadable) {
      _hasSavedDraft = true;
      _draftNotice =
          'تعذر قراءة مسودة الشراء. لم تُسجل منها حركة مالية؛ يمكنك مسحها وبدء فاتورة جديدة.';
    }
  }

  void _restoreEditor(String payload) {
    final editor = decodeWorkspace(payload)['editor'];
    if (editor is! Map) return;
    _cash.text = editor['cash'] as String? ?? '';
    _wallet.text = editor['wallet'] as String? ?? '';
    _automaticCash = editor['automaticCash'] == true;
    _reviewing = editor['reviewing'] == true;
    _paying = editor['paying'] == true;
    final quantities = editor['quantities'];
    final costs = editor['costs'];
    if (quantities is Map) {
      _quantityRaw.clear();
      for (final e in quantities.entries) {
        final id = int.parse(e.key as String);
        if (widget.snapshot.products.any((p) => p.id == id && p.isActive)) {
          _quantityRaw[id] = e.value as String;
        }
      }
    }
    if (costs is Map) {
      _costRaw.clear();
      for (final e in costs.entries) {
        _costRaw[int.parse(e.key as String)] = e.value as String;
      }
    }
    for (final l in _cart) {
      if (_costRaw[l.product.id] != null) l.costInput = _costRaw[l.product.id]!;
    }
  }

  Future<void> _flushWorkspace() async {
    if (_draftUnreadable) return;
    if (_pendingPurchase != null || _loadingPending || _saving) return;
    if (_dirty) _workspace.mark(_workspacePayload());
    await _workspace.flush();
    _hasSavedDraft = _workspace.row != null;
    _markClean();
  }

  Future<void> _suspendWorkspace() async {
    try {
      await _flushWorkspace();
      if (_workspace.row != null) {
        await ref
            .read(useCasesProvider)
            .suspendInvoiceWorkspace(_workspace.row!.id);
      }
      _workspace.reset();
      _clearEditor();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        _showSnack(context, 'تعذر حفظ الفاتورة. أعد المحاولة قبل بدء أخرى.');
      }
    }
  }

  Future<void> _openWorkspaces() async {
    try {
      await _flushWorkspace();
      if (!mounted) return;
      final uc = ref.read(useCasesProvider);
      final selected = await _chooseWorkspace(context, uc, 'purchase');
      if (!mounted) return;
      if (selected != null) await uc.resumeInvoiceWorkspace(selected.id);
      final active = await uc.activeInvoiceWorkspace('purchase');
      _workspace.reset(active);
      _clearEditor();
      if (active != null) await _loadPendingPurchase();
    } catch (_) {
      if (mounted) {
        _showSnack(context, 'تعذر فتح المسودة. تحقق من طلب الحفظ السابق.');
      }
    }
  }

  void _clearEditor() {
    if (!mounted) return;
    _restoringEditor = true;
    _redraw(() {
      _cart.clear();
      _search.clear();
      _category = null;
      _selectedOnly = false;
      _highlighted = 0;
      _quantityRaw.clear();
      _costRaw.clear();
      _cash.clear();
      _wallet.clear();
      _supplierId = null;
      _reviewing = false;
      _paying = false;
      _automaticCash = true;
      _hasSavedDraft = false;
      _draftUnreadable = false;
      _draftNotice = null;
    });
    _markClean();
    _restoringEditor = false;
    _searchFocus.requestFocus();
  }
}
