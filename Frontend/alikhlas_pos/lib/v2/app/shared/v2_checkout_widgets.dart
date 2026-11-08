part of '../v2_app.dart';

enum _CheckoutPayment { cash, wallet, mixed, installment }

enum _CheckoutKind { sale, purchase }

String _catalogSearch(String value) => normalizeArabicDigits(value)
    .toLowerCase()
    .replaceAll(RegExp('[\u064b-\u065f\u0670ـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .trim();

List<Product> _checkoutProducts(
  List<Product> all,
  String query,
  String? category,
  bool selectedOnly,
  bool Function(int) selected,
) {
  final words = _catalogSearch(
    query,
  ).split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  return all.where((p) {
    if (!p.isActive || (selectedOnly && !selected(p.id))) return false;
    if (category != null && p.category != category) return false;
    final text = _catalogSearch(
      '${p.name} ${p.barcode ?? ''} ${p.category ?? ''}',
    );
    return words.every(text.contains);
  }).toList();
}

class _CheckoutCatalog extends StatefulWidget {
  const _CheckoutCatalog({
    required this.kind,
    required this.products,
    required this.quantity,
    required this.quantityText,
    required this.onQuantity,
    required this.onAdd,
    required this.unitMinor,
    this.costText,
    this.onCost,
    this.highlightedId,
  });
  final _CheckoutKind kind;
  final List<Product> products;
  final int Function(int) quantity;
  final String Function(int) quantityText;
  final void Function(Product, String) onQuantity;
  final void Function(Product) onAdd;
  final int Function(Product) unitMinor;
  final String Function(Product)? costText;
  final void Function(Product, String)? onCost;
  final int? highlightedId;

  @override
  State<_CheckoutCatalog> createState() => _CheckoutCatalogState();
}

class _CheckoutCatalogState extends State<_CheckoutCatalog> {
  final _scroll = ScrollController();
  final _focus = <String, FocusNode>{};
  FocusNode _node(int id, bool cost) =>
      _focus.putIfAbsent('$id:$cost', () => FocusNode());
  double get _rowHeight =>
      100 * MediaQuery.textScalerOf(context).scale(14) / 14;

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _rowHeight;
    final position = _scroll.position;
    if (top < position.pixels ||
        top + _rowHeight > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top.clamp(0, position.maxScrollExtent));
    }
  }

  bool _tab(int index, bool cost, bool reverse) {
    final hasCost = widget.onCost != null;
    var nextIndex = index;
    var nextCost = false;
    if (reverse) {
      if (hasCost && cost) {
        nextCost = false;
      } else {
        nextIndex--;
        nextCost = hasCost;
      }
    } else {
      if (hasCost && !cost) {
        nextCost = true;
      } else {
        nextIndex++;
      }
    }
    if (nextIndex < 0 || nextIndex >= widget.products.length) return false;
    _reveal(nextIndex);
    final node = _node(widget.products[nextIndex].id, nextCost);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
    setState(() {});
    return true;
  }

  @override
  void didUpdateWidget(covariant _CheckoutCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedId != oldWidget.highlightedId &&
        widget.highlightedId != null) {
      final index = widget.products.indexWhere(
        (p) => p.id == widget.highlightedId,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && index >= 0) _reveal(index);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final quantity = widget.quantity;
    final quantityText = widget.quantityText;
    final onQuantity = widget.onQuantity;
    final onAdd = widget.onAdd;
    final unitMinor = widget.unitMinor;
    final costText = widget.costText;
    final onCost = widget.onCost;
    final highlightedId = widget.highlightedId;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wide = constraints.maxWidth >= 960 * scale;
        final qtyWidth = 90.0 * scale;
        final amountWidth = 116.0 * scale;
        Widget header(String text, double width) => SizedBox(
          width: width,
          child: Text(text, textAlign: TextAlign.center),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Expanded(
                    child: Text(
                      'الصنف',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  header('المتاح', 56 * scale),
                  header('الكمية', qtyWidth),
                  if (wide || onCost != null)
                    header(
                      widget.kind == _CheckoutKind.sale
                          ? 'سعر الوحدة'
                          : 'تكلفة الوحدة',
                      amountWidth,
                    ),
                  header('الإجمالي', amountWidth),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: products.isEmpty
                  ? const Center(child: Text('لا توجد أصناف مطابقة'))
                  : ListView.builder(
                      key: const PageStorageKey('checkout-catalog-scroll'),
                      controller: _scroll,
                      itemExtent: _rowHeight,
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final qty = quantity(p.id);
                        final raw = quantityText(p.id);
                        final parsed = int.tryParse(
                          normalizeArabicDigits(raw.trim()),
                        );
                        final invalid =
                            (raw.isNotEmpty || qty > 0) &&
                            (parsed == null ||
                                parsed < 0 ||
                                (widget.kind == _CheckoutKind.sale &&
                                    parsed > p.stockQty));
                        final total =
                            BigInt.from(qty) * BigInt.from(unitMinor(p));
                        final totalText =
                            total > maxMoneyMinor || total < minMoneyMinor
                            ? 'راجع المبلغ'
                            : Money(total.toInt()).format();
                        return DecoratedBox(
                          key: ValueKey('catalog-row-${p.id}'),
                          decoration: BoxDecoration(
                            color: highlightedId == p.id
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .12)
                                : qty > 0
                                ? LiquidGlassColors.of(context).row
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: LiquidGlassColors.of(
                                  context,
                                ).stroke.withValues(alpha: .18),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Focus(
                                    descendantsAreTraversable: false,
                                    child: Checkbox(
                                      value: qty > 0,
                                      onChanged:
                                          p.stockQty <= 0 &&
                                              widget.kind ==
                                                  _CheckoutKind.sale &&
                                              qty == 0
                                          ? null
                                          : (value) => onQuantity(
                                              p,
                                              value == true ? '1' : '0',
                                            ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Tooltip(
                                    message: p.name,
                                    child: InkWell(
                                      canRequestFocus: false,
                                      onTap:
                                          p.stockQty <= 0 &&
                                              widget.kind == _CheckoutKind.sale
                                          ? null
                                          : () => onAdd(p),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                            Text(
                                              p.barcode ?? 'بدون باركود',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            if (!wide && onCost == null)
                                              Text(
                                                Money(unitMinor(p)).format(),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 56 * scale,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('${p.stockQty}'),
                                      if (widget.kind == _CheckoutKind.sale &&
                                          qty > 0)
                                        Text(
                                          'يتبقى ${p.stockQty - qty}',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: qtyWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: _CheckoutTextCell(
                                      key: ValueKey('checkout-qty-${p.id}'),
                                      focus: _node(p.id, false),
                                      onTab: (reverse) =>
                                          _tab(index, false, reverse),
                                      value: raw,
                                      label: 'كمية ${p.name}',
                                      invalid: invalid,
                                      onChanged: (value) =>
                                          onQuantity(p, value),
                                    ),
                                  ),
                                ),
                                if (onCost != null)
                                  SizedBox(
                                    width: amountWidth,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: _CheckoutTextCell(
                                        key: ValueKey(
                                          widget.kind == _CheckoutKind.sale
                                              ? 'checkout-price-${p.id}'
                                              : 'checkout-cost-${p.id}',
                                        ),
                                        focus: _node(p.id, true),
                                        onTab: (reverse) =>
                                            _tab(index, true, reverse),
                                        value: costText!(p),
                                        label:
                                            '${widget.kind == _CheckoutKind.sale ? 'سعر' : 'تكلفة'} ${p.name}',
                                        invalid:
                                            !parseMoneyInput(
                                              costText(p),
                                            ).isValid ||
                                            parseMoneyInput(
                                                  costText(p),
                                                ).minorUnits <
                                                0,
                                        onChanged: (value) => onCost(p, value),
                                      ),
                                    ),
                                  )
                                else if (wide)
                                  SizedBox(
                                    width: amountWidth,
                                    child: Text(
                                      Money(unitMinor(p)).format(),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                SizedBox(
                                  width: amountWidth,
                                  child: Text(
                                    totalText,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CheckoutTextCell extends StatefulWidget {
  const _CheckoutTextCell({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    required this.focus,
    required this.onTab,
    this.invalid = false,
  });
  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  final bool invalid;
  final FocusNode focus;
  final bool Function(bool) onTab;
  @override
  State<_CheckoutTextCell> createState() => _CheckoutTextCellState();
}

class _CheckoutTextCellState extends State<_CheckoutTextCell> {
  late final _controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _CheckoutTextCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    skipTraversal: true,
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.tab &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        return widget.onTab(HardwareKeyboard.instance.isShiftPressed)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      return KeyEventResult.ignored;
    },
    child: TextField(
      focusNode: widget.focus,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        semanticCounterText: widget.label,
        errorText: widget.invalid ? 'راجع القيمة' : null,
      ),
      onChanged: widget.onChanged,
    ),
  );
}

class _CheckoutFilters extends StatelessWidget {
  const _CheckoutFilters({
    required this.all,
    required this.search,
    required this.focus,
    required this.category,
    required this.selectedOnly,
    required this.selectedCount,
    required this.onChanged,
    required this.onCategory,
    required this.onSelectedOnly,
    required this.onSubmit,
  });
  final List<Product> all;
  final TextEditingController search;
  final FocusNode focus;
  final String? category;
  final bool selectedOnly;
  final int selectedCount;
  final VoidCallback onChanged;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onSelectedOnly;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final categories =
        all
            .map((p) => p.category)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: search,
              focusNode: focus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'بحث بالاسم أو الكود أو الباركود · F2',
              ),
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              key: ValueKey(category),
              initialValue: categories.contains(category) ? category : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'التصنيف'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('كل التصنيفات'),
                ),
                for (final c in categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: onCategory,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('المختار فقط ($selectedCount)'),
            selected: selectedOnly,
            onSelected: onSelectedOnly,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({
    required this.session,
    required this.onSuspend,
    required this.onList,
  });
  final InvoiceAutosave session;
  final Future<void> Function() onSuspend;
  final Future<void> Function() onList;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onSuspend,
          icon: const Icon(Icons.pause_circle_outline),
          label: const Text('تعليق وفاتورة جديدة'),
        ),
        OutlinedButton.icon(
          onPressed: onList,
          icon: const Icon(Icons.folder_open),
          label: const Text('الفواتير المعلقة'),
        ),
        Text(session.row?.label ?? 'فاتورة جديدة'),
        if (session.error != null)
          TextButton(
            onPressed: () async {
              try {
                await session.flush();
              } catch (_) {
                /* status remains visible */
              }
            },
            child: const Text('تعذر حفظ المسودة · إعادة المحاولة'),
          )
        else
          Text(
            session.dirty
                ? 'جارٍ حفظ المسودة…'
                : session.row != null
                ? 'تم حفظ المسودة'
                : 'لم تُضف أصناف بعد',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

Future<CheckoutDraft?> _chooseWorkspace(
  BuildContext context,
  V2UseCases uc,
  String kind,
) async {
  return showDialog<CheckoutDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(
          kind == 'sale' ? 'فواتير البيع المعلقة' : 'فواتير الشراء المعلقة',
        ),
        content: SizedBox(
          width: 620,
          height: 400,
          child: FutureBuilder<List<CheckoutDraft>>(
            future: uc.invoiceWorkspaces(kind),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'تعذر تحميل المسودات. أغلق النافذة وأعد المحاولة.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(child: Text('لا توجد فواتير معلّقة'));
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  var readable = true;
                  try {
                    decodeWorkspace(row.payload);
                  } catch (_) {
                    readable = false;
                  }
                  return ListTile(
                    title: Text(row.label),
                    subtitle: Text(
                      '${_dateTime(row.updatedAt)} · ${!readable
                          ? 'تعذر قراءة المحتوى'
                          : row.state == 'submitting'
                          ? 'جارٍ التحقق من الحفظ'
                          : row.state == 'editing'
                          ? 'مفتوحة حاليًا'
                          : 'معلقة'}',
                    ),
                    onTap: !readable || row.state == 'submitting'
                        ? null
                        : () => Navigator.pop(dialogContext, row),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        try {
                          if (action == 'export') {
                            final path = await FilePicker.platform.saveFile(
                              dialogTitle: 'تصدير المسودة',
                              fileName: 'draft-${row.id}.json',
                            );
                            if (path != null) {
                              await File(
                                path,
                              ).writeAsString(row.payload, flush: true);
                            }
                          } else if (action == 'rename') {
                            final controller = TextEditingController(
                              text: row.label,
                            );
                            final label = await showDialog<String>(
                              context: dialogContext,
                              builder: (c) => AlertDialog(
                                title: const Text('اسم الفاتورة المعلقة'),
                                content: TextField(controller: controller),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('رجوع'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, controller.text),
                                    child: const Text('حفظ'),
                                  ),
                                ],
                              ),
                            );
                            controller.dispose();
                            if (label != null) {
                              await uc.renameInvoiceWorkspace(row.id, label);
                            }
                          } else if (action == 'delete') {
                            if (!dialogContext.mounted) return;
                            final yes = await showDialog<bool>(
                              context: dialogContext,
                              builder: (c) => AlertDialog(
                                title: const Text('حذف المسودة فقط؟'),
                                content: Text(row.label),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('رجوع'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('حذف المسودة'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              await uc.deleteInvoiceWorkspace(row.id);
                            }
                          }
                          if (dialogContext.mounted) refresh(() {});
                        } catch (_) {
                          if (dialogContext.mounted) {
                            _showSnack(
                              dialogContext,
                              'تعذر تنفيذ الإجراء. أعد المحاولة.',
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        if (row.state != 'submitting')
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('تغيير الاسم'),
                          ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('تصدير المحتوى'),
                        ),
                        if (row.state != 'submitting')
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف المسودة'),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ),
  );
}
