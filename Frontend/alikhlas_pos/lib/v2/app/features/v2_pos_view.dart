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
      return _Screen(
        title: 'البيع',
        subtitle: 'التحقق من نتيجة الحفظ',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يوجد طلب بيع يحتاج استكمال التحقق. إعادة المحاولة تستخدم نفس الطلب.',
              ),
              const SizedBox(height: 12),
              Text('عدد الأصناف: ${_pendingSale!.items.length}'),
              if (_pendingError != null) Text(_pendingError!),
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
      BigInt.from(remaining) + BigInt.from(_parseMoney(_interest.text)),
    );
    final installment = count > 0 && withInterest > 0
        ? allocateRemainderToLast(withInterest, count, 0)
        : 0;
    final moneyError =
        preview.error ??
        _firstMoneyInputError({
          'كاش': _cash,
          'محفظة': _wallet,
          'خصم الفاتورة': _discount,
          'فائدة اختيارية': _interest,
        });
    final error = _quantityError ?? moneyError;
    void next() {
      if (error != null || _cart.isEmpty) return;
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
          setState(() => _paying = false);
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): next,
      },
      child: AbsorbPointer(
        absorbing: _saving,
        child: _Screen(
          title: _paying
              ? 'الدفع وتأكيد البيع'
              : _reviewing
              ? 'مراجعة أصناف الفاتورة'
              : 'البيع',
          subtitle: 'اختيار الأصناف ← مراجعة ودفع ← حفظ ومعاينة',
          trailing: _reviewing || _paying
              ? OutlinedButton.icon(
                  onPressed: () => setState(() {
                    if (_paying) {
                      _paying = false;
                    } else {
                      _reviewing = false;
                    }
                  }),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('العودة للأصناف'),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceToolbar(
                session: _workspace,
                onSuspend: _suspendWorkspace,
                onList: _openWorkspaces,
              ),
              if (_draftNotice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_draftNotice!),
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
                  onCategory: (c) => setState(() => _category = c),
                  onSelectedOnly: (v) => setState(() {
                    _selectedOnly = v;
                    if (!v) _reviewing = false;
                  }),
                  onSubmit: addSearch,
                ),
                Expanded(
                  child: _GlassPane(
                    child: _CheckoutCatalog(
                      products: products,
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
                              ?.unitPriceMinor ??
                          p.salePriceMinor,
                      highlightedId: products.isEmpty
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
                                _automaticCash = value == _CheckoutPayment.cash;
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
                            _moneyField(
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
                            _moneyField(
                              _wallet,
                              'محفظة',
                              onChanged: (_) {
                                _markDirty();
                                setState(() {});
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          _moneyField(
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
                            _moneyField(
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
                          const SizedBox(height: 16),
                          _AmountRow('الإجمالي قبل الخصم', total),
                          _AmountRow('الخصم', discount),
                          _AmountRow('المطلوب', net, strong: true),
                          _AmountRow('المدفوع', paid),
                          _AmountRow('المتبقي', math.max(0, remaining)),
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
                      '${_cart.length} نوع · ${_cart.fold<int>(0, (sum, l) => sum + l.qty)} قطعة',
                    ),
                    Text(
                      'الإجمالي ${Money(total).format()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    FilledButton.icon(
                      onPressed: _cart.isEmpty || error != null
                          ? null
                          : _paying
                          ? () => _submitSale(total)
                          : next,
                      icon: Icon(
                        _paying ? Icons.check_circle : Icons.arrow_back,
                      ),
                      label: Text(
                        _saving
                            ? 'جاري الحفظ…'
                            : _paying
                            ? 'تأكيد تسجيل البيع'
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
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(V2DesignTokens.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: V2DesignTokens.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
