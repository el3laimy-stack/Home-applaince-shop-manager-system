part of '../v2_use_cases.dart';

/// Durable receipt helpers for financial mutations that return an integer id.
///
/// A receipt is written in the same transaction as the mutation. Replaying the
/// same operation key and payload returns its original id, while a different
/// payload is rejected before any financial state changes.
extension V2OperationReceiptHelpers on V2UseCases {
  String newFinancialOperationKey() =>
      base64UrlEncode(_randomBytes(16)).replaceAll('=', '');

  static const _unreadableReceiptMessage =
      'تعذر التحقق من إيصال عملية محفوظة. لا تعِد تسجيلها؛ راجع الدعم.';

  Future<AppResult<int>> _runIdempotentFinancialOperation({
    required String namespace,
    required String operationKey,
    required Object fingerprintPayload,
    required String conflictMessage,
    required Future<AppResult<int>> Function() execute,
    List<String> legacyIdFields = const [],
    Object? legacyFingerprintPayload,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(operationKey)) {
      return const AppFailure<int>('معرّف عملية غير صالح');
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(fingerprintPayload)))
        .toString();
    final legacyFingerprint = legacyFingerprintPayload == null
        ? null
        : sha256
              .convert(utf8.encode(jsonEncode(legacyFingerprintPayload)))
              .toString();
    final key = 'operation.$namespace.$operationKey';

    try {
      return await _writeTransaction(() async {
        final prior = await OperationReceiptRepository(db).find(key);
        if (prior != null) {
          final saved = prior;
          if (!saved.isReady) {
            return const AppFailure<int>(_unreadableReceiptMessage);
          }
          if (saved.fingerprint != fingerprint &&
              saved.fingerprint != legacyFingerprint) {
            return AppFailure<int>(conflictMessage);
          }
          return AppSuccess<int>(saved.resultValue!);
        }

        final result = await execute();
        if (result is AppSuccess<int>) {
          await OperationReceiptRepository(db).insert(
            decodeOperationReceipt(
              key,
              jsonEncode({'fingerprint': fingerprint, 'id': result.value}),
            ),
            recordedAt: clock(),
          );
        }
        return result;
      });
    } on MoneyRangeException catch (error) {
      return AppFailure<int>(error.message);
    } on Object catch (error, stackTrace) {
      _recordUnexpectedError(
        module: 'financial_operation',
        event: namespace,
        error: error,
        stackTrace: stackTrace,
        operationId: operationKey,
      );
      rethrow;
    }
  }

  /// The opening stock operation creates a product, a stock movement, and
  /// potentially a capital/inventory ledger entry. Its receipt must therefore
  /// replay the original product rather than create another opening balance.
  Future<AppResult<Product>> _runIdempotentProductOperation({
    required String namespace,
    required String operationKey,
    required Object fingerprintPayload,
    required String conflictMessage,
    required Future<AppResult<Product>> Function() execute,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(operationKey)) {
      return const AppFailure<Product>('معرّف عملية غير صالح');
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(fingerprintPayload)))
        .toString();
    final key = 'operation.$namespace.$operationKey';

    try {
      return await _writeTransaction(() async {
        final prior = await OperationReceiptRepository(db).find(key);
        if (prior != null) {
          final saved = prior;
          if (!saved.isReady) {
            return const AppFailure<Product>(_unreadableReceiptMessage);
          }
          if (saved.fingerprint != fingerprint) {
            return AppFailure<Product>(conflictMessage);
          }
          final product =
              await (db.select(db.products)
                    ..where((row) => row.id.equals(saved.resultValue!)))
                  .getSingleOrNull();
          if (product == null) {
            return const AppFailure<Product>(_unreadableReceiptMessage);
          }
          return AppSuccess<Product>(product);
        }

        final result = await execute();
        if (result is AppSuccess<Product>) {
          await OperationReceiptRepository(db).insert(
            decodeOperationReceipt(
              key,
              jsonEncode({'fingerprint': fingerprint, 'id': result.value.id}),
            ),
            recordedAt: clock(),
          );
        }
        return result;
      });
    } on MoneyRangeException catch (error) {
      return AppFailure<Product>(error.message);
    } on Object catch (error, stackTrace) {
      _recordUnexpectedError(
        module: 'product_operation',
        event: namespace,
        error: error,
        stackTrace: stackTrace,
        operationId: operationKey,
      );
      rethrow;
    }
  }

  Future<AppResult<Shift>> _runIdempotentShiftOperation({
    required String namespace,
    required String operationKey,
    required Object fingerprintPayload,
    required String conflictMessage,
    required Future<AppResult<Shift>> Function() execute,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(operationKey)) {
      return const AppFailure<Shift>('معرّف عملية غير صالح');
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(fingerprintPayload)))
        .toString();
    final key = 'operation.$namespace.$operationKey';

    try {
      return await _writeTransaction(() async {
        final prior = await OperationReceiptRepository(db).find(key);
        if (prior != null) {
          final saved = prior;
          if (!saved.isReady) {
            return const AppFailure<Shift>(_unreadableReceiptMessage);
          }
          if (saved.fingerprint != fingerprint) {
            return AppFailure<Shift>(conflictMessage);
          }
          final shift =
              await (db.select(db.shifts)
                    ..where((row) => row.id.equals(saved.resultValue!)))
                  .getSingleOrNull();
          if (shift == null) {
            return const AppFailure<Shift>(_unreadableReceiptMessage);
          }
          return AppSuccess<Shift>(shift);
        }

        final result = await execute();
        if (result is AppSuccess<Shift>) {
          await OperationReceiptRepository(db).insert(
            decodeOperationReceipt(
              key,
              jsonEncode({'fingerprint': fingerprint, 'id': result.value.id}),
            ),
            recordedAt: clock(),
          );
        }
        return result;
      });
    } on MoneyRangeException catch (error) {
      return AppFailure<Shift>(error.message);
    } on Object catch (error, stackTrace) {
      _recordUnexpectedError(
        module: 'shift_operation',
        event: namespace,
        error: error,
        stackTrace: stackTrace,
        operationId: operationKey,
      );
      rethrow;
    }
  }
}
