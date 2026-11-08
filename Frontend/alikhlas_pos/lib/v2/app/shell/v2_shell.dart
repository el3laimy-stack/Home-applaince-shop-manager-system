part of '../v2_app.dart';

enum _Section {
  daily,
  pos,
  inventory,
  parties,
  purchases,
  installments,
  returns,
  reports,
  backup,
  settings,
  help,
}

enum _ReportRange { today, week, month }

enum _InstallmentTab { customers, suppliers }

enum _PartyFilter { all, customers, suppliers }

enum _InventoryFilter { all, lowStock, active, inactive }

enum _InventorySort { name, lowStockFirst, price, updated }

class _WorkbenchShell extends ConsumerStatefulWidget {
  const _WorkbenchShell();

  @override
  ConsumerState<_WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends ConsumerState<_WorkbenchShell>
    with WindowListener {
  _Section _section = _Section.daily;
  bool _financialRecoveryChecked = false;
  final _dirtyInvoices = <_Section>{};
  bool _checkingDeparture = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true).catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _recoverFinancialOperation(),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(windowManager.setPreventClose(false).catchError((_) {}));
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!await _canLeaveCurrentInvoice()) return;
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _recoverFinancialOperation() async {
    if (_financialRecoveryChecked) return;
    _financialRecoveryChecked = true;
    final useCases = ref.read(useCasesProvider);
    try {
      final pending = await useCases.pendingFinancialOperation();
      if (!mounted || pending == null) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PendingFinancialRecoveryDialog(request: pending),
      );
      if (mounted) _refresh(ref);
    } on Object {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('طلب مالي يحتاج دعمًا'),
          content: const Text(
            'تعذر قراءة طلب مالي سابق بأمان. لن ننفذه تلقائيًا. احتفظ بنسخة احتياطية وتواصل مع الدعم قبل متابعة هذه العملية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('فهمت'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(currentOwnerProvider)!;
    final workbench = ref.watch(workbenchProvider);

    return _GlassStage(
      background: workbench.asData?.value.uiBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _SideNav(
                selected: _section,
                compact: MediaQuery.sizeOf(context).width < 1200,
                onSelect: (section) {
                  _requestSection(section);
                },
                onLogout: () {
                  _requestLogout();
                },
                owner: owner,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: workbench.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      _GlassPane(child: Center(child: Text('$error'))),
                  data: (snapshot) => Column(
                    children: [
                      if (snapshot.backupStatus.warning != null)
                        MaterialBanner(
                          content: Text(snapshot.backupStatus.warning!),
                          actions: [
                            TextButton(
                              onPressed: () => _requestSection(_Section.backup),
                              child: const Text('إعداد النسخ'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: _WorkbenchContent(
                          section: _section,
                          snapshot: snapshot,
                          onNavigate: _requestSection,
                          onSaleDirtyChanged: (dirty) =>
                              _setInvoiceDirty(_Section.pos, dirty),
                          onPurchaseDirtyChanged: (dirty) =>
                              _setInvoiceDirty(_Section.purchases, dirty),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setInvoiceDirty(_Section section, bool dirty) {
    if (dirty) {
      _dirtyInvoices.add(section);
    } else {
      _dirtyInvoices.remove(section);
    }
  }

  Future<void> _requestSection(_Section target) async {
    if (target == _section) return;
    if (!await _canLeaveCurrentInvoice()) return;
    if (!mounted) return;
    setState(() => _section = target);
  }

  Future<void> _requestLogout() async {
    if (!await _canLeaveCurrentInvoice()) return;
    if (!mounted) return;
    ref.read(currentOwnerProvider.notifier).setOwner(null);
  }

  Future<bool> _canLeaveCurrentInvoice() async {
    if (_checkingDeparture) return false;
    if (!_dirtyInvoices.contains(_section)) return true;
    _checkingDeparture = true;
    try {
      if (_section == _Section.pos || _section == _Section.purchases) {
        try {
          final saved = await ref
              .read(invoiceDepartureProvider)
              .flush(_section == _Section.pos ? 'sale' : 'purchase');
          if (!mounted) return false;
          if (saved) {
            _dirtyInvoices.remove(_section);
            return true;
          }
        } catch (_) {
          if (!mounted) return false;
          _showSnack(
            context,
            'تعذر حفظ المسودة. ارجع وأعد المحاولة أو أكد مغادرة التعديلات غير المحفوظة.',
          );
        }
      }
      final invoice = _section == _Section.purchases ? 'الشراء' : 'البيع';
      final leave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('فاتورة $invoice غير محفوظة'),
          content: Text(
            'التغييرات الحالية ستضيع. ارجع واختر «حفظ مسودة» إذا أردت استعادتها لاحقًا.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('العودة للفاتورة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('مغادرة دون حفظ'),
            ),
          ],
        ),
      );
      if (leave == true) {
        _dirtyInvoices.remove(_section);
        return true;
      }
      return false;
    } finally {
      _checkingDeparture = false;
    }
  }
}

class _PendingFinancialRecoveryDialog extends ConsumerStatefulWidget {
  const _PendingFinancialRecoveryDialog({required this.request});

  final PendingFinancialOperation request;

  @override
  ConsumerState<_PendingFinancialRecoveryDialog> createState() =>
      _PendingFinancialRecoveryDialogState();
}

class _PendingFinancialRecoveryDialogState
    extends ConsumerState<_PendingFinancialRecoveryDialog> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تحقق من طلب مالي سابق'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الطلب: ${widget.request.label}'),
            const SizedBox(height: 8),
            const Text(
              'لم يكتمل تأكيد النتيجة قبل إغلاق التطبيق. لن نسجل حركة جديدة؛ سنراجع الطلب نفسه فقط.',
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: const TextStyle(color: V2DesignTokens.rose),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _discard,
          child: const Text('إلغاء الطلب غير المحفوظ'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _retry,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_busy ? 'جاري التحقق...' : 'التحقق وإعادة المحاولة'),
        ),
      ],
    );
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final useCases = ref.read(useCasesProvider);
    try {
      final result = await _runWithNegativeBalanceApproval(
        context,
        action: (allowNegativeBalance) => _submitPendingFinancialOperation(
          useCases,
          widget.request,
          allowNegativeBalance: allowNegativeBalance,
        ),
        onConfirmationDeclined: () =>
            useCases.discardUncommittedPendingFinancialOperation(
              widget.request.operationKey,
            ),
      );
      if (!mounted) return;
      switch (result) {
        case AppSuccess<int>():
          Navigator.pop(context);
        case AppConfirmationRequired<int>():
          Navigator.pop(context);
        case AppFailure<int>(message: final message):
          setState(() => _message = message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final discarded = await ref
          .read(useCasesProvider)
          .discardUncommittedPendingFinancialOperation(
            widget.request.operationKey,
          );
      if (!mounted) return;
      if (discarded) {
        Navigator.pop(context);
      } else {
        setState(
          () => _message =
              'لا يمكن الإلغاء لأن العملية حُفظت بالفعل. استخدم التحقق لإظهار نتيجتها.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.selected,
    required this.onSelect,
    required this.onLogout,
    required this.owner,
    this.compact = false,
  });
  final _Section selected;
  final ValueChanged<_Section> onSelect;
  final VoidCallback onLogout;
  final User owner;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_Section.daily, Icons.space_dashboard, 'اليومية'),
      (_Section.pos, Icons.point_of_sale, 'البيع'),
      (_Section.purchases, Icons.local_shipping, 'المشتريات'),
      (_Section.returns, Icons.receipt_long, 'الفواتير والمرتجعات'),
      (_Section.inventory, Icons.inventory_2, 'المخزون'),
      (_Section.parties, Icons.people_alt, 'العملاء والموردون'),
      (_Section.installments, Icons.payments, 'الأقساط'),
      (_Section.reports, Icons.query_stats, 'التقارير'),
      (_Section.backup, Icons.backup, 'النسخ الاحتياطي'),
      (_Section.settings, Icons.settings, 'الإعدادات'),
    ];
    Widget item(_Section section, IconData icon, String label) => compact
        ? Tooltip(
            message: label,
            child: IconButton(
              isSelected: selected == section,
              icon: Icon(icon),
              onPressed: () => onSelect(section),
            ),
          )
        : _NavButton(
            selected: selected == section,
            icon: icon,
            label: label,
            onTap: () => onSelect(section),
          );
    return _GlassPane(
      width: compact ? 72 : 210,
      padding: EdgeInsets.all(compact ? 8 : 14),
      enableBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            IconButton(
              tooltip: 'فتح قائمة الشاشات',
              icon: const Icon(Icons.menu),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (c) => Dialog(
                    child: SizedBox(
                      height: MediaQuery.sizeOf(c).height * .9,
                      child: _SideNav(
                        selected: selected,
                        owner: owner,
                        onSelect: (section) {
                          Navigator.pop(c);
                          onSelect(section);
                        },
                        onLogout: () {
                          Navigator.pop(c);
                          onLogout();
                        },
                      ),
                    ),
                  ),
                );
              },
            )
          else ...[
            Text('إخلاص POS', style: Theme.of(context).textTheme.headlineSmall),
            Text(
              owner.fullName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: ListView(
              key: const ValueKey('side-navigation-scroll'),
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (!compact && (i == 0 || i == 4 || i == 8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        i == 0
                            ? 'العمل اليومي'
                            : i == 4
                            ? 'إدارة المحل'
                            : 'الإعدادات والمساعدة',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  item(items[i].$1, items[i].$2, items[i].$3),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _ThemeModeControl(compact: true),
          if (compact) ...[
            Tooltip(
              message: 'المساعدة',
              child: IconButton(
                onPressed: () => onSelect(_Section.help),
                icon: const Icon(Icons.help_outline),
              ),
            ),
            Tooltip(
              message: 'خروج',
              child: IconButton(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => onSelect(_Section.help),
              icon: const Icon(Icons.help_outline),
              label: const Text('المساعدة'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('خروج'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: selected
          ? LiquidGlassColors.of(context).selected
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected
            ? LiquidGlassColors.of(context).stroke
            : Colors.transparent,
      ),
      boxShadow: selected ? [V2DesignTokens.softControlShadow] : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: V2DesignTokens.space8),
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkbenchContent extends StatelessWidget {
  const _WorkbenchContent({
    required this.section,
    required this.snapshot,
    required this.onSaleDirtyChanged,
    required this.onPurchaseDirtyChanged,
    required this.onNavigate,
  });

  final _Section section;
  final WorkbenchSnapshot snapshot;
  final ValueChanged<bool> onSaleDirtyChanged;
  final ValueChanged<bool> onPurchaseDirtyChanged;
  final ValueChanged<_Section> onNavigate;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      _Section.daily => _DailyView(snapshot: snapshot, onNavigate: onNavigate),
      _Section.pos => _PosView(
        snapshot: snapshot,
        onDirtyChanged: onSaleDirtyChanged,
      ),
      _Section.inventory => _InventoryView(snapshot: snapshot),
      _Section.parties => _PartiesView(snapshot: snapshot),
      _Section.purchases => _PurchaseView(
        snapshot: snapshot,
        onDirtyChanged: onPurchaseDirtyChanged,
      ),
      _Section.installments => _InstallmentsView(snapshot: snapshot),
      _Section.returns => _ReturnsView(snapshot: snapshot),
      _Section.reports => _ReportsView(snapshot: snapshot),
      _Section.backup => _BackupView(snapshot: snapshot),
      _Section.settings => _SettingsView(snapshot: snapshot),
      _Section.help => _HelpView(snapshot: snapshot),
    };
  }
}
