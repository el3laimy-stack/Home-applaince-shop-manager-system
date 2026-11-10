part of '../v2_use_cases.dart';

extension V2CoreUseCaseHelpers on V2UseCases {
  String? _blankToNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Future<String> _nextNumber(String key, {required String prefix}) async {
    final current = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final next = addMinor(int.parse(current?.value ?? '0'), 1);
    await _upsertSetting(key, next.toString());
    return '$prefix-${clock().year}-${next.toString().padLeft(5, '0')}';
  }

  Future<String> _nextProductBarcode({Set<String> reserved = const {}}) async {
    final used =
        (await db.select(db.products).get())
            .map((row) => row.barcode)
            .whereType<String>()
            .toSet()
          ..addAll(reserved);
    while (true) {
      final candidate = await _nextNumber(
        'sequence.productBarcode',
        prefix: 'AK',
      );
      if (!used.contains(candidate)) return candidate;
    }
  }

  Future<void> _insertPayments(
    String ownerType,
    int ownerId,
    List<PaymentInput> payments,
  ) async {
    for (final payment in payments.where((p) => p.amountMinor > 0)) {
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              ownerType: ownerType,
              ownerId: ownerId,
              method: payment.method.name,
              amountMinor: payment.amountMinor,
              note: Value(payment.note),
            ),
          );
    }
  }

  Future<AppConfirmationRequired<int>?> _negativeBalanceConfirmationFor(
    List<_LedgerLineDraft> lines,
  ) async {
    final deltas = <String, int>{};
    for (final line in lines) {
      if (line.accountCode != AccountCodes.cash &&
          line.accountCode != AccountCodes.wallet) {
        continue;
      }
      final delta = subtractMinor(line.debitMinor, line.creditMinor);
      if (delta == 0) continue;
      deltas.update(
        line.accountCode,
        (current) => addMinor(current, delta),
        ifAbsent: () => delta,
      );
    }

    final impacts = <NegativeBalanceImpact>[];
    for (final entry in deltas.entries) {
      if (entry.value >= 0) continue;
      final current = await _accountBalance(entry.key);
      final next = addMinor(current, entry.value);
      if (next >= 0) continue;
      impacts.add(
        NegativeBalanceImpact(
          accountCode: entry.key,
          label: _liquidAccountLabel(entry.key),
          currentMinor: current,
          deltaMinor: entry.value,
          newMinor: next,
        ),
      );
    }

    if (impacts.isEmpty) return null;
    return AppConfirmationRequired<int>(
      code: 'negative_liquid_balance',
      message: 'هذه العملية ستجعل رصيد الخزينة أو المحفظة سالبًا',
      payload: NegativeBalanceConfirmation(impacts: impacts),
    );
  }

  String _liquidAccountLabel(String accountCode) {
    return switch (accountCode) {
      AccountCodes.cash => 'الخزينة',
      AccountCodes.wallet => 'المحفظة',
      _ => accountCode,
    };
  }

  Future<int> _postLedger({
    required String referenceType,
    required int referenceId,
    required String description,
    required List<_LedgerLineDraft> lines,
  }) async {
    final debit = sumMinor(lines.map((line) => line.debitMinor));
    final credit = sumMinor(lines.map((line) => line.creditMinor));
    if (debit != credit || debit == 0) {
      throw StateError('Unbalanced ledger entry: debit=$debit credit=$credit');
    }

    // Validate final balances before any posting; intermediate arithmetic is exact.
    final deltas = <String, BigInt>{};
    for (final line in lines) {
      deltas[line.accountCode] =
          (deltas[line.accountCode] ?? BigInt.zero) +
          BigInt.from(line.debitMinor) -
          BigInt.from(line.creditMinor);
    }
    for (final entry in deltas.entries) {
      final next = BigInt.from(await _accountBalance(entry.key)) + entry.value;
      checkedMinor(next);
      if (entry.key == AccountCodes.sales ||
          entry.key == AccountCodes.interestIncome ||
          entry.key == AccountCodes.payables) {
        checkedMinor(-next);
      }
    }

    final partyDeltas = <({String account, String type, int id}), BigInt>{};
    for (final line in lines) {
      if (line.partyType == null || line.partyId == null) continue;
      final key = (
        account: line.accountCode,
        type: line.partyType!,
        id: line.partyId!,
      );
      partyDeltas[key] =
          (partyDeltas[key] ?? BigInt.zero) +
          BigInt.from(line.debitMinor) -
          BigInt.from(line.creditMinor);
    }
    for (final entry in partyDeltas.entries) {
      final key = entry.key;
      final rows = await db
          .customSelect(
            "SELECT l.debit_minor,l.credit_minor FROM ledger_lines l JOIN ledger_entries e ON e.id=l.entry_id WHERE e.posting_state='posted' AND l.account_code=? AND l.party_type=? AND l.party_id=?",
            variables: [
              Variable<String>(key.account),
              Variable<String>(key.type),
              Variable<int>(key.id),
            ],
          )
          .get();
      final current = rows.fold<BigInt>(
        BigInt.zero,
        (sum, row) =>
            sum +
            BigInt.from(row.data['debit_minor'] as int) -
            BigInt.from(row.data['credit_minor'] as int),
      );
      final next = current + entry.value;
      checkedMinor(next);
      checkedMinor(key.type == 'supplier' ? -next : next);
    }

    final entryId = await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            referenceType: referenceType,
            referenceId: referenceId,
            description: description,
          ),
        );

    for (final line in lines) {
      if (line.debitMinor < 0 || line.creditMinor < 0) {
        throw StateError('Ledger lines cannot contain negative values.');
      }
      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              entryId: entryId,
              accountCode: line.accountCode,
              debitMinor: Value(line.debitMinor),
              creditMinor: Value(line.creditMinor),
              partyType: Value(line.partyType),
              partyId: Value(line.partyId),
            ),
          );
    }
    await (db.update(db.ledgerEntries)
          ..where((entry) => entry.id.equals(entryId)))
        .write(const LedgerEntriesCompanion(postingState: Value('posted')));
    return entryId;
  }

  Future<int> _accountBalance(String accountCode) async {
    return _accountNet(accountCode: accountCode);
  }

  Future<int> _accountNetBetween(
    String accountCode,
    DateTime start,
    DateTime end, {
    String? referenceType,
  }) async {
    return _accountNet(
      accountCode: accountCode,
      start: start,
      end: end,
      referenceType: referenceType,
    );
  }

  Future<int> _accountNet({
    required String accountCode,
    DateTime? start,
    DateTime? end,
    String? referenceType,
  }) async {
    final where = <String>["e.posting_state='posted'", 'l.account_code = ?'];
    final variables = <Variable>[Variable<String>(accountCode)];
    if (start != null) {
      where.add('e.created_at >= ?');
      variables.add(Variable<DateTime>(start));
    }
    if (end != null) {
      where.add('e.created_at < ?');
      variables.add(Variable<DateTime>(end));
    }
    if (referenceType != null) {
      where.add('e.reference_type = ?');
      variables.add(Variable<String>(referenceType));
    }

    const from =
        'ledger_lines l INNER JOIN ledger_entries e ON e.id = l.entry_id';
    final rows = await db
        .customSelect(
          '''
          SELECT l.debit_minor, l.credit_minor
          FROM $from
          WHERE ${where.join(' AND ')}
          ''',
          variables: variables,
          readsFrom: {db.ledgerLines, db.ledgerEntries},
        )
        .get();
    return checkedMinor(
      rows.fold<BigInt>(
        BigInt.zero,
        (sum, row) =>
            sum +
            BigInt.from(row.read<int>('debit_minor')) -
            BigInt.from(row.read<int>('credit_minor')),
      ),
    );
  }

  int _sumPayments(List<PaymentInput> payments, PaymentMethod method) {
    return sumMinor(
      payments
          .where((payment) => payment.method == method)
          .map((payment) => payment.amountMinor),
    );
  }
}
