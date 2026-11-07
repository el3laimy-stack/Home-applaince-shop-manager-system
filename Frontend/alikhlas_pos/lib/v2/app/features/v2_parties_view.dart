part of '../v2_app.dart';

class _PartiesView extends ConsumerStatefulWidget {
  const _PartiesView({required this.snapshot});
  final WorkbenchSnapshot snapshot;

  @override
  ConsumerState<_PartiesView> createState() => _PartiesViewState();
}

class _PartiesViewState extends ConsumerState<_PartiesView> {
  final _search = TextEditingController();
  _PartyFilter _filter = _PartyFilter.all;
  String? _selectedKey;
  bool _quickPaymentInProgress = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parties = _filteredParties();
    final selected = _selectedParty(parties);
    return _Screen(
      title: 'العملاء والموردون',
      subtitle: 'حساب كامل لكل طرف: كشف، فواتير، أقساط، وتحصيل سريع',
      trailing: Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => _openPartyDialog(context, ref, isCustomer: true),
            icon: const Icon(Icons.person_add),
            label: const Text('عميل'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openPartyDialog(context, ref, isCustomer: false),
            icon: const Icon(Icons.add_business),
            label: const Text('مورد'),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final detail = selected == null
              ? const _GlassPane(
                  child: Center(child: Text('اختر عميلًا أو موردًا')),
                )
              : _PartyDetailPanel(
                  party: selected,
                  plans: widget.snapshot.installmentSummaries
                      .where(
                        (item) =>
                            item.plan.partyType == selected.type &&
                            item.plan.partyId == selected.id,
                      )
                      .toList(),
                  statementFuture: ref
                      .read(useCasesProvider)
                      .partyStatement(
                        partyType: selected.type,
                        partyId: selected.id,
                      ),
                  onStatement: () => _openStatement(context, ref, selected),
                  onQuickPayment: () =>
                      _openQuickPayment(context, ref, selected),
                );
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (constraints.maxWidth < 960 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _pickParty,
                    icon: const Icon(Icons.people_outline),
                    label: const Text('اختيار عميل أو مورد'),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: detail),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(
                width: (constraints.maxWidth * 0.34).clamp(320.0, 380.0),
                child: _directory(
                  parties: parties,
                  selected: selected,
                  onChanged: () => setState(() {}),
                  onSelected: (party) =>
                      setState(() => _selectedKey = _partyKey(party)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }

  Widget _directory({
    required List<PartyBalance> parties,
    required PartyBalance? selected,
    required VoidCallback onChanged,
    required ValueChanged<PartyBalance> onSelected,
  }) => _GlassPane(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'بحث باسم أو هاتف',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        SegmentedButton<_PartyFilter>(
          selected: {_filter},
          onSelectionChanged: (selection) {
            _filter = selection.first;
            onChanged();
          },
          segments: const [
            ButtonSegment(
              value: _PartyFilter.all,
              label: Text('الكل'),
              icon: Icon(Icons.groups),
            ),
            ButtonSegment(
              value: _PartyFilter.customers,
              label: Text('عملاء'),
              icon: Icon(Icons.people),
            ),
            ButtonSegment(
              value: _PartyFilter.suppliers,
              label: Text('موردين'),
              icon: Icon(Icons.local_shipping),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: parties.isEmpty
              ? const Center(child: Text('لا توجد أطراف مطابقة'))
              : ListView.separated(
                  itemCount: parties.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final party = parties[index];
                    return _PartyDirectoryTile(
                      party: party,
                      selected:
                          _partyKey(party) ==
                          (selected == null ? null : _partyKey(selected)),
                      onTap: () => onSelected(party),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Future<void> _pickParty() async {
    final party = await showDialog<PartyBalance>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(dialogContext).height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 20,
                  end: 8,
                  top: 8,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('اختيار عميل أو مورد')),
                    CloseButton(onPressed: () => Navigator.pop(dialogContext)),
                  ],
                ),
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, updateDialog) {
                    final parties = _filteredParties();
                    return _directory(
                      parties: parties,
                      selected: _selectedParty(parties),
                      onChanged: () => updateDialog(() {}),
                      onSelected: (party) =>
                          Navigator.pop(dialogContext, party),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (party != null) _selectedKey = _partyKey(party);
    });
  }

  List<PartyBalance> _filteredParties() {
    final query = _search.text.trim();
    final parties =
        [
          ...widget.snapshot.customerBalances,
          ...widget.snapshot.supplierBalances,
        ].where((party) {
          final typeMatch = switch (_filter) {
            _PartyFilter.all => true,
            _PartyFilter.customers => party.type == 'customer',
            _PartyFilter.suppliers => party.type == 'supplier',
          };
          final queryMatch =
              query.isEmpty ||
              party.name.contains(query) ||
              (party.phone?.contains(query) ?? false);
          return typeMatch && queryMatch;
        }).toList();
    parties.sort((a, b) {
      if (a.type != b.type) return a.type == 'customer' ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return parties;
  }

  PartyBalance? _selectedParty(List<PartyBalance> parties) {
    if (parties.isEmpty) return null;
    for (final party in parties) {
      if (_partyKey(party) == _selectedKey) return party;
    }
    return parties.first;
  }

  Future<void> _openPartyDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool isCustomer,
  }) async {
    final data = await showDialog<_PartyFormData>(
      context: context,
      builder: (_) =>
          _PartyDialog(title: isCustomer ? 'عميل جديد' : 'مورد جديد'),
    );
    if (data == null || !context.mounted) return;
    final result = isCustomer
        ? await ref
              .read(useCasesProvider)
              .createCustomer(name: data.name, phone: data.phone)
        : await ref
              .read(useCasesProvider)
              .createSupplier(name: data.name, phone: data.phone);
    if (!context.mounted) return;
    _showResult(
      context,
      result,
      success: isCustomer ? 'تمت إضافة العميل' : 'تمت إضافة المورد',
    );
    _refresh(ref);
  }

  Future<void> _openStatement(
    BuildContext context,
    WidgetRef ref,
    PartyBalance party,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PartyStatementDialog(
        party: party,
        settings: widget.snapshot.shopSettings,
        statementFuture: ref
            .read(useCasesProvider)
            .partyStatement(partyType: party.type, partyId: party.id),
      ),
    );
  }

  Future<void> _openQuickPayment(
    BuildContext context,
    WidgetRef ref,
    PartyBalance party,
  ) async {
    if (_quickPaymentInProgress) return;
    setState(() => _quickPaymentInProgress = true);
    try {
      final plans = widget.snapshot.installmentSummaries
          .where(
            (item) =>
                item.plan.partyType == party.type &&
                item.plan.partyId == party.id,
          )
          .toList();
      if (plans.isEmpty) {
        _showSnack(context, 'لا توجد خطط أقساط مفتوحة لهذا الحساب');
        return;
      }
      final payment =
          await showDialog<
            ({InstallmentPlanPreview plan, int amount, PaymentMethod method})
          >(
            context: context,
            builder: (_) => _QuickInstallmentDialog(party: party, plans: plans),
          );
      if (payment == null || !context.mounted) return;
      final useCases = ref.read(useCasesProvider);
      final operationKey = useCases.newInstallmentOperationKey();
      final request = party.type == 'customer'
          ? PendingFinancialOperation.customerInstallment(
              operationKey: operationKey,
              planId: payment.plan.plan.id,
              amountMinor: payment.amount,
              method: payment.method,
            )
          : PendingFinancialOperation.supplierInstallment(
              operationKey: operationKey,
              planId: payment.plan.plan.id,
              amountMinor: payment.amount,
              method: payment.method,
            );
      final result = await _runWithNegativeBalanceApproval(
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
      _showResult(context, result, success: 'تم تسجيل الحركة');
      _refresh(ref);
    } finally {
      if (mounted) setState(() => _quickPaymentInProgress = false);
    }
  }
}

String _partyKey(PartyBalance party) => '${party.type}:${party.id}';
