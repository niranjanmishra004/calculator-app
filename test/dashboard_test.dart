import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';

/// Opens the Other Calculator dashboard through the hamburger icon.
Future<void> openDashboard(WidgetTester tester) async {
  await tester.pumpWidget(const CalculatorApp());
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  expect(find.text('Other Calculator'), findsOneWidget);
}

void main() {
  testWidgets('Age tile opens the age screen', (tester) async {
    await openDashboard(tester);

    await tester.tap(find.text('Age'));
    await tester.pumpAndSettle();

    expect(find.text('Your Age'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);
  });

  testWidgets('Scientific tile opens the scientific screen', (tester) async {
    await openDashboard(tester);

    await tester.tap(find.text('Scientific'));
    await tester.pumpAndSettle();

    // Scientific pad markers: angle toggle and a trig key.
    expect(find.text('Deg'), findsOneWidget);
    expect(find.text('sin'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);
  });

  testWidgets('Unbuilt tiles show a coming-soon note', (tester) async {
    await openDashboard(tester);

    await tester.tap(find.text('GST'));
    // Step frames for the snackbar slide-in. pumpAndSettle would NOT
    // dismiss it (it only pumps until no frames are scheduled), so the
    // 4s timer is advanced past explicitly.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('GST calculator coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Last row tile. No scrolling: the grid fits the test window, and
    // scrolling beforehand leaves residual motion that swallows taps.
    await tester.tap(find.text('Discount'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Discount calculator coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // A first-row tile as the second snackbar, to isolate ordering effects.
    await tester.tap(find.text('Loan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loan calculator coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
