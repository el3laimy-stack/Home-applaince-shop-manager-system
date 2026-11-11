part of '../v2_app.dart';

class _PosView extends ConsumerStatefulWidget {
  const _PosView({required this.snapshot, required this.onDirtyChanged});
  final WorkbenchSnapshot snapshot;
  final ValueChanged<bool> onDirtyChanged;

  @override
  ConsumerState<_PosView> createState() => _PosViewState();
}

class _PosViewState extends ConsumerState<_PosView> with _PosViewActions {
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
              'تعذر قراءة طلب البيع السابق. لن يُبدأ بيع جديد حتى يتم التحقق.',
            ),
            TextButton(
              onPressed: _loadPendingSale,
              child: const Text('إعادة محاولة قراءة الطلب'),
            ),
          ],
        ),
      );
    }
    if (_pendingSale != null) {
      return _SaleFrame(
        title: 'التحقق من نتيجة حفظ البيع',
        stage: 2,
        child: SingleChildScrollView(
          child: _GlassPane(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'يوجد طلب بيع يحتاج استكمال التحقق. إعادة المحاولة تستخدم نفس الطلب.',
                ),
                const SizedBox(height: 12),
                Text('عدد الأصناف: ${_pendingSale!.items.length}'),
                if (_pendingError != null) _AuthNotice(message: _pendingError!),
                FilledButton(
                  onPressed: _saving ? null : _savePendingSale,
                  child: Text(
                    _saving ? 'جاري التحقق...' : 'التحقق وإعادة المحاولة',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _discardPendingSale,
                  child: const Text('العودة لتعديل المسودة'),
                ),
              ],
            ),
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
        (sum, l) => sum + BigInt.from(l.qty) * BigInt.from(l.unitPriceMinor),
      ),
    );
    final discount = _parseMoney(_discount.text);
    final paid = preview.value(
      BigInt.from(_parseMoney(_cash.text)) +
          BigInt.from(_parseMoney(_wallet.text)),
    );
    final net = preview.value(BigInt.from(total) - BigInt.from(discount));
    final remaining = preview.value(BigInt.from(net) - BigInt.from(paid));
    final count =
        int.tryParse(normalizeArabicDigits(_installmentCount.text)) ?? 0;
    final withInterest = preview.value(
      BigInt.from(remaining) +
          (remaining > 0
              ? BigInt.from(_parseMoney(_interest.text))
              : BigInt.zero),
    );
    final installment = count > 0 && withInterest > 0
        ? allocateRemainderToLast(withInterest, count, 0)
        : 0;
    final amountDue = preview.value(
      BigInt.from(net) +
          (remaining > 0
              ? BigInt.from(_parseMoney(_interest.text))
              : BigInt.zero),
    );
    final moneyError =
        preview.error ??
        _firstMoneyInputError({
          'كاش': _cash,
          'محفظة': _wallet,
          'خصم الفاتورة': _discount,
          'فائدة اختيارية': _interest,
        });
    final paymentIssue =
        _paying && remaining > 0 && _payment != _CheckoutPayment.installment
        ? 'فيه مبلغ متبقي. اختار «تقسيط» وحدد العميل والمواعيد، أو كمّل المبلغ المدفوع.'
        : null;
    final error = _quantityError ?? moneyError ?? paymentIssue;

    void next() {
      if (_saving || _openingShift || error != null || _cart.isEmpty) return;
      setState(() {
        if (!_reviewing) {
          _reviewing = true;
          _search.clear();
        } else {
          _paying = true;
        }
        _syncCash();
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
    void addSearch() {
      if (_search.text.trim().isEmpty) return;
      final exact = widget.snapshot.products.where(
        (p) => p.isActive && p.barcode == _search.text.trim(),
      );
      final product = exact.isNotEmpty
          ? exact.first
          : products.isEmpty
          ? null
          : products[_highlighted.clamp(0, products.length - 1)];
      if (product == null) return;
      setState(() {
        _addToCart(product);
        _search.clear();
        _highlighted = 0;
      });
      _searchFocus.requestFocus();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () {
          setState(() {
            _paying = false;
            _reviewing = false;
            _selectedOnly = false;
          });
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): next,
      },
      child: AbsorbPointer(
        absorbing: _saving || _openingShift,
        child: _SaleFrame(
          stage: _paying
              ? 2
              : _reviewing
              ? 1
              : 0,
          title: _paying
              ? 'الدفع وتأكيد البيع'
              : _reviewing
              ? 'مراجعة أصناف الفاتورة'
              : 'البيع',
          trailing: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_reviewing || _paying)
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _paying = false;
                    _reviewing = false;
                    _selectedOnly = false;
                    _search.clear();
                  }),
                  icon: const Icon(
                    Icons.arrow_forward,
                    textDirection: TextDirection.ltr,
                  ),
                  label: const Text('العودة للأصناف'),
                ),
              _SaleWorkspaceBar(
                session: _workspace,
                onSuspend: _suspendWorkspace,
                onList: _openWorkspaces,
                onDiscard: _hasSavedDraft ? _discardDraft : null,
                notice: _draftNotice,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_draftNotice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: _DailyNotice(
                      message: _draftNotice!,
                      warning:
                          _draftNotice != 'تمت استعادة مسودة البيع المحفوظة.',
                    ),
                  ),
                ),
              if (_workspace.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AuthNotice(
                    message:
                        'تعذر حفظ المسودة. اضغط «حفظ مسودة» لإعادة المحاولة قبل مغادرة الفاتورة.',
                  ),
                ),
              if (!_paying) ...[
                _SaleFilters(
                  reviewing: _reviewing,
                  all: widget.snapshot.products,
                  search: _search,
                  focus: _searchFocus,
                  category: _reviewing ? null : _category,
                  selectedOnly: _reviewing || _selectedOnly,
                  selectedCount: _cart.length,
                  onChanged: () => setState(() => _highlighted = 0),
                  onCategory: (c) => setState(() => _category = c),
                  onSelectedOnly: (v) => setState(() {
                    _selectedOnly = v;
                    if (!v) _reviewing = false;
                  }),
                  onSubmit: addSearch,
                ),
                Expanded(
                  child: _GlassPane(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: _CheckoutCatalog(
                      kind: _CheckoutKind.sale,
                      reviewedSale: true,
                      products: products,
                      quantity: (id) =>
                          _cart
                              .where((l) => l.product.id == id)
                              .firstOrNull
                              ?.qty ??
                          0,
                      quantityText: (id) => _quantityRaw[id] ?? '',
                      onQuantity: _setQuantity,
                      costText: (p) =>
                          _priceRaw[p.id] ??
                          _minorToInputText(
                            _cart
                                    .where((l) => l.product.id == p.id)
                                    .firstOrNull
                                    ?.unitPriceMinor ??
                                p.salePriceMinor,
                          ),
                      onCost: _setPrice,
                      onAdd: (p) => setState(() => _addToCart(p)),
                      unitMinor: (p) =>
                          _cart
                              .where((l) => l.product.id == p.id)
                              .firstOrNull
                              ?.unitPriceMinor ??
                          p.salePriceMinor,
                      highlightedId: products.isEmpty || !_searchFocus.hasFocus
                          ? null
                          : products[_highlighted.clamp(0, products.length - 1)]
                                .id,
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: _GlassPane(
                    child: SingleChildScrollView(
                      key: const ValueKey('checkout-payment-scroll'),
                      child: _SalePaymentPane(
                        summary: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'ملخص الدفع',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            _SaleMoneyRow('الإجمالي قبل الخصم', total),
                            _SaleMoneyRow('الخصم', discount),
                            if (remaining > 0 &&
                                _parseMoney(_interest.text) > 0)
                              _SaleMoneyRow(
                                'فائدة التقسيط',
                                _parseMoney(_interest.text),
                              ),
                            _SaleMoneyRow('المطلوب', amountDue, strong: true),
                            _SaleMoneyRow('المدفوع', paid),
                            _SaleMoneyRow('المتبقي', math.max(0, withInterest)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'راجع طريقة الدفع والمبلغ، ثم أكد تسجيل الفاتورة.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<_CheckoutPayment>(
                              initialValue: _payment,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'طريقة الدفع',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: _CheckoutPayment.cash,
                                  child: Text('نقدي بالكامل'),
                                ),
                                DropdownMenuItem(
                                  value: _CheckoutPayment.wallet,
                                  child: Text('محفظة'),
                                ),
                                DropdownMenuItem(
                                  value: _CheckoutPayment.mixed,
                                  child: Text('نقدي ومحفظة'),
                                ),
                                DropdownMenuItem(
                                  value: _CheckoutPayment.installment,
                                  child: Text('تقسيط'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _payment = value;
                                  _automaticCash =
                                      value == _CheckoutPayment.cash;
                                  _restoringEditor = true;
                                  _cash.clear();
                                  _wallet.clear();
                                  if (value == _CheckoutPayment.wallet) {
                                    _wallet.text = _minorToInputText(
                                      math.max(0, net),
                                    );
                                  }
                                  _restoringEditor = false;
                                  _syncCash();
                                  _markDirty();
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            if (_payment != _CheckoutPayment.wallet)
                              _saleMoneyField(
                                _cash,
                                'كاش',
                                onChanged: (_) {
                                  _automaticCash = false;
                                  _markDirty();
                                  setState(() {});
                                },
                              ),
                            if (_payment == _CheckoutPayment.wallet ||
                                _payment == _CheckoutPayment.mixed) ...[
                              const SizedBox(height: 8),
                              _saleMoneyField(
                                _wallet,
                                'محفظة',
                                onChanged: (_) {
                                  _markDirty();
                                  setState(() {});
                                },
                              ),
                            ],
                            const SizedBox(height: 8),
                            _saleMoneyField(
                              _discount,
                              'خصم الفاتورة',
                              onChanged: (_) {
                                _syncCash();
                                _markDirty();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: _customerId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: remaining > 0
                                    ? 'العميل للتقسيط'
                                    : 'العميل (اختياري)',
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('بدون عميل'),
                                ),
                                for (final c in widget.snapshot.customers)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(() {
                                _customerId = value;
                                _markDirty();
                              }),
                            ),
                            if (remaining > 0 ||
                                _payment == _CheckoutPayment.installment) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _installmentCount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'عدد الأقساط',
                                ),
                                onChanged: (_) => setState(() => _markDirty()),
                              ),
                              const SizedBox(height: 8),
                              _saleMoneyField(
                                _interest,
                                'فائدة اختيارية',
                                onChanged: (_) => setState(() => _markDirty()),
                              ),
                              const SizedBox(height: 8),
                              _InstallmentScheduleEditor(
                                firstDueDate: _firstDueDate,
                                periodDays: _periodDays,
                                customPeriodController: _customPeriodDays,
                                installmentCount: count,
                                previewInstallmentMinor: installment,
                                onPickDate: _pickFirstDueDate,
                                onPeriodChanged: (value) => setState(() {
                                  _periodDays = value;
                                  _markDirty();
                                }),
                                onCustomPeriodChanged: (_) =>
                                    setState(() => _markDirty()),
                              ),
                            ],
                            if (widget.snapshot.dashboard.openShift == null &&
                                _parseMoney(_cash.text) > 0) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'افتح وردية لإتمام البيع النقدي. أصناف الفاتورة محفوظة.',
                              ),
                              FilledButton.icon(
                                onPressed: _openingShift
                                    ? null
                                    : _openSaleShift,
                                icon: const Icon(Icons.lock_open),
                                label: const Text('فتح وردية والعودة للفاتورة'),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AuthNotice(message: error),
                ),
              _SaleFooter(
                types: _cart.length,
                pieces: _cart.fold<int>(0, (sum, l) => sum + l.qty),
                total: total,
                net: _paying ? amountDue : net,
                paid: paid,
                remaining: math.max(0, withInterest),
                includesInterest:
                    _paying && remaining > 0 && _parseMoney(_interest.text) > 0,
                discount: discount,
                paying: _paying,
                reviewing: _reviewing,
                saving: _saving,
                onNext: _cart.isEmpty || error != null || _saving
                    ? null
                    : _paying
                    ? () => _submitSale(total)
                    : next,
                onSave: _saveDraft,
                onDiscard: _hasSavedDraft ? _discardDraft : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallmentScheduleEditor extends StatelessWidget {
  const _InstallmentScheduleEditor({
    required this.firstDueDate,
    required this.periodDays,
    required this.customPeriodController,
    required this.installmentCount,
    required this.previewInstallmentMinor,
    required this.onPickDate,
    required this.onPeriodChanged,
    required this.onCustomPeriodChanged,
  });

  final DateTime firstDueDate;
  final int periodDays;
  final TextEditingController customPeriodController;
  final int installmentCount;
  final int previewInstallmentMinor;
  final VoidCallback onPickDate;
  final ValueChanged<int> onPeriodChanged;
  final ValueChanged<String> onCustomPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LiquidGlassColors.of(context).row,
        borderRadius: BorderRadius.circular(V2DesignTokens.radiusMd),
        border: Border.all(color: LiquidGlassColors.of(context).row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDate,
                    icon: const Icon(Icons.event),
                    label: Text('أول قسط ${_date(firstDueDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: periodDays,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الفترة'),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('شهري')),
                      DropdownMenuItem(value: 15, child: Text('نصف شهري')),
                      DropdownMenuItem(value: 7, child: Text('أسبوعي')),
                      DropdownMenuItem(value: -1, child: Text('مخصص')),
                    ],
                    onChanged: (value) => onPeriodChanged(value ?? 30),
                  ),
                ),
              ],
            ),
            if (periodDays == -1) ...[
              const SizedBox(height: 8),
              TextField(
                controller: customPeriodController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'عدد الأيام بين كل قسط',
                ),
                onChanged: onCustomPeriodChanged,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              installmentCount <= 0
                  ? 'أدخل عدد الأقساط لعرض المعاينة'
                  : 'معاينة: $installmentCount أقساط · أول قسط ${Money(previewInstallmentMinor).format()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
