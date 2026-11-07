part of '../v2_app.dart';

class _ReturnsView extends ConsumerStatefulWidget {
  const _ReturnsView({required this.snapshot});
  final WorkbenchSnapshot snapshot;
  @override
  ConsumerState<_ReturnsView> createState() => _ReturnsViewState();
}

class _ReturnsViewState extends ConsumerState<_ReturnsView> {
  final _search = TextEditingController();
  late Future<List<Object>> _invoices;
  bool _purchases = false;
  int _page = 0;
  String _query = '';
  DateTimeRange? _dates;
  bool _returning = false;

  @override
  void initState() {
    super.initState();
    _invoices = _fetch();
  }

  Future<List<Object>> _fetch() {
    final uc = ref.read(useCasesProvider);
    final before = _dates == null
        ? null
        : DateTime(_dates!.end.year, _dates!.end.month, _dates!.end.day + 1);
    return _purchases
        ? uc.purchaseInvoiceHistory(
            query: _query,
            offset: _page * 20,
            limit: 21,
            createdFrom: _dates?.start,
            createdBefore: before,
          )
        : uc.saleInvoiceHistory(
            query: _query,
            offset: _page * 20,
            limit: 21,
            createdFrom: _dates?.start,
            createdBefore: before,
          );
  }

  void _load() {
    final next = _fetch();
    setState(() {
      _invoices = next;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Screen(
    title: 'الفواتير والمرتجعات',
    subtitle: 'ابحث واعرض الفاتورة الأصلية لإعادة الطباعة أو تسجيل المرتجع',
    child: _GlassPane(
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('فواتير البيع'),
                icon: Icon(Icons.sell),
              ),
              ButtonSegment(
                value: true,
                label: Text('فواتير الشراء'),
                icon: Icon(Icons.local_shipping),
              ),
            ],
            selected: {_purchases},
            onSelectionChanged: (v) {
              _purchases = v.first;
              _page = 0;
              _load();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'رقم الفاتورة أو اسم الطرف أو هاتفه',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) {
              _query = _search.text;
              _page = 0;
              _load();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () {
                  _query = _search.text;
                  _page = 0;
                  _load();
                },
                child: const Text('بحث'),
              ),
              OutlinedButton.icon(
                onPressed: _pickDates,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _dates == null
                      ? 'كل التواريخ'
                      : '${_date(_dates!.start)} — ${_date(_dates!.end)}',
                ),
              ),
              if (_dates != null)
                TextButton(
                  onPressed: () {
                    _dates = null;
                    _page = 0;
                    _load();
                  },
                  child: const Text('مسح التاريخ'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<Object>>(
              future: _invoices,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _load,
                      child: const Text('تعذر تحميل الفواتير. إعادة المحاولة'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                return Column(
                  children: [
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('لا توجد فواتير مطابقة'))
                          : ListView.separated(
                              itemCount: math.min(20, rows.length),
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final number = row is SaleInvoice
                                    ? row.invoiceNo
                                    : (row as PurchaseInvoice).invoiceNo;
                                final date = row is SaleInvoice
                                    ? row.createdAt
                                    : (row as PurchaseInvoice).createdAt;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Wrap(
                                    spacing: 14,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        number,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(_dateTime(date)),
                                      TextButton(
                                        onPressed: _returning
                                            ? null
                                            : () => row is SaleInvoice
                                                  ? _openDetails(row)
                                                  : _openPurchaseDetails(
                                                      row as PurchaseInvoice,
                                                    ),
                                        child: const Text('تفاصيل وطباعة'),
                                      ),
                                      FilledButton(
                                        onPressed: _returning
                                            ? null
                                            : () async {
                                                if (row is SaleInvoice) {
                                                  await _returnSale(
                                                    context,
                                                    ref,
                                                    row,
                                                  );
                                                } else {
                                                  await _openPurchaseReturn(
                                                    (row as PurchaseInvoice).id,
                                                  );
                                                }
                                              },
                                        child: const Text('إنشاء مرتجع'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _page == 0
                              ? null
                              : () {
                                  _page--;
                                  _load();
                                },
                          child: const Text('السابق'),
                        ),
                        Text('صفحة ${_page + 1}'),
                        TextButton(
                          onPressed: rows.length <= 20
                              ? null
                              : () {
                                  _page++;
                                  _load();
                                },
                          child: const Text('التالي'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openPurchaseDetails(PurchaseInvoice invoice) async {
    try {
      final receipt = await ref
          .read(useCasesProvider)
          .purchaseReceipt(invoice.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _SaleReceiptDialog(receipt: receipt),
      );
    } catch (_) {
      if (mounted) _showSnack(context, 'تعذر عرض الفاتورة. أعد المحاولة.');
    }
  }

  Future<void> _pickDates() async {
    final now = ref.read(appClockProvider)();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDateRange: _dates,
      helpText: 'تاريخ الفواتير',
      saveText: 'تطبيق',
      confirmText: 'تطبيق',
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('ar', 'EG'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child!,
      ),
    );
    if (!mounted || selected == null) return;
    _dates = selected;
    _page = 0;
    _load();
  }

  Future<void> _openPurchaseReturn([int? purchaseId]) async {
    if (_returning) return;
    setState(() => _returning = true);
    try {
      final result = await showDialog<AppResult<int>>(
        context: context,
        builder: (_) => _PurchaseReturnDialog(purchaseId: purchaseId),
      );
      if (!mounted || result == null) return;
      _showResult(context, result, success: 'تم تسجيل مرتجع الشراء');
      _refresh(ref);
      _load();
    } catch (_) {
      if (mounted) {
        _showSnack(
          context,
          'تعذر إكمال مرتجع الشراء. راجع الفاتورة والمخزون قبل إعادة المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => _returning = false);
    }
  }

  Future<void> _openDetails(SaleInvoice sale) async {
    if (_returning) return;
    setState(() => _returning = true);
    try {
      final preview = await ref
          .read(useCasesProvider)
          .saleReturnPreview(sale.id);
      if (!mounted) return;
      final createReturn = await showDialog<bool>(
        context: context,
        builder: (_) => _SaleReceiptDialog(
          receipt: preview.receipt,
          currentStatus: preview,
        ),
      );
      if (mounted && createReturn == true) {
        await _returnSale(context, ref, sale);
      }
    } catch (_) {
      if (mounted) {
        _showSnack(context, 'تعذر تحميل تفاصيل الفاتورة. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _returning = false);
    }
  }

  Future<void> _returnSale(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice sale,
  ) async {
    final preview = await ref.read(useCasesProvider).saleReturnPreview(sale.id);
    if (!context.mounted) return;
    if (!preview.lines.any((line) => line.returnableQty > 0)) {
      _showSnack(context, 'لا توجد قطع متاحة للمرتجع في هذه الفاتورة');
      return;
    }
    final result =
        await showDialog<
          ({
            Map<int, int> quantities,
            PaymentMethod method,
            PaymentMethod? overflowMethod,
          })
        >(
          context: context,
          builder: (_) => _ReturnDialog(preview: preview),
        );
    if (result == null || !context.mounted) return;
    final useCases = ref.read(useCasesProvider);
    final request = PendingFinancialOperation.saleReturn(
      operationKey: useCases.newSaleReturnOperationKey(),
      saleId: sale.id,
      saleItemQuantities: result.quantities,
      refundMethod: result.method,
      overflowRefundMethod: result.overflowMethod,
    );
    final appResult = await _runWithNegativeBalanceApproval(
      context,
      action: (allowNegativeBalance) => _submitPendingFinancialOperation(
        useCases,
        request,
        allowNegativeBalance: allowNegativeBalance,
      ),
      onConfirmationDeclined: () => useCases
          .discardUncommittedPendingFinancialOperation(request.operationKey),
    );
    if (!context.mounted) return;
    _showResult(context, appResult, success: 'تم تسجيل المرتجع');
    _refresh(ref);
    if (mounted) _load();
  }
}
