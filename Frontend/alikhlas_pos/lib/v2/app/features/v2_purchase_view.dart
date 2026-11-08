part of '../v2_app.dart';

class _PurchaseView extends ConsumerStatefulWidget {
  const _PurchaseView({required this.snapshot, required this.onDirtyChanged});
  final WorkbenchSnapshot snapshot;
  final ValueChanged<bool> onDirtyChanged;

  @override
  ConsumerState<_PurchaseView> createState() => _PurchaseViewState();
}

class _PurchaseViewState extends ConsumerState<_PurchaseView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _quantityRaw = <int, String>{};
  final _costRaw = <int, String>{};
  String? _category;
  bool _selectedOnly = false;
  int _highlighted = 0;
  bool _reviewing = false;
  bool _paying = false;
  bool _automaticCash = true;
  bool _restoringEditor = false;
  bool _syncingPayment = false;
  late final InvoiceAutosave _workspace;
  late final InvoiceDepartureCoordinator _departureCoordinator;
  late final Future<void> Function() _departureHook = _flushWorkspace;
  void _redraw(VoidCallback action) => setState(action);
  final _cash = TextEditingController();
  final _wallet = TextEditingController();
  final _cart = <_PurchaseCartLine>[];
  int? _supplierId;
  bool _saving = false;
  PendingPurchase? _pendingPurchase;
  bool _recoveringPurchase = false;
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
      'purchase',
      onChanged: () {
        if (!mounted) return;
        if (!_workspace.dirty && _workspace.error == null && !_loadingPending) {
          _markClean();
        }
        setState(() {});
      },
    );
    _departureCoordinator = ref.read(invoiceDepartureProvider);
    _departureCoordinator.register('purchase', _departureHook);
    _cash.addListener(_editorChanged);
    _wallet.addListener(_editorChanged);
    _loadPendingPurchase();
  }

  Future<void> _loadPendingPurchase() async {
    setState(() => _loadingPending = true);
    try {
      final useCases = ref.read(useCasesProvider);
      final request = await useCases.pendingPurchase();
      PurchaseDraft? draft;
      var draftUnreadable = false;
      if (request == null) {
        try {
          draft = await useCases.purchaseDraft();
        } catch (_) {
          draftUnreadable = true;
        }
      }
      if (!mounted) return;
      _pendingPurchase = request;
      _recoveringPurchase = request != null;
      _workspace.row = await useCases.activeInvoiceWorkspace('purchase');
      if (!mounted) return;
      _restoreWorkspaceState(draft, unreadable: draftUnreadable);
      _pendingLoadFailed = false;
    } catch (_) {
      if (mounted) _pendingLoadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loadingPending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pendingPurchase == null && !_paying) {
            _searchFocus.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _discardPendingPurchase() async {
    if (_saving || _pendingPurchase == null) return;
    setState(() => _saving = true);
    try {
      final removed = await ref
          .read(useCasesProvider)
          .restoreUncommittedPendingPurchaseAsDraft(
            _pendingPurchase!.operationKey,
          );
      if (!mounted) return;
      if (removed) {
        _pendingPurchase = null;
        _pendingError = null;
        _workspace.reset(
          await ref.read(useCasesProvider).activeInvoiceWorkspace('purchase'),
        );
        final draft = await ref.read(useCasesProvider).purchaseDraft();
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
    _departureCoordinator.unregister('purchase', _departureHook);
    _workspace.dispose();
    _searchFocus.dispose();
    _search.dispose();
    _cash.dispose();
    _wallet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendingLoadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تعذر قراءة طلب الشراء السابق. لن يبدأ شراء جديد حتى يتم التحقق.',
            ),
            TextButton(
              onPressed: _loadPendingPurchase,
              child: const Text('إعادة محاولة قراءة الطلب'),
            ),
          ],
        ),
      );
    }
    if (_pendingPurchase != null) {
      return _Screen(
        title: 'الشراء',
        subtitle: 'التحقق من نتيجة الحفظ',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يوجد طلب شراء يحتاج استكمال التحقق. إعادة المحاولة تستخدم نفس الطلب.',
              ),
              const SizedBox(height: 12),
              Text('عدد الأصناف: ${_pendingPurchase!.items.length}'),
              if (_pendingError != null) Text(_pendingError!),
              FilledButton(
                onPressed: _saving ? null : _savePendingPurchase,
                child: Text(
                  _saving ? 'جاري التحقق...' : 'التحقق وإعادة المحاولة',
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _discardPendingPurchase,
                child: const Text('العودة لتعديل المسودة'),
              ),
            ],
          ),
        ),
      );
    }
    final selectedIds = _cart.map((l) => l.product.id).toSet();
    final products = _checkoutProducts(
      widget.snapshot.products,
      _search.text,
      _reviewing ? null : _category,
      _reviewing || _selectedOnly,
      selectedIds.contains,
    );
    final preview = _MoneyPreview();
    final total = preview.value(
      _cart.fold<BigInt>(
        BigInt.zero,
        (s, l) => s + BigInt.from(l.qty) * BigInt.from(l.costMinor),
      ),
    );
    final paid = preview.value(
      BigInt.from(_parseMoney(_cash.text)) +
          BigInt.from(_parseMoney(_wallet.text)),
    );
    final remaining = preview.value(BigInt.from(total) - BigInt.from(paid));
    final error =
        _quantityError ??
        preview.error ??
        _firstPurchaseCostError(_cart) ??
        _firstMoneyInputError({'كاش': _cash, 'محفظة': _wallet});
    void next() {
      if (error != null || _cart.isEmpty) return;
      setState(() {
        if (!_reviewing) {
          _reviewing = true;
          _search.clear();
        } else {
          _paying = true;
        }
        _markDirty();
      });
    }

    _searchFocus.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent || products.isEmpty) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(
          () => _highlighted =
              (_highlighted +
                      (event.logicalKey == LogicalKeyboardKey.arrowDown
                          ? 1
                          : -1))
                  .clamp(0, products.length - 1),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () {
          setState(() => _paying = false);
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): next,
      },
      child: AbsorbPointer(
        absorbing: _saving,
        child: _Screen(
          title: _paying
              ? 'مراجعة دفع المشتريات'
              : _reviewing
              ? 'مراجعة أصناف الشراء'
              : 'المشتريات',
          subtitle:
              'اختيار الأصناف والكميات ← مراجعة المورد والدفع ← تسجيل الشراء',
          trailing: FilledButton.icon(
            onPressed: _openQuickProduct,
            icon: const Icon(Icons.add_box),
            label: const Text('منتج جديد'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceToolbar(
                session: _workspace,
                onSuspend: _suspendWorkspace,
                onList: _openWorkspaces,
              ),
              if (_draftNotice != null) Text(_draftNotice!),
              if (_reviewing || _paying)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      if (_paying) {
                        _paying = false;
                      } else {
                        _reviewing = false;
                      }
                    }),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('العودة للأصناف'),
                  ),
                ),
              if (!_paying) ...[
                _CheckoutFilters(
                  all: widget.snapshot.products,
                  search: _search,
                  focus: _searchFocus,
                  category: _category,
                  selectedOnly: _reviewing || _selectedOnly,
                  selectedCount: _cart.length,
                  onChanged: () => setState(() => _highlighted = 0),
                  onCategory: (v) => setState(() => _category = v),
                  onSelectedOnly: (v) => setState(() {
                    _selectedOnly = v;
                    if (!v) _reviewing = false;
                  }),
                  onSubmit: () {
                    if (products.isEmpty) return;
                    final exact = products.where(
                      (p) => p.barcode == _search.text.trim(),
                    );
                    setState(() {
                      _addToCart(
                        exact.firstOrNull ??
                            products[_highlighted.clamp(
                              0,
                              products.length - 1,
                            )],
                      );
                      _highlighted = 0;
                      _search.clear();
                    });
                    _searchFocus.requestFocus();
                  },
                ),
                Expanded(
                  child: _GlassPane(
                    child: _CheckoutCatalog(
                      products: products,
                      highlightedId: products.isEmpty
                          ? null
                          : products[_highlighted.clamp(0, products.length - 1)]
                                .id,
                      quantity: (id) =>
                          _cart
                              .where((l) => l.product.id == id)
                              .firstOrNull
                              ?.qty ??
                          0,
                      quantityText: (id) => _quantityRaw[id] ?? '',
                      onQuantity: _setQuantity,
                      onAdd: (p) => setState(() => _addToCart(p)),
                      unitMinor: (p) =>
                          _cart
                              .where((l) => l.product.id == p.id)
                              .firstOrNull
                              ?.costMinor ??
                          p.avgCostMinor,
                      costText: (p) =>
                          _costRaw[p.id] ?? _minorToInputText(p.avgCostMinor),
                      onCost: _setCost,
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: _GlassPane(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int?>(
                            initialValue: _supplierId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'المورد عند الآجل',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('بدون مورد'),
                              ),
                              for (final p in widget.snapshot.suppliers)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _supplierId = v;
                              _markDirty();
                            }),
                          ),
                          const SizedBox(height: 12),
                          _moneyField(
                            _cash,
                            'كاش',
                            onChanged: (_) {
                              _automaticCash = false;
                              _markDirty();
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          _moneyField(
                            _wallet,
                            'محفظة',
                            onChanged: (_) {
                              _automaticCash = false;
                              _markDirty();
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 12),
                          _AmountRow('الإجمالي', total, strong: true),
                          _AmountRow('المدفوع', paid),
                          _AmountRow('الآجل', math.max(0, remaining)),
                          if (remaining > 0 && _supplierId == null)
                            const Text('اختر موردًا لتسجيل الجزء الآجل'),
                          if (widget.snapshot.dashboard.openShift == null &&
                              _parseMoney(_cash.text) > 0) ...[
                            const Text(
                              'افتح وردية لإتمام الشراء النقدي. أصناف الفاتورة محفوظة.',
                            ),
                            FilledButton.icon(
                              onPressed: () async {
                                final amount = await _askMoney(
                                  context,
                                  title: 'رصيد بداية الوردية',
                                );
                                if (amount == null || !mounted) return;
                                final uc = ref.read(useCasesProvider);
                                final result =
                                    await _submitPendingFinancialOperation(
                                      uc,
                                      PendingFinancialOperation.openShift(
                                        operationKey: uc.newShiftOperationKey(),
                                        openingCashMinor: amount,
                                      ),
                                      allowNegativeBalance: false,
                                    );
                                if (!context.mounted) return;
                                _showResult(
                                  context,
                                  result,
                                  success: 'تم فتح الوردية',
                                );
                                _refresh(ref);
                              },
                              icon: const Icon(Icons.lock_open),
                              label: const Text('فتح وردية والعودة للفاتورة'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (error != null)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              _GlassPane(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_cart.length} نوع · ${_cart.fold<BigInt>(BigInt.zero, (s, l) => s + BigInt.from(l.qty))} قطعة',
                    ),
                    Text(
                      'الإجمالي ${Money(total).format()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    FilledButton.icon(
                      onPressed: _cart.isEmpty || error != null
                          ? null
                          : _paying
                          ? () => _submitPurchase(total)
                          : next,
                      icon: Icon(
                        _paying ? Icons.check_circle : Icons.arrow_back,
                      ),
                      label: Text(
                        _saving
                            ? 'جاري الحفظ…'
                            : _paying
                            ? 'تأكيد تسجيل الشراء'
                            : _reviewing
                            ? 'متابعة الدفع'
                            : 'مراجعة ودفع',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saveDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ مسودة'),
                    ),
                    if (_hasSavedDraft)
                      TextButton(
                        onPressed: _discardDraft,
                        child: const Text('مسح المسودة'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCart(Product product) {
    if (_draftUnreadable) {
      _showSnack(
        context,
        'ابدأ فاتورة جديدة أو امسح المسودة غير المقروءة أولًا.',
      );
      return;
    }
    _PurchaseCartLine? existing;
    for (final line in _cart) {
      if (line.product.id == product.id) {
        existing = line;
        break;
      }
    }
    if (existing == null && _cart.length >= 500) {
      _showSnack(context, 'الحد الأقصى 500 نوع في الفاتورة الواحدة.');
      return;
    }
    if (existing == null) {
      _cart.add(_PurchaseCartLine(product));
    } else {
      existing.qty++;
    }
    final line = _cart.where((l) => l.product.id == product.id).first;
    _quantityRaw[product.id] = '${line.qty}';
    _costRaw[product.id] = line.costInput;
    _syncCash();
    _markDirty();
  }

  Future<void> _openQuickProduct() async {
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => const _ProductDialog(quickPurchase: true),
    );
    if (data == null || !mounted) return;
    final result = await ref
        .read(useCasesProvider)
        .createProduct(
          name: data.name,
          barcode: data.barcode,
          category: data.category,
          imagePath: data.imagePath,
          salePriceMinor: data.salePriceMinor,
          openingQty: 0,
          openingCostMinor: 0,
          minStockQty: data.minStockQty,
        );
    if (!mounted) return;
    _showResult(context, result, success: 'تمت إضافة المنتج للفاتورة');
    if (result case AppSuccess<Product>(value: final product)) {
      _markDirty();
      setState(() {
        _search.clear();
        _addToCart(product);
      });
      _refresh(ref);
    }
  }

  Future<void> _submitPurchase(int total) async {
    if (_saving ||
        _pendingPurchase != null ||
        _loadingPending ||
        _pendingLoadFailed) {
      return;
    }
    try {
      await _flushWorkspace();
    } catch (_) {
      if (!mounted) return;
      final pending = await ref.read(useCasesProvider).pendingPurchase();
      if (!mounted) return;
      if (pending != null) {
        await _loadPendingPurchase();
        if (mounted) {
          setState(
            () => _pendingError =
                'يوجد طلب شراء سابق لم تُحسم نتيجته. تحقق منه قبل بدء طلب جديد.',
          );
        }
      } else {
        _showSnack(context, 'تعذر حفظ المسودة. أعد المحاولة قبل تسجيل الشراء.');
      }
      return;
    }
    if (!mounted || _saving || _pendingPurchase != null) return;
    final cash = _requireMoney(context, _cash, 'كاش');
    final wallet = _requireMoney(context, _wallet, 'محفظة');
    if (cash == null || wallet == null) return;
    final invalidCost = _firstPurchaseCostError(_cart);
    if (invalidCost != null) {
      _showSnack(context, invalidCost);
      return;
    }
    final operationKey = ref.read(useCasesProvider).newPurchaseOperationKey();
    final supplierId = _supplierId;
    final items = [
      for (final line in _cart)
        PurchaseLineInput(
          productId: line.product.id,
          qty: line.qty,
          unitCostMinor: line.costMinor,
        ),
    ];
    final payments = [
      PaymentInput(PaymentMethod.cash, cash),
      PaymentInput(PaymentMethod.wallet, wallet),
    ];
    _recoveringPurchase = false;
    _pendingError = null;
    _pendingPurchase = PendingPurchase(
      operationKey: operationKey,
      supplierId: supplierId,
      items: items,
      payments: payments,
    );
    await _savePendingPurchase();
  }

  Future<void> _savePendingPurchase() async {
    if (_saving || _pendingPurchase == null) return;
    setState(() => _saving = true);
    try {
      final useCases = ref.read(useCasesProvider);
      final requestedKey = _pendingPurchase!.operationKey;
      final request = await useCases.stagePendingPurchase(_pendingPurchase!);
      if (!mounted) return;
      _pendingPurchase = request;
      if (request.operationKey != requestedKey) {
        _recoveringPurchase = true;
        _pendingError = 'يوجد طلب شراء سابق لم تُحسم نتيجته. راجعه أولًا.';
        return;
      }
      _hasSavedDraft = false;
      _draftNotice = null;
      _markClean();
      final result = await _runWithNegativeBalanceApproval(
        context,
        action: (allowNegativeBalance) => ref.read(purchaseWriterProvider)(
          operationKey: request.operationKey,
          supplierId: request.supplierId,
          items: request.items,
          payments: request.payments,
          allowNegativeBalance: allowNegativeBalance,
        ),
      );
      if (!mounted) return;
      if (result is AppFailure<int>) {
        _pendingError = result.message;
        if (!_recoveringPurchase) {
          final removed = await useCases
              .restoreUncommittedPendingPurchaseAsDraft(request.operationKey);
          if (!mounted) return;
          if (removed) {
            _pendingPurchase = null;
            _workspace.reset(await useCases.activeInvoiceWorkspace('purchase'));
            _dirty = true;
            widget.onDirtyChanged(true);
            _workspace.mark(_workspacePayload());
          }
        }
        if (!mounted) return;
        _showResult(context, result, success: 'تم تسجيل الشراء');
      }
      if (result is AppSuccess<int>) {
        _workspace.reset();
        _clearEditor();
        final acknowledged = await useCases.acknowledgePendingPurchase(
          request.operationKey,
        );
        if (!mounted) return;
        if (!acknowledged) {
          throw StateError('Purchase acknowledgement failed');
        }
        _pendingPurchase = null;
        _pendingError = null;
        final labels = _barcodeItemsFromPurchaseRequest(request);
        _refresh(ref);
        _showSnack(context, 'تم تسجيل الشراء');
        try {
          await _promptBarcodePrinting(labels);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            _showSnack(
              context,
              'تم حفظ الشراء. تعذرت طباعة الباركود؛ يمكنك إعادة طباعته من المخزون.',
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        _pendingError = 'تعذر إكمال التحقق من الشراء. أعد المحاولة بنفس الطلب.';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<BarcodeLabelItem> _barcodeItemsFromPurchaseRequest(
    PendingPurchase request,
  ) => [
    for (final item in request.items)
      for (final product in widget.snapshot.products.where(
        (product) => product.id == item.productId,
      ))
        BarcodeLabelItem(
          productName: product.name,
          barcode: product.barcode,
          quantity: item.qty,
        ),
  ];

  Future<void> _promptBarcodePrinting(List<BarcodeLabelItem> items) async {
    final printable = BarcodeLabelsPdf.printableItems(items);
    if (printable.isEmpty && items.isEmpty) return;
    final labels = await showDialog<List<BarcodeLabelItem>>(
      context: context,
      builder: (_) => _BarcodePrintPromptDialog(items: items),
    );
    if (labels == null || labels.isEmpty || !mounted) return;
    await ref.read(barcodeLabelPrinterProvider)(
      labels,
      widget.snapshot.barcodeLabelSettings,
    );
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
          _pendingPurchase == null) {
        _workspace.mark(_workspacePayload());
      }
    });
  }

  void _markClean() {
    if (!_dirty) return;
    _dirty = false;
    widget.onDirtyChanged(false);
  }

  void _restoreDraft(PurchaseDraft draft) {
    _automaticCash = false;
    _quantityRaw.clear();
    _costRaw.clear();
    final products = {
      for (final product in widget.snapshot.products) product.id: product,
    };
    var skipped = 0;
    _cart.clear();
    for (final item in draft.items) {
      final product = products[item.productId];
      if (product == null || !product.isActive) {
        skipped += 1;
        continue;
      }
      _quantityRaw[product.id] = '${item.qty}';
      _costRaw[product.id] = _minorToInputText(item.unitCostMinor);
      _cart.add(
        _PurchaseCartLine(
          product,
          quantity: item.qty,
          unitCostMinor: item.unitCostMinor,
        ),
      );
    }
    final supplierExists =
        draft.supplierId == null ||
        widget.snapshot.suppliers.any(
          (supplier) => supplier.id == draft.supplierId,
        );
    _supplierId = supplierExists ? draft.supplierId : null;
    _cash.text = draft.cashMinor == 0 ? '' : _minorToInputText(draft.cashMinor);
    _wallet.text = draft.walletMinor == 0
        ? ''
        : _minorToInputText(draft.walletMinor);
    _hasSavedDraft = true;
    _dirty = false;
    widget.onDirtyChanged(false);
    final warnings = <String>[
      if (skipped > 0) 'تعذر استعادة $skipped صنف محذوف أو موقوف.',
      if (!supplierExists) 'المورد المحفوظ لم يعد متاحًا.',
    ];
    _draftNotice = warnings.isEmpty
        ? 'تمت استعادة مسودة الشراء المحفوظة.'
        : 'تمت استعادة المسودة. ${warnings.join(' ')}';
  }

  Future<void> _saveDraft() async {
    try {
      await _flushWorkspace();
      if (mounted) _showSnack(context, 'تم حفظ مسودة الشراء');
    } catch (_) {
      if (mounted) _showSnack(context, 'تعذر حفظ المسودة. أعد المحاولة.');
    }
  }

  Future<void> _discardDraft() async {
    if (_saving || !_hasSavedDraft) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مسح مسودة الشراء؟'),
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
      await ref.read(useCasesProvider).discardPurchaseDraft();
      _workspace.reset();
      if (!mounted) return;
      _clearEditor();
      _showSnack(context, 'تم مسح مسودة الشراء');
    } catch (_) {
      if (mounted) _showSnack(context, 'تعذر مسح المسودة. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
