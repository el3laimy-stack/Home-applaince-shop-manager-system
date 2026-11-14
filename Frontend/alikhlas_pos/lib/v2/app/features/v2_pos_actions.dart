part of '../v2_app.dart';

mixin _PosViewActions on ConsumerState<_PosView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _quantityRaw = <int, String>{};
  final _priceRaw = <int, String>{};
  String? _category;
  bool _selectedOnly = false;
  bool _reviewing = false;
  bool _paying = false;
  int _highlighted = 0;
  _CheckoutPayment _payment = _CheckoutPayment.cash;
  bool _automaticCash = true;
  bool _restoringEditor = false;
  bool _syncingPayment = false;
  late final InvoiceAutosave _workspace;
  late final InvoiceDepartureCoordinator _departureCoordinator;
  late final Future<void> Function() _departureHook = _flushWorkspace;
  void _redraw(VoidCallback action) => setState(action);
  final _cash = TextEditingController();
  final _wallet = TextEditingController();
  final _discount = TextEditingController();
  final _installmentCount = TextEditingController(text: '3');
  final _customPeriodDays = TextEditingController(text: '30');
  final _interest = TextEditingController();
  final _cart = <_CartLine>[];
  late DateTime _firstDueDate = ref
      .read(appClockProvider)()
      .add(const Duration(days: 30));
  int _periodDays = 30;
  int? _customerId;
  bool _saving = false;
  bool _openingShift = false;
  PendingSale? _pendingSale;
  bool _loadingPending = true;
  bool _pendingLoadFailed = false;
  String? _pendingError;
  bool _dirty = false;
  bool _hasSavedDraft = false;
  bool _draftUnreadable = false;
  String? _draftNotice;

  @override
  void initState() {
    super.initState();
    _workspace = InvoiceAutosave(
      ref.read(useCasesProvider),
      'sale',
      onChanged: () {
        if (!mounted) return;
        if (!_workspace.dirty && _workspace.error == null && !_loadingPending) {
          _markClean();
        }
        setState(() {});
      },
    );
    _departureCoordinator = ref.read(invoiceDepartureProvider);
    _departureCoordinator.register('sale', _departureHook);
    for (final controller in [
      _cash,
      _wallet,
      _discount,
      _interest,
      _installmentCount,
      _customPeriodDays,
    ]) {
      controller.addListener(_editorChanged);
    }
    _loadPendingSale();
  }

  Future<void> _loadPendingSale() async {
    setState(() => _loadingPending = true);
    try {
      final useCases = ref.read(useCasesProvider);
      final request = await useCases.pendingSale();
      SaleDraft? draft;
      var draftUnreadable = false;
      if (request == null) {
        try {
          draft = await useCases.saleDraft();
        } catch (_) {
          draftUnreadable = true;
        }
      }
      if (!mounted) return;
      _pendingSale = request;
      _workspace.row = await useCases.activeInvoiceWorkspace('sale');
      if (!mounted) return;
      _restoreWorkspaceState(draft, unreadable: draftUnreadable);
      _pendingLoadFailed = false;
    } catch (_) {
      if (mounted) _pendingLoadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loadingPending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pendingSale == null && !_paying) {
            _searchFocus.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _discardPendingSale() async {
    if (_saving || _pendingSale == null) return;
    setState(() => _saving = true);
    try {
      final removed = await ref
          .read(useCasesProvider)
          .restoreUncommittedPendingSaleAsDraft(_pendingSale!.operationKey);
      if (!mounted) return;
      if (removed) {
        _pendingSale = null;
        _pendingError = null;
        _workspace.reset(
          await ref.read(useCasesProvider).activeInvoiceWorkspace('sale'),
        );
        final draft = await ref.read(useCasesProvider).saleDraft();
        if (!mounted) return;
        _restoreWorkspaceState(draft);
      } else {
        _pendingError =
            'لا يمكن العودة للتعديل؛ قد تكون الفاتورة محفوظة أو توجد مسودة أخرى. استخدم التحقق.';
      }
    } catch (_) {
      if (mounted) _pendingError = 'تعذر إلغاء الطلب. أعد المحاولة.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _departureCoordinator.unregister('sale', _departureHook);
    _workspace.dispose();
    _searchFocus.dispose();
    _search.dispose();
    _cash.dispose();
    _wallet.dispose();
    _discount.dispose();
    _installmentCount.dispose();
    _customPeriodDays.dispose();
    _interest.dispose();
    super.dispose();
  }

  void _addToCart(Product product) {
    if (_draftUnreadable) {
      _showSnack(
        context,
        'ابدأ فاتورة جديدة أو امسح المسودة غير المقروءة أولًا.',
      );
      return;
    }
    _CartLine? existing;
    for (final line in _cart) {
      if (line.product.id == product.id) {
        existing = line;
        break;
      }
    }
    if (product.stockQty <= 0) return;
    if (existing == null && _cart.length >= 500) {
      _showSnack(context, 'الحد الأقصى 500 نوع في الفاتورة الواحدة.');
      return;
    }
    if (existing == null) {
      _cart.add(_CartLine(product));
    } else if (existing.qty < product.stockQty) {
      existing.qty++;
    }
    final line = _cart.where((l) => l.product.id == product.id).first;
    _applyPrice(line);
    _quantityRaw[product.id] = '${line.qty}';
    _syncCash();
    _markDirty();
  }

  Future<void> _submitSale(int total) async {
    final paidPreview =
        BigInt.from(_parseMoney(_cash.text)) +
        BigInt.from(_parseMoney(_wallet.text));
    final netPreview =
        BigInt.from(total) - BigInt.from(_parseMoney(_discount.text));
    if (paidPreview < netPreview && _payment != _CheckoutPayment.installment) {
      _showSnack(context, 'اختار تقسيط للمبلغ المتبقي، أو كمّل المدفوع.');
      return;
    }
    if (_quantityError != null) return;
    if (_saving ||
        _pendingSale != null ||
        _loadingPending ||
        _pendingLoadFailed) {
      return;
    }
    try {
      await _flushWorkspace();
    } catch (_) {
      if (!mounted) return;
      final pending = await ref.read(useCasesProvider).pendingSale();
      if (!mounted) return;
      if (pending != null) {
        await _loadPendingSale();
        if (mounted) {
          setState(
            () => _pendingError =
                'يوجد طلب سابق لم تُحسم نتيجته. تحقق منه قبل بدء طلب جديد.',
          );
        }
      } else {
        _showSnack(context, 'تعذر حفظ المسودة. أعد المحاولة قبل تسجيل البيع.');
      }
      return;
    }
    if (!mounted || _saving || _pendingSale != null) return;
    final cash = _requireMoney(context, _cash, 'كاش');
    final wallet = _requireMoney(context, _wallet, 'محفظة');
    final discount = _requireMoney(context, _discount, 'خصم الفاتورة');
    final interest = _requireMoney(context, _interest, 'فائدة اختيارية');
    if (cash == null ||
        wallet == null ||
        discount == null ||
        interest == null) {
      return;
    }
    final paid = cash + wallet;
    if (discount < 0) {
      _showSnack(context, 'الخصم لا يمكن أن يكون سالبًا');
      return;
    }
    if (discount >= total) {
      _showSnack(context, 'الخصم يجب أن يكون أقل من إجمالي الفاتورة');
      return;
    }
    final netTotal = total - discount;
    if (paid > netTotal) {
      _showSnack(context, 'المدفوع أكبر من إجمالي الفاتورة بعد الخصم');
      return;
    }
    if (cash > 0 && widget.snapshot.dashboard.openShift == null) {
      _showSnack(context, 'افتح وردية قبل البيع النقدي');
      return;
    }
    final remaining = netTotal - paid;
    if (remaining > 0 && _customerId == null) {
      _showSnack(context, 'اختر عميلًا للبيع بالتقسيط');
      return;
    }
    final installmentCount =
        int.tryParse(normalizeArabicDigits(_installmentCount.text.trim())) ?? 0;
    final periodDays = _effectiveInstallmentPeriodDays();
    if (remaining > 0 && installmentCount <= 0) {
      _showSnack(context, 'عدد الأقساط يجب أن يكون أكبر من صفر');
      return;
    }
    if (remaining > 0 && periodDays <= 0) {
      _showSnack(context, 'فترة الأقساط يجب أن تكون أكبر من صفر يوم');
      return;
    }
    final terms = remaining > 0 && _customerId != null
        ? InstallmentTerms(
            partyId: _customerId!,
            count: installmentCount,
            firstDueDate: _firstDueDate,
            interestMinor: interest,
            periodDays: periodDays,
          )
        : null;
    final operationKey = ref.read(useCasesProvider).newSaleOperationKey();
    final customerId = _customerId;
    final items = [
      for (final line in _cart)
        SaleLineInput(
          productId: line.product.id,
          qty: line.qty,
          unitPriceMinor: line.unitPriceMinor,
        ),
    ];
    final payments = [
      PaymentInput(PaymentMethod.cash, cash),
      PaymentInput(PaymentMethod.wallet, wallet),
    ];
    _pendingSale = PendingSale(
      operationKey: operationKey,
      customerId: customerId,
      items: items,
      payments: payments,
      installmentTerms: terms,
      discountMinor: discount,
    );
    await _savePendingSale();
  }

  Future<void> _savePendingSale() async {
    if (_saving || _pendingSale == null) return;
    setState(() => _saving = true);
    try {
      final useCases = ref.read(useCasesProvider);
      final requestedKey = _pendingSale!.operationKey;
      final request = await useCases.stagePendingSale(_pendingSale!);
      if (!mounted) return;
      _pendingSale = request;
      if (request.operationKey != requestedKey) {
        _pendingError =
            'يوجد طلب سابق لم تُحسم نتيجته. راجعه قبل تسجيل بيع جديد.';
        return;
      }
      _hasSavedDraft = false;
      _draftNotice = null;
      _markClean();
      final result = await ref.read(saleWriterProvider)(
        operationKey: request.operationKey,
        customerId: request.customerId,
        items: request.items,
        payments: request.payments,
        installmentTerms: request.installmentTerms,
        discountMinor: request.discountMinor,
      );
      if (!mounted) return;
      if (result is AppFailure<int>) {
        _pendingError = result.message;
      }
      if (result is AppSuccess<int>) {
        _workspace.reset();
        // The committed request remains recoverable until acknowledgement.
        _clearEditor();
        final acknowledged = await useCases.acknowledgePendingSale(
          request.operationKey,
        );
        if (!mounted) return;
        if (!acknowledged) {
          throw StateError('Pending sale acknowledgement failed');
        }
        _pendingSale = null;
        _pendingError = null;
        // The sale has committed. Waiting for its receipt to close is not a
        // pending write, and must not keep the editor's saving animation alive.
        setState(() => _saving = false);
        _refresh(ref);
        try {
          final receipt = await ref.read(saleReceiptLoaderProvider)(
            result.value,
          );
          if (!mounted) return;
          _showSnack(
            context,
            'الفاتورة ${receipt.invoice.invoiceNo} محفوظة بنجاح',
          );
          await showDialog<void>(
            context: context,
            builder: (_) => _SaleReceiptDialog(
              receipt: receipt,
              autoPrint: true,
              reviewedSale: true,
            ),
          );
        } catch (_) {
          if (mounted) {
            _showSnack(
              context,
              'تم حفظ البيع. تعذر عرض الفاتورة؛ افتحها من سجل المرتجعات لإعادة الطباعة.',
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        _pendingError = 'تعذر إكمال التحقق. أعد المحاولة بنفس الطلب.';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSaleShift() async {
    if (_openingShift || _saving) return;
    setState(() => _openingShift = true);
    try {
      final amount = await showDialog<int>(
        context: context,
        builder: (_) => const _ShiftCashDialog(),
      );
      if (amount == null || !mounted) return;
      final uc = ref.read(useCasesProvider);
      final result = await _submitPendingFinancialOperation(
        uc,
        PendingFinancialOperation.openShift(
          operationKey: uc.newShiftOperationKey(),
          openingCashMinor: amount,
        ),
        allowNegativeBalance: false,
      );
      if (!mounted) return;
      _showResult(context, result, success: 'تم فتح الوردية');
      _refresh(ref);
    } catch (_) {
      if (mounted) {
        _showSnack(
          context,
          'تعذر تأكيد نتيجة الوردية. أعد فتح التطبيق للتحقق من الطلب السابق. راجع الفاتورة قبل المتابعة.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingShift = false);
    }
  }

  int _effectiveInstallmentPeriodDays() {
    if (_periodDays > 0) return _periodDays;
    return int.tryParse(normalizeArabicDigits(_customPeriodDays.text.trim())) ??
        0;
  }

  Future<void> _pickFirstDueDate() async {
    final today = ref.read(appClockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDueDate.isBefore(today) ? today : _firstDueDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    _markDirty();
    setState(() => _firstDueDate = picked);
  }

  void _editorChanged() {
    if (_restoringEditor || _loadingPending || _saving || _syncingPayment) {
      return;
    }
    _markDirty();
  }

  void _markDirty() {
    if (_restoringEditor || _loadingPending || _saving || _draftUnreadable) {
      return;
    }
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged(true);
    }
    scheduleMicrotask(() {
      if (mounted &&
          !_restoringEditor &&
          !_loadingPending &&
          !_saving &&
          _pendingSale == null) {
        _workspace.mark(_workspacePayload());
      }
    });
  }

  void _markClean() {
    if (!_dirty) return;
    _dirty = false;
    widget.onDirtyChanged(false);
  }

  void _restoreDraft(SaleDraft draft) {
    _automaticCash = false;
    final draftTotal = draft.items.fold<BigInt>(
      BigInt.zero,
      (sum, item) =>
          sum + BigInt.from(item.qty) * BigInt.from(item.unitPriceMinor),
    );
    final remaining =
        draftTotal -
        BigInt.from(draft.discountMinor) -
        BigInt.from(draft.cashMinor) -
        BigInt.from(draft.walletMinor);
    _payment = draft.interestMinor > 0 || remaining > BigInt.zero
        ? _CheckoutPayment.installment
        : draft.walletMinor > 0
        ? (draft.cashMinor > 0
              ? _CheckoutPayment.mixed
              : _CheckoutPayment.wallet)
        : _CheckoutPayment.cash;
    final products = {
      for (final product in widget.snapshot.products) product.id: product,
    };
    var skipped = 0;
    var changedPrice = false;
    _cart.clear();
    _quantityRaw.clear();
    _priceRaw.clear();
    for (final item in draft.items) {
      final product = products[item.productId];
      if (product == null || !product.isActive) {
        skipped += 1;
        continue;
      }
      if (product.salePriceMinor != item.unitPriceMinor) changedPrice = true;
      _cart.add(
        _CartLine(product, unitPriceMinor: item.unitPriceMinor)..qty = item.qty,
      );
      _quantityRaw[product.id] = '${item.qty}';
    }
    final customerExists =
        draft.customerId == null ||
        widget.snapshot.customers.any(
          (customer) => customer.id == draft.customerId,
        );
    _customerId = customerExists ? draft.customerId : null;
    _cash.text = draft.cashMinor == 0 ? '' : _minorToInputText(draft.cashMinor);
    _wallet.text = draft.walletMinor == 0
        ? ''
        : _minorToInputText(draft.walletMinor);
    _discount.text = draft.discountMinor == 0
        ? ''
        : _minorToInputText(draft.discountMinor);
    _interest.text = draft.interestMinor == 0
        ? ''
        : _minorToInputText(draft.interestMinor);
    _installmentCount.text = draft.installmentCount.toString();
    _firstDueDate = draft.firstDueDate;
    if (const [7, 15, 30].contains(draft.periodDays)) {
      _periodDays = draft.periodDays;
      _customPeriodDays.text = draft.periodDays.toString();
    } else {
      _periodDays = -1;
      _customPeriodDays.text = draft.periodDays.toString();
    }
    _hasSavedDraft = true;
    _dirty = false;
    widget.onDirtyChanged(false);
    final warnings = <String>[
      if (skipped > 0) 'تعذر استعادة $skipped صنف محذوف أو موقوف.',
      if (!customerExists) 'العميل المحفوظ لم يعد متاحًا.',
      if (changedPrice)
        'سعر صنف في المسودة مختلف عن السعر الحالي؛ احتفظنا بسعر المسودة للمراجعة.',
    ];
    _draftNotice = warnings.isEmpty
        ? 'تمت استعادة مسودة البيع المحفوظة.'
        : 'تمت استعادة المسودة. ${warnings.join(' ')}';
  }

  Future<void> _saveDraft() async {
    try {
      await _flushWorkspace();
      if (mounted) _showSnack(context, 'تم حفظ مسودة البيع');
    } catch (_) {
      if (mounted) _showSnack(context, 'تعذر حفظ المسودة. أعد المحاولة.');
    }
  }

  Future<void> _discardDraft() async {
    if (_saving || !_hasSavedDraft) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مسح مسودة البيع؟'),
        content: const Text(
          'ستُمسح المسودة الحالية فقط. لا توجد فاتورة أو حركة مالية مسجلة منها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسح المسودة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _workspace.flush();
      await ref.read(useCasesProvider).discardSaleDraft();
      _workspace.reset();
      if (!mounted) return;
      _clearEditor();
      _showSnack(context, 'تم مسح مسودة البيع');
    } catch (_) {
      if (mounted) _showSnack(context, 'تعذر مسح المسودة. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
