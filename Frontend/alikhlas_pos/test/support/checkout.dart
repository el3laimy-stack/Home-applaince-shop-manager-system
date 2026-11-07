import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapSection(WidgetTester tester, String label) async {
  final nav = find.byKey(const ValueKey('side-navigation-scroll'));
  if (nav.evaluate().isNotEmpty) {
    final scrollable = find
        .descendant(of: nav, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    final labelFinder = find.byWidgetPredicate(
      (w) =>
          (w is Text && w.data == label) ||
          (w is Tooltip && w.message == label),
    );
    if (labelFinder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        labelFinder,
        120,
        scrollable: scrollable,
      );
    }
  }
  final tooltip = find.byTooltip(label);
  final target = tooltip.evaluate().isNotEmpty
      ? tooltip.first
      : find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> reachCheckout(WidgetTester tester, {String? payment}) async {
  for (final label in ['مراجعة ودفع', 'متابعة الدفع']) {
    final button = find.widgetWithText(FilledButton, label);
    if (button.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(button).onPressed != null) {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
  }
  if (payment != null) {
    final selector = find.text('نقدي بالكامل').first;
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(payment).last);
    await tester.pumpAndSettle();
  }
}

Future<void> enterCheckoutField(
  WidgetTester tester,
  String label,
  String value,
) async {
  await reachCheckout(tester);
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Finder quantityInput(int id) => find.descendant(
  of: find.byKey(ValueKey('checkout-qty-$id')),
  matching: find.byType(TextField),
);
Finder costInput(int id) => find.descendant(
  of: find.byKey(ValueKey('checkout-cost-$id')),
  matching: find.byType(TextField),
);
