import 'package:intl/intl.dart';

final minMoneyMinor = -(BigInt.one << 63);
final maxMoneyMinor = (BigInt.one << 63) - BigInt.one;

class MoneyRangeException implements Exception {
  const MoneyRangeException();
  String get message => 'المبلغ أو ناتج الحساب أكبر من المجال الآمن للتخزين.';
  @override
  String toString() => message;
}

int checkedMinor(BigInt value) {
  if (value < minMoneyMinor || value > maxMoneyMinor) {
    throw const MoneyRangeException();
  }
  return value.toInt();
}

int absoluteMinor(int value) => checkedMinor(BigInt.from(value).abs());

int addMinor(int a, int b) => checkedMinor(BigInt.from(a) + BigInt.from(b));
int subtractMinor(int a, int b) =>
    checkedMinor(BigInt.from(a) - BigInt.from(b));
int multiplyMinor(int a, int b) =>
    checkedMinor(BigInt.from(a) * BigInt.from(b));
int sumMinor(Iterable<int> values) => checkedMinor(
  values.fold<BigInt>(BigInt.zero, (sum, value) => sum + BigInt.from(value)),
);

int netProfitMinor({
  required int sales,
  required int interest,
  required int cogs,
  required int expenses,
  required int inventoryVariance,
  required int financialVariance,
}) => checkedMinor(
  BigInt.from(sales) +
      BigInt.from(interest) -
      BigInt.from(cogs) -
      BigInt.from(expenses) -
      BigInt.from(inventoryVariance) -
      BigInt.from(financialVariance),
);

class Money implements Comparable<Money> {
  const Money(this.minorUnits);

  static const zero = Money(0);

  final int minorUnits;

  Money operator +(Money other) =>
      Money(addMinor(minorUnits, other.minorUnits));
  Money operator -(Money other) =>
      Money(subtractMinor(minorUnits, other.minorUnits));
  Money operator -() => Money(subtractMinor(0, minorUnits));
  Money operator *(int factor) => Money(multiplyMinor(minorUnits, factor));

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;

  String format({String symbol = 'ج.م'}) {
    final formatter = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: symbol,
      decimalDigits: 2,
    );
    // Preserve locale placement and bidi marks, substituting exact digits.
    final absolute = BigInt.from(minorUnits).abs();
    final whole = _thousands(absolute ~/ BigInt.from(100));
    final cents = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
    final exact = '$whole.$cents';
    final symbols = formatter.symbols;
    final localized = exact.split('').map((char) {
      if (char == ',') return symbols.GROUP_SEP;
      if (char == '.') return symbols.DECIMAL_SEP;
      return String.fromCharCode(
        symbols.ZERO_DIGIT.codeUnitAt(0) + int.parse(char),
      );
    }).join();
    final sample = formatter.format(minorUnits < 0 ? -1 : 1);
    return sample.replaceFirst(
      RegExp(
        '[0-9${symbols.ZERO_DIGIT}-${String.fromCharCode(symbols.ZERO_DIGIT.codeUnitAt(0) + 9)}${RegExp.escape(symbols.GROUP_SEP + symbols.DECIMAL_SEP)}]+',
      ),
      localized,
    );
  }

  String formatPlain({String symbol = 'ج.م'}) {
    final sign = minorUnits < 0 ? '-' : '';
    final absolute = BigInt.from(minorUnits).abs();
    final pounds = absolute ~/ BigInt.from(100);
    final cents = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
    return '$sign${_thousands(pounds)}.$cents $symbol';
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  String toString() => format();
}

String _thousands(BigInt value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

class MoneyInputParse {
  const MoneyInputParse._({required this.minorUnits, this.errorMessage});

  const MoneyInputParse.valid(int minorUnits) : this._(minorUnits: minorUnits);

  const MoneyInputParse.invalid(String errorMessage)
    : this._(minorUnits: 0, errorMessage: errorMessage);

  final int minorUnits;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

MoneyInputParse parseMoneyInput(String rawInput, {bool allowNegative = false}) {
  final input = normalizeArabicDigits(rawInput.trim()).replaceAll('٫', '.');
  if (input.isEmpty) return const MoneyInputParse.valid(0);

  final negative = input.startsWith('-');
  final unsigned = negative ? input.substring(1) : input;
  final error = _moneyInputError(
    unsigned,
    negative: negative,
    allowNegative: allowNegative,
  );
  if (error != null) return MoneyInputParse.invalid(error);

  final parts = unsigned.split(RegExp(r'[.,]'));
  final poundsText = parts.first;
  final centsText = parts.length == 2 ? parts.last : '';
  final pounds = BigInt.parse(poundsText);
  final cents = BigInt.parse(centsText.padRight(2, '0'));
  final absolute = pounds * BigInt.from(100) + cents;
  final value = negative ? -absolute : absolute;
  if (value < minMoneyMinor || value > maxMoneyMinor) {
    return MoneyInputParse.invalid(const MoneyRangeException().message);
  }
  return MoneyInputParse.valid(value.toInt());
}

int allocateRemainderToLast(int totalMinorUnits, int count, int index) {
  if (count <= 0) {
    throw ArgumentError.value(
      count,
      'count',
      'Installment count must be positive.',
    );
  }
  final base = totalMinorUnits ~/ count;
  final remainder = totalMinorUnits - (base * count);
  return index == count - 1 ? base + remainder : base;
}

String normalizeArabicDigits(String input) {
  const arabicZero = 0x0660;
  const persianZero = 0x06F0;
  final buffer = StringBuffer();
  for (final codeUnit in input.codeUnits) {
    if (codeUnit >= arabicZero && codeUnit <= arabicZero + 9) {
      buffer.write(codeUnit - arabicZero);
    } else if (codeUnit >= persianZero && codeUnit <= persianZero + 9) {
      buffer.write(codeUnit - persianZero);
    } else {
      buffer.writeCharCode(codeUnit);
    }
  }
  return buffer.toString();
}

String? _moneyInputError(
  String unsigned, {
  required bool negative,
  required bool allowNegative,
}) {
  if (negative && !allowNegative) return 'المبلغ لا يمكن أن يكون سالبًا';
  if (unsigned.isEmpty) return 'اكتب مبلغًا صحيحًا مثل 125 أو 125.50';
  if (RegExp(r'[^0-9.,]').hasMatch(unsigned)) {
    return 'استخدم أرقامًا وفاصلًا عشريًا فقط';
  }

  final parts = unsigned.split(RegExp(r'[.,]'));
  if (parts.length > 2) return 'استخدم فاصلًا عشريًا واحدًا فقط';
  return _moneyPartsError(parts);
}

String? _moneyPartsError(List<String> parts) {
  final poundsText = parts.first;
  final centsText = parts.length == 2 ? parts.last : '';
  if (poundsText.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(poundsText)) {
    return 'اكتب مبلغًا صحيحًا مثل 125 أو 125.50';
  }
  if (centsText.length > 2) return 'استخدم خانتين عشريتين كحد أقصى';
  if (centsText.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(centsText)) {
    return 'استخدم أرقامًا وفاصلًا عشريًا فقط';
  }
  return null;
}
