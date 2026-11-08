part of '../v2_use_cases.dart';

extension V2SnapshotReportUseCases on V2UseCases {
  Future<DashboardSnapshot> dashboardSnapshot() async {
    final shift = await currentShift();
    return DashboardSnapshot(
      interestMinor: subtractMinor(
        0,
        await _accountBalance(AccountCodes.interestIncome),
      ),
      expectedOpenShiftCashMinor: shift == null
          ? null
          : await expectedShiftCashMinor(shift),
      cashMinor: await _accountBalance(AccountCodes.cash),
      walletMinor: await _accountBalance(AccountCodes.wallet),
      receivablesMinor: await _accountBalance(AccountCodes.receivables),
      payablesMinor: await _accountBalance(AccountCodes.payables),
      inventoryMinor: await _accountBalance(AccountCodes.inventory),
      salesMinor: subtractMinor(0, await _accountBalance(AccountCodes.sales)),
      cogsMinor: await _accountBalance(AccountCodes.cogs),
      expensesMinor: await _accountBalance(AccountCodes.expenses),
      inventoryVarianceMinor: await _accountBalance(
        AccountCodes.inventoryVariance,
      ),
      financialVarianceMinor: await _accountBalance(
        AccountCodes.financialVariance,
      ),
      lowStockCount:
          await (db.select(db.products)..where(
                (p) =>
                    p.isActive.equals(true) &
                    p.stockQty.isSmallerOrEqual(p.minStockQty),
              ))
              .get()
              .then((rows) => rows.length),
      openShift: shift,
    );
  }

  Future<WorkbenchSnapshot> workbenchSnapshot() async {
    final products = await (db.select(
      db.products,
    )..orderBy([(p) => OrderingTerm(expression: p.name)])).get();
    final customers = await (db.select(
      db.customers,
    )..orderBy([(c) => OrderingTerm(expression: c.name)])).get();
    final suppliers = await (db.select(
      db.suppliers,
    )..orderBy([(s) => OrderingTerm(expression: s.name)])).get();
    final plans =
        await (db.select(db.installmentPlans)
              ..where((p) => p.status.equals('open'))
              ..orderBy([
                (p) => OrderingTerm(
                  expression: p.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    final recentSales =
        await (db.select(db.saleInvoices)
              ..orderBy([
                (s) => OrderingTerm(
                  expression: s.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(8))
            .get();
    final recentPurchases =
        await (db.select(db.purchaseInvoices)
              ..orderBy([
                (p) => OrderingTerm(
                  expression: p.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(8))
            .get();

    final summaries = await _installmentSummaries(
      plans: plans,
      customers: customers,
      suppliers: suppliers,
    );
    final due = _dueInstallments(summaries);
    final today = _dayStart(clock());
    return WorkbenchSnapshot(
      installmentAlerts: InstallmentAlertsSnapshot(
        overdueCount: due.where((row) => row.isOverdue).length,
        dueTodayCount: due
            .where((row) => _dayStart(row.payment.dueDate) == today)
            .length,
      ),
      dashboard: await dashboardSnapshot(),
      dailySummary: await _dailySummary(clock()),
      products: products,
      customers: customers,
      suppliers: suppliers,
      customerBalances: await _partyBalances(
        partyType: 'customer',
        accountCode: AccountCodes.receivables,
        names: {for (final customer in customers) customer.id: customer.name},
        phones: {for (final customer in customers) customer.id: customer.phone},
      ),
      supplierBalances: await _partyBalances(
        partyType: 'supplier',
        accountCode: AccountCodes.payables,
        names: {for (final supplier in suppliers) supplier.id: supplier.name},
        phones: {for (final supplier in suppliers) supplier.id: supplier.phone},
      ),
      installmentPlans: plans,
      recentLedger: await _recentLedgerEntries(),
      recentSales: recentSales,
      recentPurchases: recentPurchases,
      dueInstallments: due.take(12).toList(),
      installmentSummaries: summaries,
      backupStatus: await _backupStatus(),
      shopSettings: await shopSettings(),
      barcodeLabelSettings: await barcodeLabelSettings(),
      uiBackground: await uiBackground(),
    );
  }

  Future<ShopSettingsSnapshot> shopSettings() async {
    return ShopSettingsSnapshot(
      shopName: await _settingValue('shop.name') ?? 'إخلاص للأجهزة المنزلية',
      branchName:
          _blankToNull(await _settingValue('shop.branch')) ?? 'الفرع الرئيسي',
      phone: _blankToNull(await _settingValue('shop.phone')),
      address: _blankToNull(await _settingValue('shop.address')),
      receiptFooter: _blankToNull(await _settingValue('shop.receiptFooter')),
    );
  }

  Future<AppResult<ShopSettingsSnapshot>> updateShopSettings({
    required String shopName,
    String? branchName,
    String? phone,
    String? address,
    String? receiptFooter,
  }) async {
    if (shopName.trim().isEmpty) {
      return const AppFailure('اسم المحل مطلوب');
    }
    if (branchName != null && branchName.trim().isEmpty) {
      return const AppFailure('اسم الفرع مطلوب');
    }
    return _writeTransaction(() async {
      await _upsertSetting('shop.name', shopName.trim());
      if (branchName != null) {
        await _upsertSetting('shop.branch', branchName.trim());
      }
      await _upsertSetting('shop.phone', phone?.trim() ?? '');
      await _upsertSetting('shop.address', address?.trim() ?? '');
      await _upsertSetting('shop.receiptFooter', receiptFooter?.trim() ?? '');
      return AppSuccess(await shopSettings());
    });
  }

  Future<BarcodeLabelSettingsSnapshot> barcodeLabelSettings() async {
    return BarcodeLabelSettingsSnapshot(
      widthMm: await _integerSetting(
        'barcode.labelWidthMm',
        fallback: BarcodeLabelSettingsSnapshot.defaultWidthMm,
      ),
      heightMm: await _integerSetting(
        'barcode.labelHeightMm',
        fallback: BarcodeLabelSettingsSnapshot.defaultHeightMm,
      ),
    );
  }

  Future<AppResult<BarcodeLabelSettingsSnapshot>> updateBarcodeLabelSettings({
    required int widthMm,
    required int heightMm,
  }) async {
    if (widthMm < BarcodeLabelSettingsSnapshot.minWidthMm ||
        widthMm > BarcodeLabelSettingsSnapshot.maxWidthMm ||
        heightMm < BarcodeLabelSettingsSnapshot.minHeightMm ||
        heightMm > BarcodeLabelSettingsSnapshot.maxHeightMm) {
      return const AppFailure(
        'أبعاد ملصق الباركود يجب أن تكون ضمن الحدود المسموحة',
      );
    }
    return _writeTransaction(() async {
      await _upsertSetting('barcode.labelWidthMm', widthMm.toString());
      await _upsertSetting('barcode.labelHeightMm', heightMm.toString());
      return AppSuccess(await barcodeLabelSettings());
    });
  }

  Future<UiBackgroundSnapshot> uiBackground() async {
    return UiBackgroundSnapshot(
      preset: await _settingValue('ui.backgroundPreset') ?? 'aurora',
      imagePath: _blankToNull(await _settingValue('ui.backgroundImagePath')),
    );
  }

  Future<void> updateUiBackground({required String preset, String? imagePath}) {
    return _writeTransaction(() async {
      await _upsertSetting('ui.backgroundPreset', preset.trim());
      await _upsertSetting('ui.backgroundImagePath', imagePath?.trim() ?? '');
    });
  }

  Future<PeriodReportSnapshot> periodReport({
    required DateTime start,
    required DateTime end,
  }) {
    return _periodReport(
      _dayStart(start),
      _dayStart(end).add(const Duration(days: 1)),
    );
  }

  Future<List<Expense>> expensesReport({
    required DateTime start,
    required DateTime end,
  }) {
    final from = _dayStart(start);
    final to = _dayStart(end).add(const Duration(days: 1));
    return (db.select(db.expenses)
          ..where(
            (expense) =>
                expense.createdAt.isBiggerOrEqualValue(from) &
                expense.createdAt.isSmallerThanValue(to),
          )
          ..orderBy([
            (expense) => OrderingTerm(
              expression: expense.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  Future<List<PartyStatementLine>> partyStatement({
    required String partyType,
    required int partyId,
  }) async {
    final accountCode = partyType == 'supplier'
        ? AccountCodes.payables
        : AccountCodes.receivables;
    final query =
        db.select(db.ledgerLines).join([
            innerJoin(
              db.ledgerEntries,
              db.ledgerEntries.id.equalsExp(db.ledgerLines.entryId),
            ),
          ])
          ..where(
            db.ledgerLines.accountCode.equals(accountCode) &
                db.ledgerLines.partyType.equals(partyType) &
                db.ledgerLines.partyId.equals(partyId),
          )
          ..orderBy([
            OrderingTerm.asc(db.ledgerEntries.createdAt),
            OrderingTerm.asc(db.ledgerEntries.id),
          ]);
    final rows = await query.get();
    var balance = 0;
    final statement = <PartyStatementLine>[];
    for (final row in rows) {
      final line = row.readTable(db.ledgerLines);
      final entry = row.readTable(db.ledgerEntries);
      final delta = partyType == 'supplier'
          ? BigInt.from(line.creditMinor) - BigInt.from(line.debitMinor)
          : BigInt.from(line.debitMinor) - BigInt.from(line.creditMinor);
      balance = checkedMinor(BigInt.from(balance) + delta);
      statement.add(
        PartyStatementLine(
          entry: entry,
          debitMinor: line.debitMinor,
          creditMinor: line.creditMinor,
          balanceMinor: balance,
          invoiceDetails: await _statementInvoiceDetails(entry),
        ),
      );
    }
    return statement;
  }
}
