import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';
import 'package:myapp/sip.dart';

/// Opens the SIP calculator through the hamburger dashboard.
Future<void> openSip(WidgetTester tester) async {
  await tester.pumpWidget(const CalculatorApp());
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('SIP'));
  await tester.pumpAndSettle();
  expect(find.text('SIP Calculator'), findsOneWidget);
}

String sipKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> pad(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Scrolls a field into the visible scrollport and lets motion settle,
/// otherwise the tap lands on the keypad underneath instead.
Future<void> seeField(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 50);
  await tester.pumpAndSettle();
}

/// Picks a duration quick chip from the period sheet.
Future<void> setPeriod(WidgetTester tester, String chip) async {
  await seeField(tester, 'sipPeriod');
  await tester.tap(find.byKey(const Key('sipPeriod')));
  await tester.pumpAndSettle();
  expect(find.text('Done'), findsOneWidget);
  await tester.tap(find.text(chip));
  await tester.pumpAndSettle();
}

/// Types into a field selected by tapping its card.
Future<void> typeInto(
  WidgetTester tester,
  String key,
  List<String> keys,
) async {
  await seeField(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  for (final k in keys) {
    await pad(tester, k);
  }
}

void main() {
  group('sipCalc', () {
    test('standard case: 10000/mo at 12% for 12 months', () {
      final r = sipCalc(10000, 12, 12);
      expect(r.invested, 120000);
      expect(r.total, closeTo(128093.28, 0.05));
      expect(r.gains, closeTo(r.total - r.invested, 1e-9));
    });

    test('zero rate returns exactly the invested amount', () {
      final r = sipCalc(5000, 0, 10);
      expect(r.invested, 50000);
      expect(r.total, 50000);
      expect(r.gains, 0);
    });

    test('empty inputs give zeros', () {
      for (final r in [sipCalc(0, 12, 12), sipCalc(10000, 12, 0)]) {
        expect(r.invested, 0);
        expect(r.total, 0);
        expect(r.gains, 0);
      }
    });

    test('step-up invests more and earns more', () {
      final stepped = sipCalc(10000, 12, 24, 10);
      final plain = sipCalc(10000, 12, 24);
      // Year one 12×10000 plus year two 12×11000.
      expect(stepped.invested, closeTo(252000, 0.01));
      expect(stepped.total, greaterThan(plain.total));
      expect(stepped.gains, greaterThan(0));
    });
  });

  group('inr', () {
    test('Indian grouping', () {
      expect(inr(0), '₹0');
      expect(inr(999), '₹999');
      expect(inr(1000), '₹1,000');
      expect(inr(10871), '₹10,871');
      expect(inr(100000), '₹1,00,000');
      expect(inr(10000000), '₹1,00,00,000');
      expect(inr(12345678), '₹1,23,45,678');
      expect(inr(8093.28), '₹8,093');
    });

    test('entry formatting keeps decimals', () {
      expect(groupIndian('100000'), '1,00,000');
      expect(entryInr(''), '');
      expect(entryInr('10000'), '₹10,000');
      expect(entryInr('12.5'), '₹12.5');
    });
  });

  testWidgets('Empty fields show example placeholders', (tester) async {
    await openSip(tester);

    expect(find.text('SIP Amount'), findsOneWidget);
    expect(find.text('Rate (%)'), findsOneWidget);
    expect(find.text('Investment Period'), findsOneWidget);
    expect(sipKey(tester, 'sipAmount'), '₹10,000');
    expect(sipKey(tester, 'sipRate'), '12');
    expect(sipKey(tester, 'sipPeriod'), 'Select Duration');
    expect(sipKey(tester, 'sipTotal'), '₹0');
    expect(sipKey(tester, 'sipInvested'), '₹0 · 0%');
    expect(sipKey(tester, 'sipGains'), '₹0 · 0%');
  });

  testWidgets('Keypad types into the active field with live results', (
    tester,
  ) async {
    await openSip(tester);

    await pad(tester, '00');
    expect(sipKey(tester, 'sipAmount'), '₹0');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(sipKey(tester, 'sipAmount'), '₹10,000');

    // Pick a period, type rate and amount, totals follow live.
    await setPeriod(tester, '10Y');
    expect(sipKey(tester, 'sipPeriod'), '10 Yrs');
    await typeInto(tester, 'sipRate', ['1', '2']);
    expect(sipKey(tester, 'sipRate'), '12');
    await typeInto(tester, 'sipAmount', ['5', '0', '0', '0']);
    expect(sipKey(tester, 'sipAmount'), '₹5,000');
    final expected = sipCalc(5000, 12, 120);
    expect(sipKey(tester, 'sipTotal'), inr(expected.total));
  });

  testWidgets('Reference values: 10000 at 12% over 10 years', (tester) async {
    await openSip(tester);

    await setPeriod(tester, '10Y');
    await typeInto(tester, 'sipRate', ['1', '2']);
    await typeInto(tester, 'sipAmount', ['1', '0', '0', '0', '0']);

    expect(sipKey(tester, 'sipAmount'), '₹10,000');
    expect(sipKey(tester, 'sipTotal'), '₹23,23,391');
    expect(sipKey(tester, 'sipInvested'), '₹12,00,000 · 52%');
    expect(sipKey(tester, 'sipGains'), '₹11,23,391 · 48%');
  });

  testWidgets('Rate field accepts decimals', (tester) async {
    await openSip(tester);

    await setPeriod(tester, '10Y');
    await typeInto(tester, 'sipRate', ['1', '3', '.', '5']);
    expect(sipKey(tester, 'sipRate'), '13.5');
    await typeInto(tester, 'sipAmount', ['1', '0', '0', '0', '0']);
    final expected = sipCalc(10000, 13.5, 120);
    expect(sipKey(tester, 'sipTotal'), inr(expected.total));
  });

  testWidgets('Step-up raises the projected gains', (tester) async {
    await openSip(tester);

    await setPeriod(tester, '10Y');
    await typeInto(tester, 'sipRate', ['1', '2']);
    await typeInto(tester, 'sipAmount', ['1', '0', '0', '0', '0']);

    final before = sipKey(tester, 'sipGains');
    await typeInto(tester, 'sipStepUp', ['1', '0']);
    expect(sipKey(tester, 'sipStepUp'), '10');
    final expected = sipCalc(10000, 12, 120, 10);
    expect(sipKey(tester, 'sipGains'), startsWith(inr(expected.gains)));
    expect(sipKey(tester, 'sipGains'), isNot(equals(before)));
  });

  testWidgets('Duration sheet quick chip changes the period', (tester) async {
    await openSip(tester);

    expect(sipKey(tester, 'sipPeriod'), 'Select Duration');
    await setPeriod(tester, '5Y');
    expect(sipKey(tester, 'sipPeriod'), '5 Yrs');
  });

  testWidgets('Back returns to the dashboard', (tester) async {
    await openSip(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);
  });
}
