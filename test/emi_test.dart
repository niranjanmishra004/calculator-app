import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/emi.dart';
import 'package:myapp/main.dart';
import 'package:myapp/sip.dart' show inr;

/// Opens the EMI calculator through the hamburger dashboard.
Future<void> openEmi(WidgetTester tester) async {
  await tester.pumpWidget(const CalculatorApp());
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('EMI'));
  await tester.pumpAndSettle();
  expect(find.text('EMI Calculator'), findsOneWidget);
}

String emiKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('emiCalc', () {
    test('reference values: 500000 at 10.5% over 5 years', () {
      final r = emiCalc(500000, 10.5, 60);
      expect(r.emi, 10747);
      expect(r.total, 644820);
      expect(r.interest, 144820);
      expect(r.months, 60);
    });

    test('zero rate splits the principal evenly', () {
      final r = emiCalc(120000, 0, 12);
      expect(r.emi, 10000);
      expect(r.total, 120000);
      expect(r.interest, 0);
    });

    test('empty inputs give zeros', () {
      for (final r in [emiCalc(0, 10.5, 60), emiCalc(500000, 10.5, 0)]) {
        expect(r.emi, 0);
        expect(r.total, 0);
        expect(r.interest, 0);
      }
    });
  });

  group('emiSchedule', () {
    test('yearly rows add up to the loan', () {
      final res = emiCalc(500000, 10.5, 60);
      final rows = emiSchedule(500000, 10.5, 60, res.emi);
      expect(rows.length, 5);
      final p = rows.fold(0.0, (a, r) => a + r.principal);
      final i = rows.fold(0.0, (a, r) => a + r.interest);
      expect(p, closeTo(500000, 0.01));
      // Rounded EMIs leave a few rupees of rounding in the last year.
      expect(i, closeTo(res.interest, 10));
      expect(rows.last.balance, closeTo(0, 0.01));
    });

    test('short loans produce a single partial-year row', () {
      final res = emiCalc(120000, 0, 6);
      final rows = emiSchedule(120000, 0, 6, res.emi);
      expect(rows.length, 1);
      expect(rows.single.year, 1);
      expect(rows.single.principal, closeTo(120000, 0.01));
    });
  });

  testWidgets('Empty fields show example placeholders', (tester) async {
    await openEmi(tester);

    expect(emiKey(tester, 'emiAmount'), '₹5,00,000');
    expect(emiKey(tester, 'emiRate'), '10.5%');
    expect(emiKey(tester, 'emiTenure'), 'Select tenure');
    expect(emiKey(tester, 'emiTotal'), '–');
  });

  /// Edits a row through its editor sheet with the normal keyboard.
  Future<void> emiType(
    WidgetTester tester,
    String key,
    String value,
  ) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), value);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  /// Picks a tenure quick chip.
  Future<void> emiChip(WidgetTester tester, String chip) async {
    await tester.tap(find.byKey(const Key('emiTenure')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(chip));
    await tester.pumpAndSettle();
  }

  testWidgets('Reference values: 500000 at 10.5% over 5 years', (
    tester,
  ) async {
    await openEmi(tester);

    await emiType(tester, 'emiAmount', '500000');
    expect(emiKey(tester, 'emiAmount'), '₹5,00,000');
    await emiType(tester, 'emiRate', '10.5');
    expect(emiKey(tester, 'emiRate'), '10.5%');

    await tester.tap(find.byKey(const Key('emiTenure')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5Y'));
    await tester.pumpAndSettle();
    expect(emiKey(tester, 'emiTenure'), '5 years');

    await tester.tap(find.text('Calculate EMI'));
    await tester.pumpAndSettle();

    expect(emiKey(tester, 'emiTotal'), '₹10,747');
    expect(emiKey(tester, 'emiInterest'), '₹1,44,820');
    expect(emiKey(tester, 'emiPayment'), '₹6,44,820');
  });

  testWidgets('Editing then calculating updates the results', (tester) async {
    await openEmi(tester);

    await emiType(tester, 'emiAmount', '600000');
    // Editing invalidates the snapshot: prompt state until Calculate.
    expect(emiKey(tester, 'emiTotal'), '–');

    await emiType(tester, 'emiRate', '10.5');
    await emiChip(tester, '5Y');
    expect(emiKey(tester, 'emiTenure'), '5 years');

    await tester.tap(find.text('Calculate EMI'));
    await tester.pumpAndSettle();

    final expected = emiCalc(600000, 10.5, 60);
    expect(emiKey(tester, 'emiTotal'), inr(expected.emi));
    expect(emiKey(tester, 'emiInterest'), inr(expected.interest));
  });

  testWidgets('Tenure chips and schedule sheet work', (tester) async {
    await openEmi(tester);

    expect(emiKey(tester, 'emiTenure'), 'Select tenure');
    await emiType(tester, 'emiAmount', '500000');
    await emiType(tester, 'emiRate', '10.5');
    await emiChip(tester, '10Y');
    expect(emiKey(tester, 'emiTenure'), '10 years');

    await tester.tap(find.text('Calculate EMI'));
    await tester.pumpAndSettle();
    final expected = emiCalc(500000, 10.5, 120);
    expect(emiKey(tester, 'emiTotal'), inr(expected.emi));

    // The link sits at the very bottom: bring it into view first.
    await tester.scrollUntilVisible(
      find.text('View payment schedule'),
      100,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View payment schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Schedule'), findsOneWidget);
    expect(find.text('Year 1'), findsOneWidget);
    expect(find.text('Year 10'), findsOneWidget);
  });

  testWidgets('Zero loan amount asks for details', (tester) async {
    await openEmi(tester);

    // Valid rate and tenure isolate the zero-amount path.
    await emiType(tester, 'emiRate', '10.5');
    await emiChip(tester, '5Y');
    await emiType(tester, 'emiAmount', '0');
    expect(emiKey(tester, 'emiAmount'), '₹0');

    await tester.tap(find.text('Calculate EMI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Enter loan details to calculate'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('Back returns to the dashboard', (tester) async {
    await openEmi(tester);

    // Header back sits in a circle button.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);
  });
}
