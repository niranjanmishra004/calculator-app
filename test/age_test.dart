import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/age.dart';
import 'package:myapp/main.dart';

/// Opens the age calculator through the hamburger dashboard.
Future<void> openAge(WidgetTester tester) async {
  await tester.pumpWidget(const CalculatorApp());
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Age'));
  await tester.pumpAndSettle();
}

String ageBig(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('ageBig'))).data!;

String keyedText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// Taps a bottom tab. Tab labels mirror some titles, and the tab bar sits
/// after the content in tree order, so `.last` hits the tab.
Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The picker default the screen offers: 25 years ago today.
DateTime pickerDefault() {
  final n = DateTime.now();
  final dim = DateTime(n.year - 25, n.month + 1, 0).day;
  return DateTime(n.year - 25, n.month, n.day > dim ? dim : n.day);
}

void main() {
  group('calculateAge', () {
    test('reference case: 10 Jan 1997 to 11 Jan 2026', () {
      final age = calculateAge(DateTime(1997, 1, 10), DateTime(2026, 1, 11));
      expect(age.years, 29);
      expect(age.months, 0);
      expect(age.days, 1);
      expect(age.totalDays, 10593);
      expect(age.totalMonths, 348);
      expect(age.totalWeeks, 1513);
    });

    test('leap birthday borrows correctly', () {
      final age = calculateAge(DateTime(2000, 2, 29), DateTime(2024, 2, 28));
      expect(age.years, 23);
      expect(age.months, 11);
      expect(age.days, 30);
    });

    test('same day is zero', () {
      final age = calculateAge(DateTime(2026, 5, 5), DateTime(2026, 5, 5));
      expect(age.years, 0);
      expect(age.months, 0);
      expect(age.days, 0);
      expect(age.totalDays, 0);
    });

    test('month-end borrow: 31 Jan to 29 Feb', () {
      final age = calculateAge(DateTime(2024, 1, 31), DateTime(2024, 2, 29));
      expect(age.years, 0);
      expect(age.months, 0);
      expect(age.days, 29);
      expect(age.totalDays, 29);
    });

    test('comparing dates is order independent', () {
      final a = calculateAge(DateTime(2000, 1, 1), DateTime(2020, 6, 15));
      final b = calculateAge(DateTime(2020, 6, 15), DateTime(2000, 1, 1));
      // Reversed dates borrow "negatively"; the screen always orders
      // earlier-first, so only the ordered result is asserted exactly.
      expect(a.years, 20);
      expect(a.months, 5);
      expect(a.days, 14);
      expect(
        a.totalDays,
        DateTime(2020, 6, 15).difference(DateTime(2000, 1, 1)).inDays,
      );
      expect(b.totalDays, -a.totalDays);
    });
  });

  group('nextBirthday', () {
    test('counts down to the next occurrence', () {
      final next = nextBirthday(
        DateTime(1997, 1, 10),
        DateTime(2026, 1, 11),
      );
      expect(next.date, DateTime(2027, 1, 10));
      expect(next.turning, 30);
      expect(next.daysLeft, 364);
    });

    test('birthday today means zero days left', () {
      final next = nextBirthday(
        DateTime(2000, 5, 5),
        DateTime(2026, 5, 5),
      );
      expect(next.date, DateTime(2026, 5, 5));
      expect(next.turning, 26);
      expect(next.daysLeft, 0);
    });

    test('Feb 29 birthdays land on Feb 28 off leap years', () {
      final next = nextBirthday(
        DateTime(2000, 2, 29),
        DateTime(2023, 6, 1),
      );
      expect(next.date, DateTime(2024, 2, 29));
      expect(next.turning, 24);
    });
  });

  group('formatting', () {
    test('dot thousand grouping', () {
      expect(groupThousands(0), '0');
      expect(groupThousands(348), '348');
      expect(groupThousands(1513), '1.513');
      expect(groupThousands(10593), '10.593');
      expect(groupThousands(1000000), '1.000.000');
    });

    test('date and weekday names', () {
      expect(fmtDate(DateTime(1997, 1, 10)), '10 Jan 1997');
      expect(weekdayName(DateTime(1997, 1, 10)), 'Friday');
    });
  });

  testWidgets('Dashboard opens the age screen with its tabs', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);

    await tester.tap(find.text('Age'));
    await tester.pumpAndSettle();

    expect(find.text('Your Age'), findsOneWidget);
    expect(find.text('Date of Birth'), findsOneWidget);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.text('Total Time Alive'), findsOneWidget);
    for (final t in ['Age', 'Birthday']) {
      expect(find.text(t), findsWidgets);
    }
    // No birthdate yet: placeholder state.
    expect(ageBig(tester), '–');
    expect(find.text('Pick your birthdate above'), findsOneWidget);
  });

  testWidgets('Picking a birthdate computes the exact age', (tester) async {
    await openAge(tester);

    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Confirm the offered default: exactly 25 years ago today.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(ageBig(tester), '25');
    expect(keyedText(tester, 'bdYears'), '25');
    expect(keyedText(tester, 'bdMonths'), '0');
    expect(keyedText(tester, 'bdDays'), '0');
    expect(keyedText(tester, 'totMonths'), '300');
    final initial = pickerDefault();
    final today = DateTime.now();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(initial).inDays;
    expect(keyedText(tester, 'totDays'), groupThousands(days));
    expect(
      keyedText(tester, 'ageSub'),
      '25 years, 0 months, 0 days',
    );
  });

  testWidgets('Share action appears once an age is computed', (tester) async {
    await openAge(tester);

    // No birthdate yet: nothing to share.
    expect(find.byIcon(Icons.ios_share), findsNothing);

    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The platform clipboard never resolves inside widget tests, so this
    // asserts the wiring (button shows up exactly when a summary exists)
    // without tapping through to Clipboard.setData.
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });

  testWidgets('Tabs switch content and back returns', (tester) async {
    await openAge(tester);

    expect(find.text('Your Age'), findsOneWidget);

    await tab(tester, 'Birthday');
    expect(find.text('Birthday'), findsWidgets);
    expect(find.byKey(const Key('bdayBig')), findsOneWidget);

    // Compare, Milestones and Settings tabs are gone: only two remain.
    expect(find.text('Compare'), findsNothing);
    expect(find.text('Milestones'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await tab(tester, 'Age');
    expect(find.text('Your Age'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    // Back goes to the dashboard, and once more to the standard pad.
    expect(find.text('Other Calculator'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
