part of '../v2_app.dart';

/// Edits remain local until the existing atomic, durable import is approved.
class _BulkProductsDialog extends ConsumerStatefulWidget {
  const _BulkProductsDialog();

  @override
  ConsumerState<_BulkProductsDialog> createState() =>
      _BulkProductsDialogState();
}

class _BulkProductsDialogState extends ConsumerState<_BulkProductsDialog> {
  static const _labels = [
    'اسم المنتج',
    'الباركود (اختياري)',
    'التصنيف (اختياري)',
    'سعر بيع القطعة',
    'الكمية بالمحل والمخزن',
    'تكلفة القطعة',
    'حد النقص',
  ];
  final _rows = <List<TextEditingController>>[];
  ProductCsvPreview? _preview;
  PendingFinancialOperation? _request;
  bool _busy = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _addRow();
  }

  void _addRow() {
    _rows.add([
      for (final value in ['', '', '', '', '0', '0', '0'])
        TextEditingController(text: value),
    ]);
    _preview = null;
  }

  String _source() =>
      ref.read(useCasesProvider).productCsvTemplate() +
      _rows
          .map(
            (row) => row
                .map((cell) => '"${cell.text.replaceAll('"', '""')}"')
                .join(','),
          )
          .join('\r\n');

  @override
  void dispose() {
    for (final row in _rows) {
      for (final cell in row) {
        cell.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _close() async {
    if (_edited && _request == null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('البيانات لم تُعتمد بعد'),
          content: const Text(
            'يمكنك الرجوع وحفظ مسودة CSV لاستكمالها لاحقًا من استيراد CSV. هل تريد إغلاق الإدخال دون حفظ؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('الرجوع للإدخال'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إغلاق دون حفظ'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(productCsvTemplateSaverProvider)(_source());
      if (mounted)
        _showSnack(
          context,
          saved
              ? 'تم حفظ المسودة. استكملها لاحقًا باستخدام استيراد CSV؛ لم يتغير المخزون.'
              : 'لم تُحفظ المسودة',
        );
    } on Object {
      if (mounted)
        _showSnack(context, 'تعذر حفظ المسودة. البيانات ما زالت هنا.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    setState(() => _busy = true);
    final useCases = ref.read(useCasesProvider);
    try {
      if (_request == null) {
        final preview = await useCases.previewProductCsv(_source());
        if (!mounted) return;
        setState(() => _preview = preview);
        if (!preview.canImport) return;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ProductCsvPreviewDialog(
            fileName: 'بضاعة أول المدة — إجمالي الموجود بالمحل والمخزن',
            preview: preview,
          ),
        );
        if (!mounted || confirmed != true) return;
        _request = PendingFinancialOperation.productCsvImport(
          operationKey: useCases.newProductCsvImportOperationKey(),
          rows: preview.rows,
        );
      }
      final result = await _submitPendingFinancialOperation(
        useCases,
        _request!,
        allowNegativeBalance: false,
      );
      if (!mounted) return;
      _showResult(
        context,
        result,
        success: 'تم تسجيل البضاعة والأرصدة الافتتاحية بنجاح',
      );
      if (result is AppSuccess<int>) {
        _refresh(ref);
        Navigator.pop(context);
      }
    } on Object {
      if (mounted)
        _showSnack(
          context,
          'تعذر إكمال العملية. بياناتك ما زالت هنا؛ أعد المحاولة بنفس الطلب.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _request != null;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('تجهيز البضاعة بالجملة'),
        content: SizedBox(
          width: 1120,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '١ أدخل البضاعة   ←   ٢ راجع الإجماليات   ←   ٣ اعتمد المخزون',
              ),
              const SizedBox(height: 8),
              const Text(
                'كل صف لصنف واحد. اجمع الموجود في المحل والمخزن؛ النظام يحتفظ برصيد موحد. تكلفة القطعة هي سعر شراء قطعة واحدة، وليست تكلفة الكمية كلها. اترك الباركود فارغًا لتوليده تلقائيًا.',
              ),
              const SizedBox(height: 8),
              Text(
                '${_rows.length} صنف • استخدم Tab للتنقل بين الخانات. لا يتغير المخزون قبل الاعتماد.',
              ),
              if (_request != null)
                const Text(
                  'تم تثبيت الطلب. إعادة المحاولة تستخدم نفس الطلب لمنع تكرار البضاعة.',
                ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1240,
                    child: ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final issues =
                            _preview?.issues
                                .where((issue) => issue.sourceRow == index + 2)
                                .toList() ??
                            [];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Text('${index + 1}'),
                                  ),
                                  for (var column = 0; column < 7; column++)
                                    Expanded(
                                      flex: column == 0 ? 2 : 1,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: TextField(
                                          key: ValueKey('bulk-$index-$column'),
                                          controller: _rows[index][column],
                                          enabled: !locked,
                                          decoration: InputDecoration(
                                            labelText: _labels[column],
                                          ),
                                          keyboardType: column >= 3
                                              ? const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                )
                                              : TextInputType.text,
                                          onChanged: (_) {
                                            _edited = true;
                                            if (_preview != null)
                                              setState(() => _preview = null);
                                          },
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'حذف الصف ${index + 1}',
                                    onPressed: locked || _rows.length == 1
                                        ? null
                                        : () {
                                            setState(() {
                                              final row = _rows.removeAt(index);
                                              for (final cell in row) {
                                                cell.dispose();
                                              }
                                              _preview = null;
                                              _edited = true;
                                            });
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              for (final issue in issues)
                                Text(
                                  'الصف ${index + 1}: ${issue.message}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_preview != null && !_preview!.canImport)
                Text(
                  'صحح الأخطاء الموضحة في الصفوف (${_preview!.issues.length}). لم يُحفظ أي صنف.',
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: locked || _rows.length >= 2000
                      ? null
                      : () => setState(_addRow),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صف'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _close,
            child: const Text('إغلاق'),
          ),
          OutlinedButton(
            onPressed: locked ? null : _export,
            child: const Text('حفظ مسودة CSV'),
          ),
          FilledButton(
            onPressed: _busy ? null : _review,
            child: Text(
              _busy
                  ? 'جاري الفحص والحفظ...'
                  : _request != null
                  ? 'إعادة محاولة نفس الطلب'
                  : 'مراجعة البضاعة',
            ),
          ),
        ],
      ),
    );
  }
}
