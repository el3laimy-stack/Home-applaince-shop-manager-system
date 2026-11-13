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
                        if (dashboard.openShift == null)
                          FutureBuilder<Shift?>(
                            future: ref
                                .read(useCasesProvider)
                                .latestClosedShift(),
                            builder: (context, snapshot) {
                              final shift = snapshot.data;
                              if (shift == null ||
                                  shift.differenceMinor == null ||
                                  shift.expectedCashMinor == null ||
                                  shift.actualCashMinor == null)
                                return const SizedBox.shrink();
                              final difference = shift.differenceMinor!;
                              final label = difference == 0
                                  ? 'بلا فرق'
                                  : '${difference < 0 ? 'عجز' : 'زيادة'} ${Money(difference.abs()).format()}';
                              return Text(
                                'آخر وردية مغلقة: المتوقع ${Money(shift.expectedCashMinor ?? 0).format()}، الفعلي ${Money(shift.actualCashMinor ?? 0).format()}، $label',
                              );
                            },
                          ),
                        TextButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => _ShiftHistoryDialog(
                              useCases: ref.read(useCasesProvider),
                            ),
                          ),
                          icon: const Icon(Icons.history),
                          label: const Text('سجل الورديات'),
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
              FutureBuilder<bool>(
                future: ref
                    .read(useCasesProvider)
                    .recoveryCodeNeedsConfirmation(),
                builder: (context, state) => state.data == true
                    ? _DailyNotice(
                        message:
                            'لم يؤكَّد حفظ رمز الاستعادة. إذا فقدته، أنشئ رمزًا جديدًا بكلمة المرور.',
                        warning: true,
                        action: TextButton(
                          onPressed: () async {
                            await showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _ReissueRecoveryDialog(
                                useCases: ref.read(useCasesProvider),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                          child: const Text('إعداد رمز الاستعادة'),
                        ),
                      )
                    : const SizedBox.shrink(),
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
      final difference = amount - expectedCash;
      if (difference != 0) {
        final label = difference < 0 ? 'عجز' : 'زيادة';
        final approved = await _confirm(
          context,
          title: 'مراجعة فرق الوردية',
          message:
              'المتوقع ${Money(expectedCash).format()}، والفعلي ${Money(amount).format()}، والفرق $label ${Money(difference.abs()).format()}. هل تريد إغلاق الوردية؟',
        );
        if (!approved || !context.mounted) return;
      }
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
          reviewedShiftId: widget.snapshot.dashboard.openShift?.id,
          reviewedExpectedCashMinor: expectedCash,
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

class _ShiftHistoryDialog extends StatefulWidget {
  const _ShiftHistoryDialog({required this.useCases});
  final V2UseCases useCases;
  @override
  State<_ShiftHistoryDialog> createState() => _ShiftHistoryDialogState();
}

class _ShiftHistoryDialogState extends State<_ShiftHistoryDialog> {
  int _page = 0;
  late Future<List<Shift>> _rows = _fetch();
  Future<List<Shift>> _fetch() =>
      widget.useCases.closedShiftHistory(offset: _page * 20);
  void _move(int delta) => setState(() {
    _page += delta;
    _rows = _fetch();
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('سجل الورديات المغلقة'),
    content: SizedBox(
      width: 650,
      height: 400,
      child: FutureBuilder<List<Shift>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(child: Text('تعذر تحميل سجل الورديات.'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty)
            return const Center(child: Text('لا توجد ورديات مغلقة.'));
          return ListView.builder(
            itemCount: math.min(20, rows.length),
            itemBuilder: (context, index) {
              final shift = rows[index];
              final diff = shift.differenceMinor;
              final difference = diff == null
                  ? 'غير متاح'
                  : diff == 0
                  ? 'بلا فرق'
                  : '${diff < 0 ? 'عجز' : 'زيادة'} ${Money(diff.abs()).format()}';
              return ListTile(
                title: Text(
                  'فتح ${_dateTime(shift.openedAt)} • إغلاق ${shift.closedAt == null ? 'غير متاح' : _dateTime(shift.closedAt!)}',
                ),
                subtitle: Text(
                  'المتوقع ${shift.expectedCashMinor == null ? 'غير متاح' : Money(shift.expectedCashMinor!).format()} • الفعلي ${shift.actualCashMinor == null ? 'غير متاح' : Money(shift.actualCashMinor!).format()} • $difference',
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _page == 0 ? null : () => _move(-1),
        child: const Text('السابق'),
      ),
      FutureBuilder<List<Shift>>(
        future: _rows,
        builder: (context, snapshot) => TextButton(
          onPressed: (snapshot.data?.length ?? 0) > 20 ? () => _move(1) : null,
          child: const Text('التالي'),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
    ],
  );
}

class _ReissueRecoveryDialog extends StatefulWidget {
  const _ReissueRecoveryDialog({required this.useCases});
  final V2UseCases useCases;
  @override
  State<_ReissueRecoveryDialog> createState() => _ReissueRecoveryDialogState();
}

class _ReissueRecoveryDialogState extends State<_ReissueRecoveryDialog> {
  final _password = TextEditingController();
  OwnerRecovery? _recovery;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _issue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.useCases.reissueUnconfirmedRecoveryCode(
        _password.text,
      );
      if (!mounted) return;
      switch (result) {
        case AppSuccess<OwnerRecovery>(value: final recovery):
          setState(() {
            _recovery = recovery;
            _password.clear();
          });
        case AppFailure<OwnerRecovery>(message: final message):
          setState(() => _error = message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إصدار الرمز. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final recovery = _recovery;
    if (recovery == null || _busy) return;
    if (!await _confirmRecoveryCode(context, recovery.recoveryCode) || !mounted)
      return;
    setState(() => _busy = true);
    try {
      final saved = await widget.useCases.confirmRecoveryCodeSaved(
        recovery.recoveryCode,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => _error = 'تعذر تأكيد الرمز.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تأكيد الرمز.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _recovery == null,
    child: AlertDialog(
      title: const Text('إعداد رمز الاستعادة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recovery == null) ...[
            const Text(
              'أدخل كلمة مرور المالك لإصدار رمز جديد. سيُلغى الرمز السابق.',
            ),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
            ),
          ] else ...[
            const Text('احتفظ بالرمز خارج الجهاز، ثم أكّد حفظه.'),
            SelectableText(
              _recovery!.recoveryCode,
              key: const ValueKey('reissued-recovery-code'),
              textDirection: TextDirection.ltr,
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        if (_recovery == null)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('لاحقًا'),
          ),
        FilledButton(
          onPressed: _busy ? null : (_recovery == null ? _issue : _finish),
          child: Text(_recovery == null ? 'إصدار رمز جديد' : 'حفظت الرمز'),
        ),
      ],
    ),
  );
}
