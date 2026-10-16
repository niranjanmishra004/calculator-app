import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';

/// Taps a keypad/function key. Keys sit after the display in tree order,
/// so `.last` hits the key even when the same glyph is on screen.
Future<void> key(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
}

/// Big number in the calculator display.
String displayText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('display'))).data!;

/// Expression line above the big number.
String historyText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('history'))).data ?? '';

void main() {
  testWidgets('Shows the new layout: top bar and keys', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    // Display starts at 0.
    expect(displayText(tester), '0');
    expect(historyText(tester), '');

    // Top bar: hamburger and settings, no SPLIT pill.
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.text('SPLIT'), findsNothing);

    // No scientific row, no fake status bar.
    for (final label in ['e', 'sin', 'cos', 'deg']) {
      expect(find.text(label), findsNothing);
    }

    // Keypad keys from the mock.
    for (final label in [
      'C',
      '(',
      ')',
      '+',
      '7',
      '8',
      '9',
      '.',
      '0',
      'DEL',
      '=',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    // Minus and divide keep their typographic glyphs on the keys.
    expect(find.text('\u2212'), findsOneWidget);
    expect(find.text('\u00F7'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
  });

  testWidgets('Basic addition with live preview', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '7');
    await key(tester, '+');
    await key(tester, '3');

    // Expression echoes without spaces, main display previews the result.
    expect(historyText(tester), '7+3');
    expect(displayText(tester), '10');

    await key(tester, '=');
    expect(historyText(tester), '7+3');
    expect(displayText(tester), '10');
  });

  testWidgets('Pending operator swap: 5 * then + becomes 5 + 2 = 7', (
    tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '5');
    await key(tester, '*');
    await key(tester, '+');
    await key(tester, '2');

    expect(historyText(tester), '5+2');
    expect(displayText(tester), '7');

    await key(tester, '=');
    expect(historyText(tester), '5+2');
    expect(displayText(tester), '7');
  });

  testWidgets('BODMAS with parentheses (mock expression)', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    for (final c in ['2', '0', '5']) {
      await key(tester, c);
    }
    await key(tester, '+');
    for (final c in ['5', '0']) {
      await key(tester, c);
    }
    await key(tester, '\u00F7');
    await key(tester, '2');
    await key(tester, '\u2212');
    await key(tester, '(');
    for (final c in ['1', '2']) {
      await key(tester, c);
    }
    await key(tester, '*');
    for (final c in ['1', '4']) {
      await key(tester, c);
    }
    await key(tester, ')');

    // 205 + 50/2 - (12*14) = 205 + 25 - 168 = 62.
    expect(historyText(tester), '205+50/2-(12*14)');
    expect(displayText(tester), '62');

    await key(tester, '=');
    expect(historyText(tester), '205+50/2-(12*14)');
    expect(displayText(tester), '62');
  });

  testWidgets('Nested parens and division order', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '2');
    await key(tester, '*');
    await key(tester, '(');
    await key(tester, '3');
    await key(tester, '+');
    await key(tester, '4');
    await key(tester, ')');

    expect(historyText(tester), '2*(3+4)');
    expect(displayText(tester), '14');

    await key(tester, '=');
    expect(displayText(tester), '14');
  });

  testWidgets('Minus after an operator negates the next operand', (
    tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '5');
    await key(tester, '+');
    await key(tester, '\u2212');
    await key(tester, '3');

    expect(historyText(tester), '5+-3');
    expect(displayText(tester), '2');

    await key(tester, '=');
    expect(displayText(tester), '2');
  });

  testWidgets('Leading minus types a negative number', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '\u2212');
    await key(tester, '5');

    expect(historyText(tester), '-5');
    expect(displayText(tester), '-5');

    await key(tester, '=');
    expect(displayText(tester), '-5');
  });

  testWidgets('Trailing operator on equals drops it (5 + = gives 5)', (
    tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '5');
    await key(tester, '+');
    await key(tester, '=');

    expect(historyText(tester), '5+');
    expect(displayText(tester), '5');
  });

  testWidgets('Result continues after equals (62 + 1 = 63)', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    for (final c in ['6', '2']) {
      await key(tester, c);
    }
    await key(tester, '=');
    expect(displayText(tester), '62');

    // Operator continues from the result, digit starts fresh.
    await key(tester, '+');
    await key(tester, '1');
    await key(tester, '=');
    expect(historyText(tester), '62+1');
    expect(displayText(tester), '63');
  });

  testWidgets('DEL removes one character at a time', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '1');
    await key(tester, '2');
    await key(tester, '3');
    expect(displayText(tester), '123');

    await key(tester, 'DEL');
    expect(displayText(tester), '12');
    await key(tester, 'DEL');
    expect(displayText(tester), '1');
    await key(tester, 'DEL');
    expect(displayText(tester), '0');
    expect(historyText(tester), '');
  });

  testWidgets('C clears the entry, then everything', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '5');
    expect(displayText(tester), '5');

    await key(tester, 'C');
    expect(displayText(tester), '0');

    // Second C drops the padded 0; the display still reads 0.
    await key(tester, 'C');
    expect(displayText(tester), '0');
    expect(historyText(tester), '');

    // Typing starts a fresh expression.
    await key(tester, '9');
    expect(displayText(tester), '9');
  });

  testWidgets('Division by zero shows Error and C recovers', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '5');
    await key(tester, '\u00F7');
    await key(tester, '0');
    await key(tester, '=');

    expect(displayText(tester), 'Error');

    await key(tester, 'C');
    expect(displayText(tester), '0');
    expect(historyText(tester), '');
  });

  testWidgets('Decimal point uses a dot separator', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await key(tester, '1');
    await key(tester, '.');
    await key(tester, '5');
    await key(tester, '+');
    await key(tester, '2');
    await key(tester, '.');
    await key(tester, '5');

    expect(historyText(tester), '1.5+2.5');
    expect(displayText(tester), '4');

    await key(tester, '=');
    expect(displayText(tester), '4');
  });

  testWidgets('Parens keys only fire where a paren makes sense', (
    tester,
  ) async {
    await tester.pumpWidget(const CalculatorApp());

    // ")" with nothing open is ignored.
    await key(tester, '5');
    await key(tester, ')');
    await key(tester, '=');
    expect(displayText(tester), '5');

    await key(tester, 'C');
    await key(tester, 'C');
    await key(tester, '2');
    // "(" right after a number is ignored too.
    await key(tester, '(');
    expect(historyText(tester), '2');
  });

  testWidgets('Operator keys are deep blue', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    final colors = tester
        .widgetList<Material>(
          find.ancestor(
            of: find.text('+').last,
            matching: find.byType(Material),
          ),
        )
        .map((m) => m.color);
    expect(colors, contains(const Color(0xFF1E40AF)));
    // Red C and green = keep their colours.
    final cColors = tester
        .widgetList<Material>(
          find.ancestor(of: find.text('C'), matching: find.byType(Material)),
        )
        .map((m) => m.color);
    expect(cColors, contains(const Color(0xFFF87171)));
    final eqColors = tester
        .widgetList<Material>(
          find.ancestor(of: find.text('='), matching: find.byType(Material)),
        )
        .map((m) => m.color);
    expect(eqColors, contains(const Color(0xFF16A34A)));
  });

  testWidgets('Settings sheet toggles haptic feedback', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(find.byType(Switch).evaluate(), isNotEmpty);

    final before = tester.widget<Switch>(find.byType(Switch)).value;
    expect(before, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    // Dismiss by tapping the barrier outside the sheet.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('Menu sheet shows clipboard actions', (tester) async {
    await tester.pumpWidget(const CalculatorApp());

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Copy result'), findsOneWidget);
    expect(find.text('Paste number'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

}
