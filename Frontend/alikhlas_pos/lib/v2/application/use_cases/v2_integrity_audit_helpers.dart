part of '../v2_use_cases.dart';

Map<int, List<T>> _groupIntegrityRows<T>(
  Iterable<T> rows,
  int Function(T row) keyOf,
) {
  final grouped = <int, List<T>>{};
  for (final row in rows) {
    grouped.putIfAbsent(keyOf(row), () => []).add(row);
  }
  return grouped;
}

/// Every audit accumulator is exact before converting to the storage range.
extension _ExactAuditSum<T> on Iterable<T> {
  int exactAuditSum(int Function(T row) value) => sumMinor(map(value));
}
