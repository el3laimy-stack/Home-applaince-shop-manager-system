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
  bool _shiftDialogOpen = false;
  bool get _shiftBusy => _shiftSubmitting || _shiftDialogOpen;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final dashboard = snapshot.dashboard;
    final summary = snapshot.dailySummary;
    final colors = LiquidGlassColors.of(context);
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: SingleChildScrollView(
          key: const PageStorageKey('daily-page-scroll'),
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GlassPane(
                enableBlur: true,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final identity = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'يومية المحل',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${snapshot.shopSettings.shopName} • ${snapshot.shopSettings.branchName}',
                          style: TextStyle(color: colors.muted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'اليوم • ${_date(summary.date)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                    final shift = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dashboard.openShift == null
                              ? 'الوردية مغلقة'
                              : 'وردية مفتوحة • ${_time(dashboard.openShift!.openedAt)}',
                          style: TextStyle(color: colors.muted),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          key: const ValueKey('daily-shift-action'),
                          onPressed: _shiftBusy
                              ? null
                              : () => dashboard.openShift == null
                                    ? _openShift(context, ref)
                                    : _closeShift(
                                        context,
                                        ref,
                                        dashboard.expectedOpenShiftCashMinor ??
                                            0,
                                      ),
                          icon: _shiftSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  dashboard.openShift == null
                                      ? Icons.lock_open
                                      : Icons.lock_outline,
                                ),
                          label: Text(
                            _shiftSubmitting
                                ? 'جارٍ التأكيد...'
                                : dashboard.openShift == null
                                ? 'فتح وردية'
                                : 'إغلاق وردية',
                          ),
                        ),
                      ],
                    );
                    if (box.maxWidth <
                        650 * MediaQuery.textScalerOf(context).scale(1)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [identity, const SizedBox(height: 12), shift],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 20),
                        shift,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _DailyGrid(
                minWidth: 155,
                maxColumns: 4,
                children: [
                  FilledButton.icon(
                    onPressed: () => widget.onNavigate(_Section.pos),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('بيع جديد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.purchases),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('شراء جديد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.returns),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('فواتير المحل'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate(_Section.installments),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('تحصيل قسط'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DailyGrid(
                minWidth: 220,
                maxColumns: 3,
                children: [
                  _DailyStat(
                    key: const ValueKey('daily-sales'),
                    label: 'مبيعات اليوم',
                    value: Money(summary.salesMinor).format(),
                    helper: 'صافي المبيعات بعد المرتجعات',
                    icon: Icons.receipt_long_outlined,
                  ),
                  _DailyStat(
                    key: const ValueKey('daily-profit'),
                    label: 'صافي ربح اليوم',
                    value: Money(summary.profitMinor).format(),
                    helper: 'تفاصيل الحساب موضحة بالأسفل',
                    icon: Icons.trending_up,
                    negative: summary.profitMinor < 0,
                  ),
                  _DailyStat(
                    key: const ValueKey('daily-invoices'),
                    label: 'فواتير البيع اليوم',
                    value: summary.saleCount.toString(),
                    helper:
                        'شراء: ${summary.purchaseCount} • مرتجعات: ${summary.returnCount}',
                    icon: Icons.shopping_bag_outlined,
                  ),
                ],
              ),
              if (dashboard.openShift == null) ...[
                const SizedBox(height: 14),
                const _DailyNotice(
                  message:
                      'افتح وردية قبل تسجيل بيع أو تحصيل نقدي. تقدر تراجع المخزون والفواتير في أي وقت.',
                ),
              ],
              if (dashboard.openShift?.cashDeltaBeforeUpgradeMinor != null) ...[
                const SizedBox(height: 14),
                const _DailyNotice(
                  message:
                      'هذه الوردية بدأت بإصدار سابق؛ راجع النقد الفعلي قبل الإغلاق.',
                  warning: true,
                ),
              ],
              if (snapshot.backupStatus.warning != null) ...[
                const SizedBox(height: 14),
                _DailyNotice(
                  key: const ValueKey('daily-backup-warning'),
                  message: snapshot.backupStatus.warning!,
                  warning: true,
                  action: TextButton(
                    onPressed: () => widget.onNavigate(_Section.backup),
                    child: const Text('إعداد النسخ'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _DailyAlertsPanel(
                snapshot: snapshot,
                onNavigate: widget.onNavigate,
              ),
              const SizedBox(height: 14),
              _DailySummaryPanel(summary: summary),
              const SizedBox(height: 12),
              _GlassPane(
                child: ExpansionTile(
                  key: const PageStorageKey('daily-balances'),
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('أرصدة المحل الحالية'),
                  subtitle: const Text('أرصدة حالية، والربح من بداية التسجيل'),
                  children: [
                    const SizedBox(height: 12),
                    _DailyGrid(
                      minWidth: 220,
                      maxColumns: 3,
                      children: [
                        _DailyStat(
                          label: 'الخزينة',
                          value: Money(dashboard.cashMinor).format(),
                          icon: Icons.payments_outlined,
                        ),
                        _DailyStat(
                          label: 'المحفظة',
                          value: Money(dashboard.walletMinor).format(),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        _DailyStat(
                          label: 'أرصدة العملاء',
                          value: Money(dashboard.receivablesMinor).format(),
                          icon: Icons.people_outline,
                        ),
                        _DailyStat(
                          label: 'أرصدة الموردين',
                          value: Money(-dashboard.payablesMinor).format(),
                          icon: Icons.local_shipping_outlined,
                        ),
                        _DailyStat(
                          label: 'قيمة المخزون بالتكلفة',
                          value: Money(dashboard.inventoryMinor).format(),
                          icon: Icons.inventory_2_outlined,
                        ),
                        _DailyStat(
                          label: 'صافي الربح التراكمي',
                          value: Money(dashboard.profitMinor).format(),
                          icon: Icons.trending_up,
                          negative: dashboard.profitMinor < 0,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _GlassPane(
                child: _DailyLowStockList(
                  products: snapshot.products,
                  onOpen: () => widget.onNavigate(_Section.inventory),
                ),
              ),
              const SizedBox(height: 12),
              _GlassPane(
                child: ExpansionTile(
                  key: const PageStorageKey('daily-ledger'),
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('سجل القيود المحاسبية'),
                  subtitle: const Text('آخر العمليات المسجلة محاسبيًا'),
                  children: [
                    _DailyRecentLedger(entries: snapshot.recentLedger),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openShift(BuildContext context, WidgetRef ref) async {
    if (_shiftBusy) return;
    setState(() => _shiftDialogOpen = true);
    try {
      final amount = await showDialog<int>(
        context: context,
        builder: (_) => const _ShiftCashDialog(),
      );
      if (amount == null || !context.mounted) return;
      setState(() {
        _shiftDialogOpen = false;
        _shiftSubmitting = true;
      });
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
    } catch (_) {
      if (context.mounted) {
        _showSnack(
          context,
          'تعذر تأكيد نتيجة الوردية. أعد فتح التطبيق للتحقق من الطلب السابق دون تسجيله مرة أخرى.',
        );
        _refresh(ref);
      }
    } finally {
      if (mounted) {
        setState(() {
          _shiftDialogOpen = false;
          _shiftSubmitting = false;
        });
      }
    }
  }

  Future<void> _closeShift(
    BuildContext context,
    WidgetRef ref,
    int expectedCash,
  ) async {
    if (_shiftBusy) return;
    setState(() => _shiftDialogOpen = true);
    try {
      final amount = await showDialog<int>(
        context: context,
        builder: (_) => _ShiftCashDialog(expectedCash: expectedCash),
      );
      if (amount == null || !context.mounted) return;
      setState(() {
        _shiftDialogOpen = false;
        _shiftSubmitting = true;
      });
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
    } catch (_) {
      if (context.mounted) {
        _showSnack(
          context,
          'تعذر تأكيد نتيجة الوردية. أعد فتح التطبيق للتحقق من الطلب السابق دون تسجيله مرة أخرى.',
        );
        _refresh(ref);
      }
    } finally {
      if (mounted) {
        setState(() {
          _shiftDialogOpen = false;
          _shiftSubmitting = false;
        });
      }
    }
  }
}
