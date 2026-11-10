part of '../v2_app.dart';

extension _PosWorkspaceSupport on _PosViewActions {
  String? get _quantityError {
    if (_draftUnreadable) {
      return 'المسودة غير مقروءة. يمكنك تصديرها من الفواتير المعلقة، أو بدء فاتورة جديدة.';
    }
    for (final entry in _quantityRaw.entries) {
      final value = int.tryParse(normalizeArabicDigits(entry.value.trim()));
      final matches = widget.snapshot.products.where((p) => p.id == entry.key);
      if (value == null || value < 0) {
        return 'راجع الكميات: أدخل عددًا صحيحًا أو صفرًا لإزالة الصنف.';
      }
      if (value > 0 &&
          (matches.isEmpty ||
              !matches.first.isActive ||
              value > matches.first.stockQty)) {
        return 'كمية صنف تتجاوز المخزون المتاح. راجع الكمية قبل المتابعة.';
      }
    }
    for (final line in _cart) {
      final raw = _priceRaw[line.product.id];
      if (raw == null) continue;
      final parsed = parseMoneyInput(raw);
      if (!parsed.isValid || raw.trim().isEmpty || parsed.minorUnits < 0) {
        return 'راجع سعر الصنف: أدخل سعرًا صحيحًا غير سالب.';
      }
    }
    return null;
  }

  void _applyPrice(_CartLine line) {
    final raw = _priceRaw[line.product.id];
    if (raw == null) return;
    final parsed = parseMoneyInput(raw);
    if (parsed.isValid && raw.trim().isNotEmpty && parsed.minorUnits >= 0) {
      line.unitPriceMinor = parsed.minorUnits;
    }
  }

  void _setPrice(Product product, String raw) {
    if (_draftUnreadable) return;
    _redraw(() {
      _priceRaw[product.id] = raw;
      final line = _cart.where((l) => l.product.id == product.id).firstOrNull;
      if (line != null) _applyPrice(line);
      _syncCash();
      _markDirty();
    });
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
      final value = int.tryParse(normalizeArabicDigits(raw.trim()));
      if (value == 0) {
        _cart.removeWhere((l) => l.product.id == product.id);
      } else if (value != null && value > 0) {
        final rows = _cart.where((l) => l.product.id == product.id);
        if (rows.isEmpty) {
          _cart.add(_CartLine(product)..qty = value);
        } else {
          rows.first.qty = value;
        }
        _applyPrice(_cart.firstWhere((l) => l.product.id == product.id));
      }
      _syncCash();
      _markDirty();
    });
  }

  void _syncCash() {
    if (!_automaticCash || _payment != _CheckoutPayment.cash) return;
    final total = _cart.fold<BigInt>(
      BigInt.zero,
      (s, l) => s + BigInt.from(l.qty) * BigInt.from(l.unitPriceMinor),
    );
    final net = total - BigInt.from(_parseMoney(_discount.text));
    if (net < BigInt.zero || net > maxMoneyMinor) return;
    _syncingPayment = true;
    _cash.text = net == BigInt.zero ? '' : _minorToInputText(net.toInt());
    _wallet.clear();
    _syncingPayment = false;
  }

  String _workspacePayload() {
    SaleDraft? base;
    if (_cart.isNotEmpty) {
      base = SaleDraft(
        customerId: _customerId,
        items: [
          for (final l in _cart)
            SaleLineInput(
              productId: l.product.id,
              qty: l.qty,
              unitPriceMinor: l.unitPriceMinor,
            ),
        ],
        cashMinor: math.max(0, _parseMoney(_cash.text)),
        walletMinor: math.max(0, _parseMoney(_wallet.text)),
        discountMinor: math.max(0, _parseMoney(_discount.text)),
        interestMinor: math.max(0, _parseMoney(_interest.text)),
        installmentCount: math.max(
          1,
          int.tryParse(normalizeArabicDigits(_installmentCount.text)) ?? 1,
        ),
        firstDueDate: _firstDueDate,
        periodDays: math.max(1, _effectiveInstallmentPeriodDays()),
        savedAt: ref.read(appClockProvider)(),
      );
    }
    return jsonEncode({
      'version': 2,
      'draft': base == null ? null : jsonDecode(base.encode()),
      'editor': {
        'cash': _cash.text,
        'wallet': _wallet.text,
        'discount': _discount.text,
        'interest': _interest.text,
        'count': _installmentCount.text,
        'customPeriod': _customPeriodDays.text,
        'payment': _payment.name,
        'automaticCash': _automaticCash,
        'reviewing': _reviewing,
        'paying': _paying,
        'prices': {for (final e in _priceRaw.entries) '${e.key}': e.value},
        'quantities': {
          for (final e in _quantityRaw.entries) '${e.key}': e.value,
        },
      },
    });
  }

  void _restoreWorkspaceState(SaleDraft? draft, {bool unreadable = false}) {
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
          'تعذر قراءة مسودة البيع. لم تُسجل منها حركة مالية؛ يمكنك مسحها وبدء فاتورة جديدة.';
    }
    // Show restoration warnings before continuing to review or payment.
    if (_draftNotice != null &&
        _draftNotice != 'تمت استعادة مسودة البيع المحفوظة.') {
      _reviewing = false;
      _paying = false;
    }
  }

  void _restoreEditor(String payload) {
    final data = decodeWorkspace(payload);
    final editor = data['editor'];
    if (editor is! Map) return;
    _cash.text = editor['cash'] as String? ?? '';
    _wallet.text = editor['wallet'] as String? ?? '';
    _discount.text = editor['discount'] as String? ?? '';
    _interest.text = editor['interest'] as String? ?? '';
    _installmentCount.text = editor['count'] as String? ?? '3';
    _customPeriodDays.text = editor['customPeriod'] as String? ?? '30';
    _payment = _CheckoutPayment.values.byName(
      editor['payment'] as String? ?? 'cash',
    );
    _automaticCash = editor['automaticCash'] == true;
    _reviewing = editor['reviewing'] == true;
    _paying = editor['paying'] == true;
    _priceRaw.clear();
    final prices = editor['prices'];
    if (prices is Map) {
      for (final e in prices.entries) {
        final id = int.parse(e.key as String);
        if (widget.snapshot.products.any((p) => p.id == id && p.isActive)) {
          _priceRaw[id] = e.value as String;
        }
      }
    }
    final quantities = editor['quantities'];
    if (quantities is Map) {
      _quantityRaw.clear();
      for (final e in quantities.entries) {
        final id = int.parse(e.key as String);
        if (widget.snapshot.products.any((p) => p.id == id && p.isActive)) {
          _quantityRaw[id] = e.value as String;
        }
      }
    }
  }

  Future<void> _flushWorkspace() async {
    if (_draftUnreadable) return;
    if (_pendingSale != null || _loadingPending || _saving) return;
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
        _showSnack(
          context,
          'تعذر حفظ الفاتورة؛ أعد المحاولة قبل بدء فاتورة أخرى.',
        );
      }
    }
  }

  Future<void> _openWorkspaces() async {
    try {
      await _flushWorkspace();
      if (!mounted) return;
      final uc = ref.read(useCasesProvider);
      final selected = await _chooseWorkspace(context, uc, 'sale');
      if (!mounted) return;
      if (selected != null) await uc.resumeInvoiceWorkspace(selected.id);
      final active = await uc.activeInvoiceWorkspace('sale');
      _workspace.reset(active);
      _clearEditor();
      if (active != null) await _loadPendingSale();
    } catch (_) {
      if (mounted) {
        _showSnack(
          context,
          'تعذر فتح المسودة. تحقق من طلب الحفظ السابق وأعد المحاولة.',
        );
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
      _priceRaw.clear();
      for (final c in [_cash, _wallet, _discount, _interest]) {
        c.clear();
      }
      _customerId = null;
      _reviewing = false;
      _paying = false;
      _payment = _CheckoutPayment.cash;
      _automaticCash = true;
      _installmentCount.text = '3';
      _customPeriodDays.text = '30';
      _periodDays = 30;
      _firstDueDate = ref
          .read(appClockProvider)()
          .add(const Duration(days: 30));
      _hasSavedDraft = false;
      _draftUnreadable = false;
      _draftNotice = null;
    });
    _markClean();
    _restoringEditor = false;
    _searchFocus.requestFocus();
  }
}
