part of '../v2_app.dart';

/// Sale-only surfaces keep the purchase workflow and its visual references intact.
class _SaleFrame extends StatelessWidget {
  const _SaleFrame({
    required this.title,
    required this.stage,
    required this.child,
    this.trailing,
  });
  final String title;
  final int stage;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    final header = _GlassPane(
      enableBlur: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final titleRow = Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'الخطوة ${stage + 1} من 3',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
            ],
          );
          if (box.maxWidth < 650 && trailing != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow,
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing!,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleRow),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          );
        },
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (box.maxWidth < 650 || box.maxHeight < 520 || scale > 1.5) {
          return SingleChildScrollView(
            key: const ValueKey('sale-page-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 10),
                SizedBox(
                  height: math.max(720 * scale, box.maxHeight),
                  child: child,
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 10),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _SaleWorkspaceBar extends StatelessWidget {
  const _SaleWorkspaceBar({
    required this.session,
    required this.onSuspend,
    required this.onList,
    this.onDiscard,
    this.notice,
  });
  final InvoiceAutosave session;
  final Future<void> Function() onSuspend, onList;
  final VoidCallback? onDiscard;
  final String? notice;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: session.error != null
        ? 'تعذر حفظ المسودة · خيارات الفاتورة'
        : 'خيارات الفاتورة',
    icon: Icon(
      session.error != null ? Icons.error_outline : Icons.more_horiz,
      color: session.error != null ? LiquidGlassColors.of(context).error : null,
    ),
    itemBuilder: (_) => [
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          session.error != null
              ? 'تعذر حفظ المسودة'
              : session.dirty
              ? 'جارٍ حفظ المسودة…'
              : session.row != null
              ? 'تم حفظ المسودة'
              : 'فاتورة جديدة',
        ),
      ),
      const PopupMenuDivider(),
      if (notice != null)
        const PopupMenuItem(
          value: 'notice',
          child: Text('تنبيه المسودة المستعادة'),
        ),
      const PopupMenuItem(value: 'suspend', child: Text('تعليق وفاتورة جديدة')),
      const PopupMenuItem(value: 'list', child: Text('الفواتير المعلقة')),
      if (onDiscard != null)
        const PopupMenuItem(value: 'discard', child: Text('مسح المسودة')),
      if (session.error != null)
        const PopupMenuItem(
          value: 'retry',
          child: Text('إعادة محاولة حفظ المسودة'),
        ),
    ],
    onSelected: (value) async {
      switch (value) {
        case 'suspend':
          await onSuspend();
        case 'list':
          await onList();
        case 'discard':
          onDiscard?.call();
        case 'retry':
          try {
            await session.flush();
          } catch (_) {
            /* Error stays visible. */
          }
        case 'notice':
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              scrollable: true,
              title: const Text('تنبيه المسودة'),
              content: Text(notice!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          );
      }
    },
  );
}

class _SaleFilters extends StatelessWidget {
  const _SaleFilters({
    required this.all,
    required this.search,
    required this.focus,
    required this.category,
    required this.selectedOnly,
    required this.selectedCount,
    required this.reviewing,
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
  final bool reviewing;
  final VoidCallback onChanged;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onSelectedOnly;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final categories =
        all
            .where((p) => p.isActive)
            .map((p) => p.category)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final searchField = TextField(
      controller: search,
      focusNode: focus,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        labelText: 'بحث بالاسم أو الكود أو الباركود · F2',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.close, size: 19),
                onPressed: () {
                  search.clear();
                  onChanged();
                  focus.requestFocus();
                },
              ),
      ),
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmit(),
    );
    final categoryField = DropdownButtonFormField<String?>(
      key: ValueKey(category),
      initialValue: categories.contains(category) ? category : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'التصنيف',
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('كل التصنيفات'),
        ),
        for (final c in categories)
          DropdownMenuItem(
            value: c,
            child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onCategory,
    );
    final selected = FilterChip(
      label: Text('المختار فقط ($selectedCount)'),
      selected: selectedOnly,
      onSelected: onSelectedOnly,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          if (reviewing) {
            return searchField;
          }
          if (box.maxWidth < 700 * MediaQuery.textScalerOf(context).scale(1)) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: categoryField),
                    const SizedBox(width: 8),
                    Flexible(child: selected),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              SizedBox(width: 170, child: categoryField),
              const SizedBox(width: 8),
              selected,
            ],
          );
        },
      ),
    );
  }
}

class _SaleFooter extends StatelessWidget {
  const _SaleFooter({
    required this.types,
    required this.pieces,
    required this.total,
    required this.net,
    required this.discount,
    required this.paying,
    required this.reviewing,
    required this.saving,
    required this.onNext,
    required this.onSave,
    this.onDiscard,
    this.paid,
    this.remaining,
    this.includesInterest = false,
  });
  final int types, pieces, total, net, discount;
  final bool paying, reviewing, saving;
  final int? paid;
  final int? remaining;
  final bool includesInterest;
  final VoidCallback? onNext;
  final VoidCallback onSave;
  final VoidCallback? onDiscard;
  @override
  Widget build(BuildContext context) {
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$types نوع · $pieces قطعة',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          '${includesInterest
              ? 'المطلوب بالخصم والفائدة'
              : discount > 0
              ? 'المطلوب بعد الخصم'
              : 'المطلوب'} ${Money(net).format()}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (paying && paid != null && remaining != null)
          Text(
            'المدفوع ${Money(paid!).format()} • المتبقي ${Money(remaining!).format()}',
            key: const ValueKey('sale-settlement-summary'),
            style: Theme.of(context).textTheme.bodySmall,
          )
        else if (discount > 0)
          Text(
            'قبل الخصم ${Money(total).format()} • الخصم ${Money(discount).format()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: FilledButton.icon(
            key: const ValueKey('sale-next'),
            onPressed: onNext,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    paying ? Icons.check_circle_outline : Icons.arrow_back,
                    textDirection: TextDirection.ltr,
                  ),
            label: Text(
              saving
                  ? 'جارٍ الحفظ…'
                  : paying
                  ? 'تأكيد تسجيل البيع'
                  : reviewing
                  ? 'متابعة الدفع'
                  : 'مراجعة ودفع',
            ),
          ),
        ),
        TextButton.icon(
          onPressed: saving ? null : onSave,
          icon: const Icon(Icons.save_outlined, size: 19),
          label: const Text('حفظ مسودة'),
        ),
      ],
    );
    return _GlassPane(
      enableBlur: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 600 * MediaQuery.textScalerOf(context).scale(1)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 8), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 12),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _SaleMoneyRow extends StatelessWidget {
  const _SaleMoneyRow(this.label, this.minor, {this.strong = false});
  final String label;
  final int minor;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(label),
        Text(
          Money(minor).format(),
          style: strong ? Theme.of(context).textTheme.titleLarge : null,
        ),
      ],
    ),
  );
}

extension _ReviewedSaleCatalog on _CheckoutCatalogState {
  void _editReviewedQuantity(int index, Product product, String raw) {
    widget.onQuantity(product, raw);
    if (int.tryParse(normalizeArabicDigits(raw.trim())) != 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.products.isEmpty ||
          widget.products.any((p) => p.id == product.id)) {
        return;
      }
      final next = index.clamp(0, widget.products.length - 1);
      _reveal(next);
      final node = _node(widget.products[next].id, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    });
  }

  Widget _buildReviewedSale(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compactRow = _compactReviewedSale;
    final qtyWidth = 90.0 * scale;
    final priceWidth = 116.0 * scale;
    final amountWidth = 124.0 * scale;
    final stockWidth = 64.0 * scale;
    Widget heading(String text, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final tableWidth = math.max(box.maxWidth - 8, 680 * scale);
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                height: box.maxHeight - 8,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: Text(
                              'الصنف',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          heading('المتاح', stockWidth),
                          heading('الكمية', qtyWidth),
                          SizedBox(
                            width: priceWidth,
                            child: Column(
                              children: [
                                const Text('سعر الوحدة'),
                                Text(
                                  'لهذه الفاتورة فقط',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          heading('الإجمالي', amountWidth),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: widget.products.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.emptyMessage ??
                                          'لا توجد أصناف مطابقة. غيّر البحث أو التصنيف، أو ارجع لكل الأصناف.',
                                      textAlign: TextAlign.center,
                                    ),
                                    if (widget.onEmptyAction != null)
                                      TextButton(
                                        onPressed: widget.onEmptyAction,
                                        child: const Text(
                                          'الذهاب للمخزون وإضافة منتج',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            )
                          : Scrollbar(
                              controller: _scroll,
                              thumbVisibility: true,
                              notificationPredicate: (n) =>
                                  n.metrics.axis == Axis.vertical,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: ListView.builder(
                                  key: const PageStorageKey(
                                    'checkout-catalog-scroll',
                                  ),
                                  controller: _scroll,
                                  itemExtent: _rowHeight,
                                  itemCount: widget.products.length,
                                  itemBuilder: (context, index) {
                                    final p = widget.products[index];
                                    final qty = widget.quantity(p.id);
                                    final raw = widget.quantityText(p.id);
                                    final parsed = int.tryParse(
                                      normalizeArabicDigits(raw.trim()),
                                    );
                                    final invalidQty =
                                        (raw.isNotEmpty || qty > 0) &&
                                        (parsed == null ||
                                            parsed < 0 ||
                                            parsed > p.stockQty);
                                    final price = widget.costText!(p);
                                    final parsedPrice = parseMoneyInput(price);
                                    final total =
                                        BigInt.from(qty) *
                                        BigInt.from(widget.unitMinor(p));
                                    final totalText =
                                        total > maxMoneyMinor ||
                                            total < minMoneyMinor
                                        ? 'راجع المبلغ'
                                        : Money(total.toInt()).format();
                                    return DecoratedBox(
                                      key: ValueKey('catalog-row-${p.id}'),
                                      decoration: BoxDecoration(
                                        color: qty > 0
                                            ? colors.selected.withValues(
                                                alpha: .45,
                                              )
                                            : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colors.stroke,
                                          ),
                                          right: BorderSide(
                                            color: widget.highlightedId == p.id
                                                ? colors.primary
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        // Compact sale rows need enough vertical
                                        // room for both stock and remaining-qty
                                        // labels at 100% and 125% text scaling.
                                        padding: EdgeInsets.symmetric(
                                          vertical: compactRow ? 6 : 8,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 37,
                                              child: Focus(
                                                descendantsAreTraversable:
                                                    false,
                                                child: Checkbox(
                                                  value: qty > 0,
                                                  onChanged:
                                                      p.stockQty <= 0 &&
                                                          qty == 0
                                                      ? null
                                                      : (v) =>
                                                            widget.onQuantity(
                                                              p,
                                                              v == true
                                                                  ? '1'
                                                                  : '0',
                                                            ),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Tooltip(
                                                message: p.name,
                                                child: InkWell(
                                                  canRequestFocus: false,
                                                  onTap: () => showDialog<void>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: Text(p.name),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'المتاح: ${p.stockQty}',
                                                          ),
                                                          Text(
                                                            'سعر البيع: ${Money(p.salePriceMinor).format()}',
                                                          ),
                                                          if (p
                                                                  .category
                                                                  ?.isNotEmpty ==
                                                              true)
                                                            Text(
                                                              'التصنيف: ${p.category}',
                                                            ),
                                                          if (p
                                                                  .barcode
                                                                  ?.isNotEmpty ==
                                                              true)
                                                            Text(
                                                              'الباركود: ${p.barcode}',
                                                            ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: const Text(
                                                            'إغلاق',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          p.name,
                                                          maxLines: compactRow
                                                              ? 1
                                                              : 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall,
                                                        ),
                                                        if (compactRow &&
                                                            (p.category?.isNotEmpty ==
                                                                    true ||
                                                                p
                                                                        .barcode
                                                                        ?.isNotEmpty ==
                                                                    true))
                                                          Text(
                                                            [
                                                              if (p
                                                                      .category
                                                                      ?.isNotEmpty ==
                                                                  true)
                                                                p.category!,
                                                              if (p
                                                                      .barcode
                                                                      ?.isNotEmpty ==
                                                                  true)
                                                                p.barcode!,
                                                            ].join(' · '),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodySmall,
                                                          ),
                                                        if (!compactRow &&
                                                            p
                                                                    .category
                                                                    ?.isNotEmpty ==
                                                                true)
                                                          Text(
                                                            p.category!,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodySmall,
                                                          ),
                                                        if (!compactRow &&
                                                            p
                                                                    .barcode
                                                                    ?.isNotEmpty ==
                                                                true)
                                                          Text(
                                                            p.barcode!,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodySmall,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip:
                                                  'إضافة قطعة من ${p.name}',
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                              ),
                                              onPressed: p.stockQty <= 0
                                                  ? null
                                                  : () => widget.onAdd(p),
                                            ),
                                            SizedBox(
                                              width: stockWidth,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '${p.stockQty}',
                                                    style: TextStyle(
                                                      color: p.stockQty <= 0
                                                          ? colors.error
                                                          : colors.ink,
                                                    ),
                                                  ),
                                                  if (qty > 0)
                                                    Text(
                                                      'يتبقى ${p.stockQty - qty}',
                                                      textAlign:
                                                          TextAlign.center,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                child: _CheckoutTextCell(
                                                  key: ValueKey(
                                                    'checkout-qty-${p.id}',
                                                  ),
                                                  salesStyle: true,
                                                  focus: _node(p.id, false),
                                                  onTab: (reverse) => _tab(
                                                    index,
                                                    false,
                                                    reverse,
                                                  ),
                                                  value: raw,
                                                  label: 'كمية ${p.name}',
                                                  invalid: invalidQty,
                                                  onChanged: (value) =>
                                                      _editReviewedQuantity(
                                                        index,
                                                        p,
                                                        value,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: priceWidth,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                child: _CheckoutTextCell(
                                                  key: ValueKey(
                                                    'checkout-price-${p.id}',
                                                  ),
                                                  salesStyle: true,
                                                  focus: _node(p.id, true),
                                                  onTab: (reverse) => _tab(
                                                    index,
                                                    true,
                                                    reverse,
                                                  ),
                                                  value: price,
                                                  label:
                                                      'سعر ${p.name} لهذه الفاتورة',
                                                  invalid:
                                                      price.trim().isEmpty ||
                                                      !parsedPrice.isValid ||
                                                      parsedPrice.minorUnits <
                                                          0,
                                                  onChanged: (value) =>
                                                      widget.onCost!(p, value),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: amountWidth - 8,
                                              child: Text(
                                                totalText,
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

TextField _saleMoneyField(
  TextEditingController controller,
  String label, {
  ValueChanged<String>? onChanged,
}) => TextField(
  controller: controller,
  textDirection: TextDirection.ltr,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  ),
  onChanged: onChanged,
);

class _SalePaymentPane extends StatelessWidget {
  const _SalePaymentPane({required this.child, required this.summary});
  final Widget child, summary;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final totals = _GlassPane(child: summary);
      if (box.maxWidth < 840 * MediaQuery.textScalerOf(context).scale(1)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child, const SizedBox(height: 16), totals],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: child),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: totals),
        ],
      );
    },
  );
}

extension _ReviewedReceipt on _SaleReceiptDialogState {
  Widget _buildReviewedReceipt(List<SaleReceiptLine> rows) {
    final receipt = widget.receipt;
    return FutureBuilder<ReceiptPrintJob>(
      future: _job,
      builder: (context, job) {
        final viewport = MediaQuery.sizeOf(context);
        final compact =
            viewport.width < 650 ||
            viewport.height - MediaQuery.viewInsetsOf(context).bottom <
                680 * MediaQuery.textScalerOf(context).scale(1);
        Widget lineList() => ListView.separated(
          key: const ValueKey('sale-receipt-lines'),
          shrinkWrap: compact,
          physics: compact ? const NeverScrollableScrollPhysics() : null,
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (context, index) {
            final line = rows[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  line.productName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${line.qty} × ${Money(line.unitPriceMinor).format()}',
                    ),
                    Text(Money(line.lineTotalMinor).format()),
                  ],
                ),
              ],
            );
          },
        );
        Widget document() {
          if (_shape) {
            if (job.hasError) {
              return const Center(
                child: Text(
                  'تعذر تجهيز الإيصال. تفاصيل الفاتورة المحفوظة متاحة.',
                ),
              );
            }
            if (!job.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return PdfPreview(
              build: (_) => Future.value(job.data!.bytes),
              initialPageFormat: job.data!.format,
              maxPageWidth: job.data!.profile.widthMm * 6.0,
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: '${receipt.invoice.invoiceNo}.pdf',
              onError: _previewError,
            );
          }
          return Column(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'بحث داخل الفاتورة',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => _redraw(() {}),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Text('لا توجد أصناف مطابقة داخل الفاتورة.')
              else if (compact)
                lineList()
              else
                Expanded(child: lineList()),
            ],
          );
        }

        Widget body() => Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تم حفظ الفاتورة',
              key: const ValueKey('sale-receipt-saved'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: LiquidGlassColors.of(context).primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              receipt.shopSettings.shopName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Wrap(
              spacing: 20,
              runSpacing: 4,
              children: [
                Text('الفرع: ${receipt.shopSettings.branchName}'),
                Text('التاريخ: ${_dateTime(receipt.invoice.createdAt)}'),
              ],
            ),
            Text(
              '${receipt.documentTitle} ${receipt.invoice.invoiceNo}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${receipt.lines.length} نوع · ${receipt.lines.fold<BigInt>(BigInt.zero, (s, l) => s + BigInt.from(l.qty))} قطعة • ${receipt.customerName ?? 'بدون عميل مسجل'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 4,
              children: [
                Text('المطلوب ${Money(receipt.invoice.totalMinor).format()}'),
                Text('المدفوع ${Money(receipt.invoice.paidMinor).format()}'),
                Text(
                  'المتبقي ${Money(receipt.invoice.remainingMinor).format()}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('تفاصيل الفاتورة'),
                  selected: !_shape,
                  onSelected: _printing
                      ? null
                      : (_) => _redraw(() => _shape = false),
                ),
                ChoiceChip(
                  label: const Text('شكل الإيصال الحراري'),
                  selected: _shape,
                  onSelected: _printing
                      ? null
                      : (_) => _redraw(() => _shape = true),
                ),
              ],
            ),
            if (receipt.hasLegacyProductIdentity)
              const Text(legacyProductIdentityNotice),
            if (job.hasError) ...[
              const SizedBox(height: 8),
              const _AuthNotice(
                message:
                    'الفاتورة محفوظة. تعذر تجهيز الطباعة، وتقدر تعيد المحاولة.',
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _printing
                      ? null
                      : () => _redraw(() {
                          _job = _loadJob();
                        }),
                  child: const Text('إعادة تجهيز الطباعة'),
                ),
              ),
            ],
            if (_printMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(liveRegion: true, child: Text(_printMessage!)),
              ),
            const SizedBox(height: 10),
            if (compact)
              SizedBox(height: _shape ? 420 : null, child: document())
            else
              Expanded(child: document()),
          ],
        );
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 920,
            height: viewport.height * .9,
            child: _GlassPane(
              enableBlur: true,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: compact
                        ? SingleChildScrollView(
                            key: const ValueKey('sale-receipt-scroll'),
                            child: body(),
                          )
                        : body(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      TextButton(
                        onPressed: _printing
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('إغلاق'),
                      ),
                      FilledButton.icon(
                        onPressed: _printing || job.hasError ? null : _print,
                        icon: const Icon(Icons.print_outlined),
                        label: Text(
                          _printing ? 'جارٍ إرسال الإيصال…' : 'طباعة',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
