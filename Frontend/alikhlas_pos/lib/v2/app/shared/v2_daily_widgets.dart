part of '../v2_app.dart';

/// Natural-height tiles keep text readable as the viewport or font changes.
class _DailyGrid extends StatelessWidget {
  const _DailyGrid({
    required this.children,
    this.minWidth = 220,
    this.maxColumns = 3,
  });
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
      var columns = ((box.maxWidth + 12) / (minWidth * scale + 12))
          .floor()
          .clamp(1, maxColumns)
          .clamp(1, children.length);
      if (children.length == 4 && columns == 3) columns = 2;
      final width = (box.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: child,
              ),
            ),
        ],
      );
    },
  );
}

class _DailyStat extends StatelessWidget {
  const _DailyStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.helper,
    this.negative = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final String? helper;
  final bool negative;
  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    return _GlassPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: TextStyle(color: colors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            key: PageStorageKey('daily-stat-$label'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: negative ? colors.error : colors.ink,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(helper!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _DailyNotice extends StatelessWidget {
  const _DailyNotice({
    super.key,
    required this.message,
    this.warning = false,
    this.action,
  });
  final String message;
  final bool warning;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    final color = warning ? colors.error : colors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border.all(color: color.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  warning ? Icons.warning_amber_outlined : Icons.info_outline,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            if (action != null)
              Align(alignment: AlignmentDirectional.centerEnd, child: action!),
          ],
        ),
      ),
    );
  }
}

class _DailyAlertsPanel extends StatelessWidget {
  const _DailyAlertsPanel({required this.snapshot, required this.onNavigate});
  final WorkbenchSnapshot snapshot;
  final ValueChanged<_Section> onNavigate;
  @override
  Widget build(BuildContext context) {
    final overdue = snapshot.installmentAlerts.overdueCount;
    final dueToday = snapshot.installmentAlerts.dueTodayCount;
    final low = snapshot.products
        .where((p) => p.isActive && p.stockQty <= p.minStockQty)
        .length;
    final backup = snapshot.backupStatus;
    final backupLabel = backup.latestBackupPath == null
        ? 'لا توجد نسخة محفوظة'
        : backup.lastSuccessAt == null
        ? 'نسخة موجودة؛ وقت الحفظ غير متاح'
        : _dateTime(backup.lastSuccessAt!.toLocal());
    return _DailyGrid(
      minWidth: 190,
      maxColumns: 4,
      children: [
        _DailyAlert(
          key: const ValueKey('daily-low-stock-alert'),
          icon: Icons.inventory_2_outlined,
          label: 'أصناف ناقصة',
          value: low.toString(),
          urgent: low > 0,
          onTap: () => onNavigate(_Section.inventory),
        ),
        _DailyAlert(
          key: const ValueKey('daily-overdue-alert'),
          icon: Icons.event_busy_outlined,
          label: 'أقساط متأخرة',
          value: overdue.toString(),
          urgent: overdue > 0,
          onTap: () => onNavigate(_Section.installments),
        ),
        _DailyAlert(
          key: const ValueKey('daily-due-alert'),
          icon: Icons.event_available_outlined,
          label: 'مستحق اليوم',
          value: dueToday.toString(),
          urgent: dueToday > 0,
          onTap: () => onNavigate(_Section.installments),
        ),
        _DailyAlert(
          key: const ValueKey('daily-backup-alert'),
          icon: Icons.backup_outlined,
          label: 'آخر حفظ للنسخ',
          value: backupLabel,
          urgent: backup.latestBackupPath == null || backup.warning != null,
          onTap: () => onNavigate(_Section.backup),
        ),
      ],
    );
  }
}

class _DailyAlert extends StatelessWidget {
  const _DailyAlert({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.urgent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool urgent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    final color = urgent ? colors.error : colors.primary;
    return Semantics(
      button: true,
      child: Material(
        color: color.withValues(alpha: .07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label, style: TextStyle(color: colors.muted)),
                    ),
                    Icon(
                      Icons.chevron_left,
                      textDirection: TextDirection.ltr,
                      size: 18,
                      color: colors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailySummaryPanel extends StatelessWidget {
  const _DailySummaryPanel({required this.summary});
  final DailySummarySnapshot summary;
  @override
  Widget build(BuildContext context) => _GlassPane(
    child: ExpansionTile(
      key: const PageStorageKey('daily-summary'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('تفاصيل اليوم'),
      subtitle: const Text('حساب الربح وحركة الكاش والمحفظة'),
      children: [
        const SizedBox(height: 8),
        _DailyAmountRow('المبيعات بعد المرتجعات', summary.salesMinor),
        _DailyAmountRow('تكلفة المبيعات', summary.cogsMinor),
        _DailyAmountRow('مجمل ربح البيع', summary.tradingGrossProfitMinor),
        _DailyAmountRow('المصروفات', summary.expensesMinor),
        if (summary.inventoryVarianceMinor != 0)
          _DailyAmountRow('فروق الجرد', summary.inventoryVarianceMinor),
        if (summary.financialVarianceMinor != 0)
          _DailyAmountRow('فروق مالية موثقة', summary.financialVarianceMinor),
        if (summary.interestMinor != 0)
          _DailyAmountRow('فوائد تقسيط العملاء', summary.interestMinor),
        const Divider(height: 22),
        _DailyAmountRow('صافي ربح اليوم', summary.profitMinor, strong: true),
        const Divider(height: 22),
        _DailyAmountRow('صافي حركة الكاش', summary.cashNetMinor),
        _DailyAmountRow('صافي حركة المحفظة', summary.walletNetMinor),
        _DailyAmountRow('مشتريات دخلت المخزون', summary.purchaseMinor),
      ],
    ),
  );
}

class _DailyAmountRow extends StatelessWidget {
  const _DailyAmountRow(this.label, this.minor, {this.strong = false});
  final String label;
  final int minor;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, box) {
          final title = Text(label, style: style);
          final amount = SelectableText(
            Money(minor).format(),
            key: PageStorageKey('daily-row-$label'),
            style: style,
          );
          if (box.maxWidth < 480 * MediaQuery.textScalerOf(context).scale(1)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 4), amount],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: title),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: amount),
            ],
          );
        },
      ),
    );
  }
}

class _DailyLowStockList extends StatelessWidget {
  const _DailyLowStockList({required this.products, required this.onOpen});
  final List<Product> products;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final low = products
        .where((p) => p.isActive && p.stockQty <= p.minStockQty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تنبيه نقص المخزون',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (low.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('لا توجد أصناف ناقصة'),
          ),
        for (final product in low.take(5)) ...[
          const Divider(height: 18),
          Text(product.name, style: Theme.of(context).textTheme.titleSmall),
          Text(
            'المتاح: ${product.stockQty} • حد التنبيه: ${product.minStockQty}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (low.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('معروض أول 5 من ${low.length} صنف ناقص'),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('فتح المخزون'),
          ),
        ),
      ],
    );
  }
}

class _DailyRecentLedger extends StatelessWidget {
  const _DailyRecentLedger({required this.entries});
  final List<LedgerEntryPreview> entries;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (entries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('لا توجد قيود بعد'),
        ),
      for (final preview in entries) ...[
        const Divider(height: 18),
        Text(preview.entry.description),
        Text(
          _dateTime(preview.entry.createdAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}

class _ShiftCashDialog extends StatefulWidget {
  const _ShiftCashDialog({this.expectedCash});
  final int? expectedCash;
  @override
  State<_ShiftCashDialog> createState() => _ShiftCashDialogState();
}

class _ShiftCashDialogState extends State<_ShiftCashDialog> {
  final _cash = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _submitted = false;
  bool get closing => widget.expectedCash != null;
  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    if (_form.currentState?.validate() != true) return;
    _submitted = true;
    Navigator.pop(context, parseMoneyInput(_cash.text).minorUnits);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(closing ? 'إغلاق الوردية' : 'فتح الوردية'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              closing
                  ? 'عدّ الكاش الموجود في الدرج، واكتب المبلغ الفعلي.'
                  : 'اكتب الكاش الموجود في الدرج عند بداية الوردية.',
            ),
            if (closing) ...[
              const SizedBox(height: 12),
              const Text('المتوقع في الدرج حسب التسجيل'),
              const SizedBox(height: 4),
              SelectableText(
                Money(widget.expectedCash!).format(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('shift-cash'),
              controller: _cash,
              autofocus: true,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: closing
                    ? 'الكاش الفعلي في الدرج'
                    : 'الرصيد الافتتاحي',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText: 'بالجنيه المصري، ويمكن كتابة صفر',
                helperMaxLines: 2,
                errorMaxLines: 3,
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'اكتب المبلغ، ولو مفيش كاش اكتب صفر'
                  : _moneyInputError('المبلغ', v),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const ValueKey('shift-confirm'),
        onPressed: _submit,
        child: Text(closing ? 'إغلاق الوردية' : 'فتح الوردية'),
      ),
    ],
  );
}

class _LowStockList extends StatelessWidget {
  const _LowStockList({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final low = products
        .where((p) => p.isActive && p.stockQty <= p.minStockQty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تنبيه نقص المخزون',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: low.isEmpty
              ? const Center(child: Text('لا توجد أصناف ناقصة'))
              : ListView.separated(
                  itemCount: low.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = low[index];
                    return ListTile(
                      title: Text(product.name),
                      trailing: Text(
                        '${product.stockQty}/${product.minStockQty}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RecentLedger extends StatelessWidget {
  const _RecentLedger({required this.entries});
  final List<LedgerEntryPreview> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('آخر القيود', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('لا توجد قيود بعد'))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final preview = entries[index];
                    return ListTile(
                      dense: true,
                      title: Text(preview.entry.description),
                      subtitle: Text(_dateTime(preview.entry.createdAt)),
                      trailing: Text(Money(preview.debitMinor).format()),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
