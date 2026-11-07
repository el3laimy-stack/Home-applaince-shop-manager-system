part of '../v2_use_cases.dart';

extension V2ReportUseCaseHelpers on V2UseCases {
  Future<DailySummarySnapshot> _dailySummary(DateTime date) async {
    final start = _dayStart(date);
    final report = await _periodReport(
      start,
      start.add(const Duration(days: 1)),
    );
    return DailySummarySnapshot(
      date: start,
      salesMinor: report.salesMinor,
      cogsMinor: report.cogsMinor,
      expensesMinor: report.expensesMinor,
      inventoryVarianceMinor: report.inventoryVarianceMinor,
      financialVarianceMinor: report.financialVarianceMinor,
      interestMinor: report.interestMinor,
      cashNetMinor: report.cashNetMinor,
      walletNetMinor: report.walletNetMinor,
      purchaseMinor: report.purchaseMinor,
      saleCount: report.saleCount,
      purchaseCount: report.purchaseCount,
      returnCount: report.returnCount,
    );
  }

  Future<PeriodReportSnapshot> _periodReport(
    DateTime start,
    DateTime end,
  ) async {
    final salesMinor = subtractMinor(
      0,
      await _accountNetBetween(AccountCodes.sales, start, end),
    );
    final cogsMinor = await _accountNetBetween(AccountCodes.cogs, start, end);
    final expensesMinor = await _accountNetBetween(
      AccountCodes.expenses,
      start,
      end,
    );
    final inventoryVarianceMinor = await _accountNetBetween(
      AccountCodes.inventoryVariance,
      start,
      end,
    );
    final financialVarianceMinor = await _accountNetBetween(
      AccountCodes.financialVariance,
      start,
      end,
    );
    final interestMinor = subtractMinor(
      0,
      await _accountNetBetween(AccountCodes.interestIncome, start, end),
    );
    final purchaseMinor = await _accountNetBetween(
      AccountCodes.inventory,
      start,
      end,
      referenceType: 'purchase',
    );

    final saleCountColumn = db.saleInvoices.id.count();
    final saleCount =
        await (db.selectOnly(db.saleInvoices)
              ..addColumns([saleCountColumn])
              ..where(
                db.saleInvoices.createdAt.isBiggerOrEqualValue(start) &
                    db.saleInvoices.createdAt.isSmallerThanValue(end),
              ))
            .map((row) => row.read(saleCountColumn) ?? 0)
            .getSingle();
    final purchaseCountColumn = db.purchaseInvoices.id.count();
    final purchaseCount =
        await (db.selectOnly(db.purchaseInvoices)
              ..addColumns([purchaseCountColumn])
              ..where(
                db.purchaseInvoices.createdAt.isBiggerOrEqualValue(start) &
                    db.purchaseInvoices.createdAt.isSmallerThanValue(end),
              ))
            .map((row) => row.read(purchaseCountColumn) ?? 0)
            .getSingle();
    final returnCountColumn = db.saleReturns.id.count();
    final returnCount =
        await (db.selectOnly(db.saleReturns)
              ..addColumns([returnCountColumn])
              ..where(
                db.saleReturns.createdAt.isBiggerOrEqualValue(start) &
                    db.saleReturns.createdAt.isSmallerThanValue(end),
              ))
            .map((row) => row.read(returnCountColumn) ?? 0)
            .getSingle();

    return PeriodReportSnapshot(
      start: start,
      end: end,
      salesMinor: salesMinor,
      cogsMinor: cogsMinor,
      expensesMinor: expensesMinor,
      inventoryVarianceMinor: inventoryVarianceMinor,
      financialVarianceMinor: financialVarianceMinor,
      interestMinor: interestMinor,
      cashNetMinor: await _accountNetBetween(AccountCodes.cash, start, end),
      walletNetMinor: await _accountNetBetween(AccountCodes.wallet, start, end),
      purchaseMinor: purchaseMinor,
      saleCount: saleCount,
      purchaseCount: purchaseCount,
      returnCount: returnCount,
    );
  }

  DateTime _dayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<InstallmentDuePreview> _dueInstallments(
    List<InstallmentPlanPreview> summaries,
  ) {
    final today = _dayStart(clock());
    final horizon = DateTime(today.year, today.month, today.day + 8);
    final result = <InstallmentDuePreview>[
      for (final summary in summaries)
        for (final scheduled in summary.schedule)
          if (scheduled.remainingMinor > 0 &&
              scheduled.payment.dueDate.isBefore(horizon))
            InstallmentDuePreview(
              plan: summary.plan,
              payment: scheduled.payment,
              partyName: summary.partyName,
              remainingMinor: scheduled.remainingMinor,
              isOverdue: scheduled.payment.dueDate.isBefore(today),
            ),
    ];
    result.sort((a, b) {
      final date = a.payment.dueDate.compareTo(b.payment.dueDate);
      if (date != 0) return date;
      final plan = a.plan.id.compareTo(b.plan.id);
      return plan == 0 ? a.payment.id.compareTo(b.payment.id) : plan;
    });
    return result;
  }

  Future<List<InstallmentPlanPreview>> _installmentSummaries({
    required List<InstallmentPlan> plans,
    required List<Customer> customers,
    required List<Supplier> suppliers,
  }) async {
    if (plans.isEmpty) return const [];

    final customerNames = {
      for (final customer in customers) customer.id: customer.name,
    };
    final supplierNames = {
      for (final supplier in suppliers) supplier.id: supplier.name,
    };
    final payments = await (db.select(
      db.installmentPayments,
    )..orderBy([(payment) => OrderingTerm.asc(payment.dueDate)])).get();
    final paymentsByPlan = <int, List<InstallmentPayment>>{};
    for (final payment in payments) {
      paymentsByPlan.putIfAbsent(payment.planId, () => []).add(payment);
    }

    final today = _dayStart(clock());
    final horizon = today.add(const Duration(days: 8));
    final previews = <InstallmentPlanPreview>[];

    for (final plan in plans) {
      final schedule = paymentsByPlan[plan.id] ?? const <InstallmentPayment>[];
      var paidRemainder = plan.paidMinor;
      var overdueMinor = 0;
      var dueSoonMinor = 0;
      var nextDueMinor = 0;
      DateTime? nextDueDate;
      final schedulePreview = <InstallmentSchedulePreview>[];

      for (final payment in schedule) {
        final allocated = paidRemainder <= 0
            ? 0
            : paidRemainder > payment.amountMinor
            ? payment.amountMinor
            : paidRemainder;
        final unpaid = payment.amountMinor - allocated;
        paidRemainder -= allocated;
        final isOverdue = unpaid > 0 && payment.dueDate.isBefore(today);
        final isDueSoon =
            unpaid > 0 &&
            !payment.dueDate.isBefore(today) &&
            payment.dueDate.isBefore(horizon);
        schedulePreview.add(
          InstallmentSchedulePreview(
            payment: payment,
            paidMinor: allocated,
            remainingMinor: unpaid,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
          ),
        );
        if (unpaid == 0) continue;

        if (isOverdue) {
          overdueMinor = addMinor(overdueMinor, unpaid);
        }
        if (isDueSoon) {
          dueSoonMinor = addMinor(dueSoonMinor, unpaid);
        }
        if (nextDueDate == null || payment.dueDate.isBefore(nextDueDate)) {
          nextDueDate = payment.dueDate;
          nextDueMinor = unpaid;
        }
      }

      final names = plan.partyType == 'customer'
          ? customerNames
          : supplierNames;
      previews.add(
        InstallmentPlanPreview(
          plan: plan,
          partyName: names[plan.partyId] ?? '#${plan.partyId}',
          remainingMinor: plan.totalMinor - plan.paidMinor,
          overdueMinor: overdueMinor,
          dueSoonMinor: dueSoonMinor,
          nextDueMinor: nextDueMinor,
          schedule: schedulePreview,
          nextDueDate: nextDueDate,
        ),
      );
    }

    previews.sort((a, b) {
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final aDate = a.nextDueDate ?? DateTime(9999);
      final bDate = b.nextDueDate ?? DateTime(9999);
      return aDate.compareTo(bDate);
    });
    return previews;
  }

  Future<List<PartyBalance>> _partyBalances({
    required String partyType,
    required String accountCode,
    required Map<int, String> names,
    required Map<int, String?> phones,
  }) async {
    final balances = <int, BigInt>{};
    final rows = await db
        .customSelect(
          '''
          SELECT party_id, debit_minor, credit_minor
          FROM ledger_lines
          WHERE account_code = ? AND party_type = ? AND party_id IS NOT NULL
          ''',
          variables: [
            Variable<String>(accountCode),
            Variable<String>(partyType),
          ],
          readsFrom: {db.ledgerLines},
        )
        .get();
    for (final row in rows) {
      final id = row.read<int>('party_id');
      balances[id] =
          (balances[id] ?? BigInt.zero) +
          BigInt.from(row.read<int>('debit_minor')) -
          BigInt.from(row.read<int>('credit_minor'));
    }
    return names.entries
        .map(
          (entry) => PartyBalance(
            id: entry.key,
            name: entry.value,
            type: partyType,
            balanceMinor: checkedMinor(
              (balances[entry.key] ?? BigInt.zero) *
                  BigInt.from(partyType == 'supplier' ? -1 : 1),
            ),
            phone: phones[entry.key],
          ),
        )
        .toList()
      ..sort(
        (a, b) => BigInt.from(
          b.balanceMinor,
        ).abs().compareTo(BigInt.from(a.balanceMinor).abs()),
      );
  }

  Future<List<LedgerEntryPreview>> _recentLedgerEntries() async {
    final entries =
        await (db.select(db.ledgerEntries)
              ..orderBy([
                (entry) => OrderingTerm(
                  expression: entry.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(14))
            .get();
    final previews = <LedgerEntryPreview>[];
    for (final entry in entries) {
      final lines = await (db.select(
        db.ledgerLines,
      )..where((line) => line.entryId.equals(entry.id))).get();
      previews.add(
        LedgerEntryPreview(
          entry: entry,
          debitMinor: lines.fold(0, (sum, line) => sum + line.debitMinor),
          creditMinor: lines.fold(0, (sum, line) => sum + line.creditMinor),
        ),
      );
    }
    return previews;
  }
}
