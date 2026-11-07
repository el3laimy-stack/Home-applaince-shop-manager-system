part of '../v2_app.dart';

class _DailyView extends ConsumerStatefulWidget {
  const _DailyView({required this.snapshot, required this.onNavigate});
  final WorkbenchSnapshot snapshot;
  final ValueChanged<_Section> onNavigate;

  @override
  ConsumerState<_DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends ConsumerState<_DailyView> {
  bool _shiftSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.snapshot.dashboard;
    final summary = widget.snapshot.dailySummary;
    return _Screen(
      title: 'يومية المحل',
      subtitle: dashboard.openShift == null
          ? 'ابدأ وردية جديدة قبل أي حركة كاش'
          : 'وردية مفتوحة منذ ${_time(dashboard.openShift!.openedAt)}',
      trailing: Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: dashboard.openShift == null && !_shiftSubmitting
                ? () => _openShift(context, ref)
                : null,
            icon: const Icon(Icons.lock_open),
            label: const Text('فتح وردية'),
          ),
          OutlinedButton.icon(
            onPressed: dashboard.openShift == null || _shiftSubmitting
                ? null
                : () => _closeShift(
                    context,
                    ref,
                    dashboard.expectedOpenShiftCashMinor ?? 0,
                  ),
            icon: const Icon(Icons.lock),
            label: const Text('إغلاق وردية'),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            if (dashboard.openShift?.cashDeltaBeforeUpgradeMinor != null)
              const Text(
                'هذه الوردية بدأت بإصدار سابق؛ راجع النقد الفعلي قبل الإغلاق.',
              ),
            _GlassPane(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => widget.onNavigate(_Section.pos),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('بيع جديد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.purchases),
                    icon: const Icon(Icons.local_shipping),
                    label: const Text('شراء جديد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.installments),
                    icon: const Icon(Icons.payments),
                    label: const Text('تحصيل قسط'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.returns),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('فواتير المحل'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
              title: const Text('أرصدة المحل والتفاصيل المالية'),
              children: [
                _MetricsGrid(
                  metrics: [
                    ('الخزينة', dashboard.cashMinor, Icons.payments),
                    (
                      'المحفظة',
                      dashboard.walletMinor,
                      Icons.account_balance_wallet,
                    ),
                    ('أرصدة العملاء', dashboard.receivablesMinor, Icons.people),
                    (
                      'أرصدة الموردين',
                      -dashboard.payablesMinor,
                      Icons.local_shipping,
                    ),
                    (
                      'قيمة المخزون',
                      dashboard.inventoryMinor,
                      Icons.inventory_2,
                    ),
                    (
                      'صافي الربح',
                      dashboard.grossProfitMinor,
                      Icons.trending_up,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DailyAlertsPanel(snapshot: widget.snapshot),
            const SizedBox(height: 14),
            _DailySummaryPanel(summary: summary),
            const SizedBox(height: 14),
            SizedBox(
              height: 320,
              child: Row(
                children: [
                  Expanded(
                    child: _GlassPane(
                      child: _RecentLedger(
                        entries: widget.snapshot.recentLedger,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _GlassPane(
                      child: _LowStockList(products: widget.snapshot.products),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShift(BuildContext context, WidgetRef ref) async {
    if (_shiftSubmitting) return;
    setState(() => _shiftSubmitting = true);
    try {
      final amount = await _askMoney(context, title: 'رصيد افتتاحي');
      if (amount == null || !context.mounted) return;
      final useCases = ref.read(useCasesProvider);
      final result = await _submitPendingFinancialOperation(
        useCases,
        PendingFinancialOperation.openShift(
          operationKey: useCases.newShiftOperationKey(),
          openingCashMinor: amount,
        ),
        allowNegativeBalance: false,
      );
      if (!context.mounted) return;
      _showResult(context, result, success: 'تم فتح الوردية');
      _refresh(ref);
    } finally {
      if (mounted) setState(() => _shiftSubmitting = false);
    }
  }

  Future<void> _closeShift(
    BuildContext context,
    WidgetRef ref,
    int expectedCash,
  ) async {
    if (_shiftSubmitting) return;
    setState(() => _shiftSubmitting = true);
    try {
      final amount = await _askMoney(
        context,
        title: 'الكاش الفعلي في الدرج',
        initialMinor: expectedCash,
      );
      if (amount == null || !context.mounted) return;
      final useCases = ref.read(useCasesProvider);
      final result = await _submitPendingFinancialOperation(
        useCases,
        PendingFinancialOperation.closeShift(
          operationKey: useCases.newShiftOperationKey(),
          actualCashMinor: amount,
        ),
        allowNegativeBalance: false,
      );
      if (!context.mounted) return;
      _showResult(context, result, success: 'تم إغلاق الوردية');
      _refresh(ref);
    } finally {
      if (mounted) setState(() => _shiftSubmitting = false);
    }
  }
}
