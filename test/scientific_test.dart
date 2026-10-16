import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';

/// Taps a scientific key. Keys sit after the display in tree order,
/// so `.last` hits the key even when the same glyph is on screen.
Future<void> skey(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
}

/// Opens the scientific screen through the hamburger dashboard.
Future<void> openSci(WidgetTester tester) async {
  await tester.pumpWidget(const CalculatorApp());
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scientific'));
  await tester.pumpAndSettle();
}

/// Big number in the scientific display.
String sDisplay(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sciDisplay'))).data!;

/// Expression line above the big number.
String sHistory(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sciHistory'))).data ?? '';

void main() {
  testWidgets('Dashboard opens the scientific screen and back returns', (
    tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);

    await tester.tap(find.text('Scientific'));
    await tester.pumpAndSettle();

    // Full scientific pad from the reference.
    for (final label in [
      '(',
      ')',
      'mc',
      'm+',
      'm-',
      'mr',
      '2nd',
      'x²',
      'x³',
      'x^y',
      'e^x',
      '10^x',
      '1/x',
      '²√x',
      '³√x',
      'y√x',
      'ln',
      'log10',
      'x!',
      'sin',
      'cos',
      'tan',
      'e',
      'EE',
      'Rand',
      'sinh',
      'cosh',
      'tanh',
      'π',
      'Deg',
      'DEL',
      'C',
      '%',
      '÷',
      '×',
      '−',
      '+',
      '+/-',
      '.',
      '0',
      '=',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(sDisplay(tester), '0');

    // Back arrow returns to the dashboard, and once more to standard.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Other Calculator'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('Square root: ²√(9) = 3', (tester) async {
    await openSci(tester);

    await skey(tester, '²√x');
    await skey(tester, '9');
    await skey(tester, ')');

    expect(sHistory(tester), '²√(9)');
    expect(sDisplay(tester), '3');

    await skey(tester, '=');
    expect(sDisplay(tester), '3');
  });

  testWidgets('Sine in degrees: sin(30) = 0.5', (tester) async {
    await openSci(tester);

    await skey(tester, 'sin');
    await skey(tester, '3');
    await skey(tester, '0');
    await skey(tester, ')');

    expect(sHistory(tester), 'sin(30)');
    expect(sDisplay(tester), '0.5');

    await skey(tester, '=');
    expect(sDisplay(tester), '0.5');
  });

  testWidgets('2nd gives inverse trig: asin(1) = 90°', (tester) async {
    await openSci(tester);

    await skey(tester, '2nd');
    expect(find.text('asin'), findsOneWidget);
    expect(find.text('sin'), findsNothing);

    await skey(tester, 'asin');
    await skey(tester, '1');
    await skey(tester, ')');
    await skey(tester, '=');

    expect(sHistory(tester), 'asin(1)');
    expect(sDisplay(tester), '90');
  });

  testWidgets('Factorial: 5! = 120', (tester) async {
    await openSci(tester);

    await skey(tester, '5');
    await skey(tester, 'x!');

    expect(sHistory(tester), '5!');
    expect(sDisplay(tester), '120');

    await skey(tester, '=');
    expect(sDisplay(tester), '120');
  });

  testWidgets('Power and y-root: 2^8 = 256, 3y√27 = 3', (tester) async {
    await openSci(tester);

    await skey(tester, '2');
    await skey(tester, 'x^y');
    await skey(tester, '8');
    await skey(tester, '=');

    expect(sHistory(tester), '2^8');
    expect(sDisplay(tester), '256');

    await skey(tester, 'C');
    await skey(tester, '3');
    await skey(tester, 'y√x');
    await skey(tester, '2');
    await skey(tester, '7');
    await skey(tester, '=');

    expect(sHistory(tester), '3y√27');
    expect(sDisplay(tester), '3');
  });

  testWidgets('Implicit multiply: 2π previews correctly', (tester) async {
    await openSci(tester);

    await skey(tester, '2');
    await skey(tester, 'π');

    expect(sHistory(tester), '2×π');
    expect(sDisplay(tester), '6.28318531');
  });

  testWidgets('Logarithm: ln(e) = 1', (tester) async {
    await openSci(tester);

    await skey(tester, 'ln');
    await skey(tester, 'e');
    await skey(tester, ')');
    await skey(tester, '=');

    expect(sHistory(tester), 'ln(e)');
    expect(sDisplay(tester), '1');
  });

  testWidgets('Memory keys store, recall and flag M', (tester) async {
    await openSci(tester);

    await skey(tester, '5');
    await skey(tester, 'm+');
    expect(find.text('M'), findsOneWidget);

    await skey(tester, 'C');
    await skey(tester, 'C');
    expect(sDisplay(tester), '0');

    await skey(tester, 'mr');
    expect(sDisplay(tester), '5');

    await skey(tester, 'mc');
    expect(find.text('M'), findsNothing);
  });

  testWidgets('EE types powers of ten: 1e5 = 100000', (tester) async {
    await openSci(tester);

    await skey(tester, '1');
    await skey(tester, 'EE');
    await skey(tester, '5');

    expect(sHistory(tester), '1e5');

    await skey(tester, '=');
    expect(sDisplay(tester), '100000');
  });

  testWidgets('Percent and negate: 50% = 0.5, 5 +/- = -5', (tester) async {
    await openSci(tester);

    await skey(tester, '5');
    await skey(tester, '0');
    await skey(tester, '%');

    expect(sHistory(tester), '50%');
    expect(sDisplay(tester), '0.5');

    await skey(tester, 'C');
    await skey(tester, '5');
    await skey(tester, '+/-');

    expect(sDisplay(tester), '-5');
  });

  testWidgets('Deg/Rad toggle switches the angle mode', (tester) async {
    await openSci(tester);

    expect(find.text('Deg'), findsOneWidget);
    await skey(tester, 'Deg');
    expect(find.text('Rad'), findsOneWidget);
    await skey(tester, 'Rad');
    expect(find.text('Deg'), findsOneWidget);
  });

  testWidgets('Division by zero shows Error and C recovers', (tester) async {
    await openSci(tester);

    await skey(tester, '1');
    await skey(tester, '÷');
    await skey(tester, '0');
    await skey(tester, '=');

    expect(sDisplay(tester), 'Error');

    await skey(tester, 'C');
    expect(sDisplay(tester), '0');
    expect(sHistory(tester), '');
  });
}
