import 'dart:convert';

const receiptResultKinds = <String, String>{
  'sale': 'sale_invoice',
  'purchase': 'purchase_invoice',
  'sale_return': 'sale_return',
  'purchase_return': 'purchase_return',
  'opening_stock': 'product',
  'inventory_adjustment': 'inventory_adjustment',
  'opening_balance': 'opening_balance',
  'financial_correction': 'financial_correction',
  'financial_correction_reversal': 'financial_correction_reversal',
  'expense': 'expense',
  'installment.customer': 'ledger_entry',
  'installment.supplier': 'ledger_entry',
  'shift.open': 'shift',
  'shift.close': 'shift',
  'product_csv_import': 'scalar_count',
};
const receiptResultTables = <String, String>{
  'sale_invoice': 'sale_invoices',
  'purchase_invoice': 'purchase_invoices',
  'sale_return': 'sale_returns',
  'purchase_return': 'purchase_returns',
  'product': 'products',
  'inventory_adjustment': 'inventory_adjustments',
  'opening_balance': 'opening_balances',
  'financial_correction': 'financial_corrections',
  'financial_correction_reversal': 'financial_correction_reversals',
  'expense': 'expenses',
  'ledger_entry': 'ledger_entries',
  'shift': 'shifts',
};

class DecodedOperationReceipt {
  const DecodedOperationReceipt({
    required this.key,
    required this.rawPayload,
    this.namespace,
    this.operationKey,
    this.fingerprint,
    this.resultKind,
    this.resultValue,
    this.blockReason,
  });
  final String key, rawPayload;
  final String? namespace, operationKey, fingerprint, resultKind, blockReason;
  final int? resultValue;
  bool get isReady => blockReason == null;
  String get status => isReady ? 'ready' : 'blocked';
  DecodedOperationReceipt blocked(String reason) => DecodedOperationReceipt(
    key: key,
    rawPayload: rawPayload,
    namespace: namespace,
    operationKey: operationKey,
    blockReason: reason,
  );
  bool agreesWith(DecodedOperationReceipt other) =>
      isReady &&
      other.isReady &&
      key == other.key &&
      namespace == other.namespace &&
      operationKey == other.operationKey &&
      fingerprint == other.fingerprint &&
      resultKind == other.resultKind &&
      resultValue == other.resultValue;
}

/// Match complete registered namespaces, including embedded dots. The original
/// key and bytes are retained even if neither namespace nor payload is readable.
DecodedOperationReceipt decodeOperationReceipt(String key, String raw) {
  String? namespace, operationKey;
  for (final known in receiptResultKinds.keys) {
    final prefix = 'operation.$known.';
    if (key.startsWith(prefix)) {
      namespace = known;
      operationKey = key.substring(prefix.length);
      break;
    }
  }
  final base = DecodedOperationReceipt(
    key: key,
    rawPayload: raw,
    namespace: namespace,
    operationKey: operationKey,
  );
  if (namespace == null ||
      operationKey == null ||
      !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(operationKey)) {
    return base.blocked('unknown-key-contract');
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return base.blocked('unreadable-payload');
    final fingerprint = decoded['fingerprint'];
    final aliases = switch (namespace) {
      'sale' => ['saleId'],
      'purchase' => ['purchaseId'],
      _ => <String>[],
    };
    var result = decoded['id'];
    for (final alias in aliases) {
      final candidate = decoded[alias];
      if (result != null && candidate != null && result != candidate) {
        return base.blocked('conflicting-result-alias');
      }
      result ??= candidate;
    }
    if (fingerprint is! String ||
        fingerprint.isEmpty ||
        result is! int ||
        result < 1) {
      return base.blocked('unreadable-payload');
    }
    return DecodedOperationReceipt(
      key: key,
      rawPayload: raw,
      namespace: namespace,
      operationKey: operationKey,
      fingerprint: fingerprint,
      resultKind: receiptResultKinds[namespace],
      resultValue: result,
    );
  } on FormatException {
    return base.blocked('unreadable-payload');
  }
}
