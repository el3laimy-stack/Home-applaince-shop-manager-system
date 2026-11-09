part of '../v2_app.dart';

class _SaleReceiptDialog extends ConsumerStatefulWidget {
  const _SaleReceiptDialog({
    required this.receipt,
    this.currentStatus,
    this.autoPrint = false,
  });
  final bool autoPrint;
  final SaleReceiptSnapshot receipt;
  final SaleReturnPreview? currentStatus;
  @override
  ConsumerState<_SaleReceiptDialog> createState() => _SaleReceiptDialogState();
}

class _SaleReceiptDialogState extends ConsumerState<_SaleReceiptDialog> {
  bool _printing = false;
  bool _shape = false;
  final _search = TextEditingController();
  String? _printMessage;
  late Future<ReceiptPrintJob> _job = _loadJob();
  bool _autoPrintAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _printNewSale());
  }

  Future<void> _printNewSale() async {
    if (!widget.autoPrint || _autoPrintAttempted || !mounted) return;
    _autoPrintAttempted = true;
    try {
      final job = await _job;
      if (mounted && job.profile.autoPrintAfterSale && !_printing) {
        await _print();
      }
    } catch (_) {
      // Preview presents its retry action; the sale is already committed.
    }
  }

  Future<ReceiptPrintJob> _loadJob() async {
    final uc = ref.read(useCasesProvider);
    final profile = await uc.receiptPrintProfile();
    return SaleReceiptPdf.document(widget.receipt, profile: profile);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final rows = receipt.lines
        .where(
          (l) => _catalogSearch(
            '${l.productName} ${l.productBarcode ?? ''}',
          ).contains(_catalogSearch(_search.text)),
        )
        .toList();
    return AlertDialog(
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(receipt.shopSettings.shopName),
          Text('الفرع: ${receipt.shopSettings.branchName}'),
          Text('التاريخ: ${_dateTime(receipt.invoice.createdAt)}'),
          Text('${receipt.documentTitle} ${receipt.invoice.invoiceNo}'),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: (MediaQuery.sizeOf(context).height - 350).clamp(160.0, 520.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('تفاصيل الفاتورة'),
                  icon: Icon(Icons.receipt_long),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('شكل الإيصال الحراري'),
                  icon: Icon(Icons.print),
                ),
              ],
              selected: {_shape},
              onSelectionChanged: _printing
                  ? null
                  : (v) => setState(() => _shape = v.first),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<ReceiptPrintJob>(
                future: _job,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _job = _loadJob()),
                        child: const Text('تعذر تجهيز الإيصال. إعادة المحاولة'),
                      ),
                    );
                  }
                  if (_shape) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final job = snapshot.data!;
                    return PdfPreview(
                      build: (_) => Future.value(job.bytes),
                      initialPageFormat: job.format,
                      maxPageWidth: job.profile.widthMm * 6.0,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      pdfFileName: '${receipt.invoice.invoiceNo}.pdf',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${receipt.customerName ?? 'نقدي'} · ${_dateTime(receipt.invoice.createdAt)}',
                      ),
                      Text(
                        '${receipt.lines.length} نوع · ${receipt.lines.fold<BigInt>(BigInt.zero, (s, l) => s + BigInt.from(l.qty))} قطعة',
                      ),
                      if (receipt.hasLegacyProductIdentity)
                        const Text(legacyProductIdentityNotice),
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'بحث داخل الفاتورة',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final line = rows[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    line.productName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 10,
                                    children: [
                                      Text(
                                        '${line.qty} × ${Money(line.unitPriceMinor).format()}',
                                      ),
                                      Text(Money(line.lineTotalMinor).format()),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      SizedBox(
                        height: 150,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AmountRow(
                                'الإجمالي',
                                receipt.invoice.subtotalMinor,
                              ),
                              if (receipt.invoice.discountMinor > 0)
                                _AmountRow(
                                  'الخصم',
                                  receipt.invoice.discountMinor,
                                ),
                              if (receipt.invoice.interestMinor > 0)
                                _AmountRow(
                                  'الفائدة',
                                  receipt.invoice.interestMinor,
                                ),
                              _AmountRow(
                                'المطلوب',
                                receipt.invoice.totalMinor,
                                strong: true,
                              ),
                              _AmountRow('المدفوع', receipt.invoice.paidMinor),
                              _AmountRow(
                                'المتبقي',
                                receipt.invoice.remainingMinor,
                              ),
                              for (final p in receipt.payments)
                                _AmountRow(
                                  _paymentMethodText(p.method),
                                  p.amountMinor,
                                ),
                              if (widget.currentStatus case final status?) ...[
                                const Divider(),
                                _AmountRow(
                                  'تحصيل أقساط بعد البيع',
                                  status.collectedInstallmentsMinor,
                                ),
                                _AmountRow(
                                  'إجمالي المرتجع حتى الآن',
                                  status.lines.fold<int>(
                                    0,
                                    (s, l) => s + l.refundedMinor,
                                  ),
                                ),
                                if (status.remainingDebtMinor != null)
                                  _AmountRow(
                                    'المديونية الحالية',
                                    status.remainingDebtMinor!,
                                  ),
                                const Text(
                                  'مبالغ الفاتورة المطبوعة تخص وقت البيع؛ التحصيل والمرتجعات موضحة هنا بشكل منفصل.',
                                ),
                              ],
                              if (receipt.shopSettings.receiptFooter != null)
                                Text(
                                  receipt.shopSettings.receiptFooter!,
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_printMessage != null) Text(_printMessage!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        if (widget.currentStatus case final status?)
          TextButton(
            onPressed:
                _printing || !status.lines.any((l) => l.returnableQty > 0)
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('إنشاء مرتجع'),
          ),
        FilledButton.icon(
          onPressed: _printing ? null : _print,
          icon: const Icon(Icons.print),
          label: Text(_printing ? 'جارٍ إرسال الإيصال…' : 'طباعة'),
        ),
      ],
    );
  }

  Future<void> _print() async {
    final printer = ref.read(receiptDocumentPrinterProvider);
    setState(() {
      _printing = true;
      _printMessage = null;
    });
    try {
      final result = await printer(await _job);
      if (!mounted) return;
      setState(
        () => _printMessage = switch (result) {
          ReceiptPrintOutcome.submitted =>
            'تم إرسال طلب الطباعة. الفاتورة محفوظة.',
          ReceiptPrintOutcome.cancelled =>
            'أُلغيت الطباعة. الفاتورة محفوظة ويمكن طباعتها لاحقًا.',
          ReceiptPrintOutcome.failed =>
            'الفاتورة محفوظة، لكن تعذرت الطباعة. يمكنك إعادة المحاولة.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _printMessage =
              'الفاتورة محفوظة، لكن تعذرت الطباعة. يمكنك إعادة المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}

class _ReceiptInfoBlock extends StatelessWidget {
  const _ReceiptInfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _mutedInk)),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
