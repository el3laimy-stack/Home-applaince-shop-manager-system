import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reviewed shift is checked atomically and a saved closure replays',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db);
      final shift =
          (await uc.openShift(200000, operationKey: uc.newShiftOperationKey())
                  as AppSuccess<Shift>)
              .value;
      final stale = PendingFinancialOperation.closeShift(
        operationKey: uc.newShiftOperationKey(),
        actualCashMinor: 190000,
        reviewedShiftId: shift.id,
        reviewedExpectedCashMinor: 199900,
      );
      expect(
        PendingFinancialOperation.decode(stale.encode()).encode(),
        stale.encode(),
      );
      await uc.stagePendingFinancialOperation(stale);
      expect(
        await uc.submitPendingFinancialOperation(stale),
        isA<AppFailure<int>>(),
      );
      expect((await uc.currentShift())?.id, shift.id);
      expect(
        await uc.discardUncommittedPendingFinancialOperation(
          stale.operationKey,
        ),
        isTrue,
      );
      final request = PendingFinancialOperation.closeShift(
        operationKey: uc.newShiftOperationKey(),
        actualCashMinor: 190000,
        reviewedShiftId: shift.id,
        reviewedExpectedCashMinor: 200000,
      );
      await uc.stagePendingFinancialOperation(request);
      final first = await uc.submitPendingFinancialOperation(request);
      final second = await uc.submitPendingFinancialOperation(request);
      expect((first as AppSuccess<int>).value, shift.id);
      expect((second as AppSuccess<int>).value, shift.id);
      final closed = await db.select(db.shifts).getSingle();
      expect(closed.differenceMinor, -10000);
      expect(closed.status, 'closed');
      expect((await uc.closedShiftHistory()).single.id, shift.id);
      expect(await uc.closedShiftHistory(offset: 1), isEmpty);
    },
  );
  test('cash movement after review rejects the stale closure', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final uc = V2UseCases(db);
    final shift =
        (await uc.openShift(200000, operationKey: uc.newShiftOperationKey())
                as AppSuccess<Shift>)
            .value;
    final request = PendingFinancialOperation.closeShift(
      operationKey: uc.newShiftOperationKey(),
      actualCashMinor: 190000,
      reviewedShiftId: shift.id,
      reviewedExpectedCashMinor: 200000,
    );
    final movement = await uc.recordExpense(
      operationKey: uc.newExpenseOperationKey(),
      description: 'مصروف اختبار',
      amountMinor: 1000,
      method: PaymentMethod.cash,
      allowNegativeBalance: true,
    );
    expect(movement, isA<AppSuccess<int>>());
    expect(await uc.expectedShiftCashMinor(shift), 199000);
    await uc.stagePendingFinancialOperation(request);
    expect(
      await uc.submitPendingFinancialOperation(request),
      isA<AppFailure<int>>(),
    );
    expect((await uc.currentShift())?.id, shift.id);
  });
  test('legacy close request still round-trips without review fields', () {
    final request = PendingFinancialOperation.closeShift(
      operationKey: 'old',
      actualCashMinor: 0,
    );
    expect(
      PendingFinancialOperation.decode(request.encode()).encode(),
      request.encode(),
    );
  });
}
