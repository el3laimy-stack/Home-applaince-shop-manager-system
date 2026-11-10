import 'package:drift/drift.dart';
import 'app_database.dart';
import 'operation_receipt_codec.dart';

/// Every retry and pending-request reader uses this boundary. A blocked or
/// conflicting source is present evidence, never permission to execute again.
class OperationReceiptRepository {
  OperationReceiptRepository(this.db);
  final AppDatabase db;

  Future<DecodedOperationReceipt?> find(String key) async {
    final current = await (db.select(
      db.operationReceipts,
    )..where((r) => r.receiptKey.equals(key))).getSingleOrNull();
    final legacy = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (current == null && legacy == null) return null;
    DecodedOperationReceipt? saved;
    if (current != null) {
      saved = decodeOperationReceipt(key, current.rawPayload);
      if (current.status != 'ready' ||
          !saved.isReady ||
          current.formatVersion != 1 ||
          current.namespace != saved.namespace ||
          current.operationKey != saved.operationKey ||
          current.fingerprint != saved.fingerprint ||
          current.resultKind != saved.resultKind ||
          current.resultValue != saved.resultValue ||
          current.blockReason != null) {
        return saved.blocked('stored-receipt-barrier');
      }
    }
    if (legacy != null) {
      final old = decodeOperationReceipt(key, legacy.value);
      if (!old.isReady) return old;
      if (saved != null && !saved.agreesWith(old)) {
        return saved.blocked('legacy-conflict');
      }
      saved ??= old;
    }
    final result = saved!;
    final table = receiptResultTables[result.resultKind];
    if (table != null &&
        (await db
                .customSelect(
                  'SELECT 1 FROM $table WHERE id=?',
                  variables: [Variable<int>(result.resultValue!)],
                )
                .get())
            .isEmpty) {
      return result.blocked('missing-result');
    }
    return result;
  }

  /// Called inside the same application transaction as the financial mutation.
  Future<void> insert(
    DecodedOperationReceipt receipt, {
    DateTime? recordedAt,
  }) async {
    await db
        .into(db.operationReceipts)
        .insert(
          OperationReceiptsCompanion.insert(
            receiptKey: receipt.key,
            namespace: Value(receipt.namespace),
            operationKey: Value(receipt.operationKey),
            status: receipt.status,
            rawPayload: receipt.rawPayload,
            blockReason: Value(receipt.blockReason),
            fingerprint: Value(receipt.fingerprint),
            resultKind: Value(receipt.resultKind),
            resultValue: Value(receipt.resultValue),
            recordedAt: Value(recordedAt),
          ),
        );
  }
}
