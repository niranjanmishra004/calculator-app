import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dashboard.dart';

void main() {
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Intentionally no custom fontFamily: the bundled Roboto renders
        // fast everywhere. A missing family name forces per-glyph
        // fallback resolution and looks inconsistent across devices.
      ),
      home: Builder(
        builder: (context) {
          // Follows the device: dark system -> dark calculator,
          // light system -> light calculator. Updates automatically
          // when the system theme changes.
          final dark =
              MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          return CalculatorScreen(dark: dark);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expression model
// ---------------------------------------------------------------------------

/// Every element of the expression under construction. Numbers keep the raw
/// text the user typed ("12", "0.5", "0.") so the display echoes exactly
/// what was entered; everything else is structural.
enum _TokType { num, add, sub, mul, div, lpar, rpar, neg }

class _Tok {
  const _Tok(this.type, [this.text = '']);

  final _TokType type;
  final String text;
}

bool _isBinaryOp(_TokType t) =>
    t == _TokType.add ||
    t == _TokType.sub ||
    t == _TokType.mul ||
    t == _TokType.div;

enum _Op { div, mul, sub, add }

/// Tactile press physics shared by every key: shrink slightly while the
/// pointer is down, spring back on release. One 90ms transform per key —
/// negligible cost, big premium feel on touch.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  var _down = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setDown(true),
      onPointerUp: (_) => _setDown(false),
      onPointerCancel: (_) => _setDown(false),
      child: AnimatedScale(
        scale: _down ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout metrics
// ---------------------------------------------------------------------------

const double _gap = 12.0;
const double _topBarHeight = 56.0;
const double _homeIndicatorHeight = 29.0;
const double _displayMinHeight = 150.0;
const double _phoneFrameWidth = 400.0;


class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, required this.dark});

  final bool dark;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  static const int _maxDigits = 9;

  // The whole expression as a flat token list, e.g.
  // [205] [+] [50] [/] [2] [-] [(] [12] [*] [14] [)]. Parentheses and
  // operator precedence are resolved at evaluation time, so editing is
  // just pushing and popping tokens.
  final List<_Tok> _expr = [];
  bool _justEvaluated = false;
  bool _error = false;
  double? _result;
  final bool _haptics = true;

  // ---------- evaluation (shunting-yard + RPN) ----------

  static int _prec(_TokType t) => switch (t) {
    _TokType.add || _TokType.sub => 1,
    _TokType.mul || _TokType.div => 2,
    _TokType.neg => 3,
    _ => 0,
  };

  /// Evaluates [toks] honouring BODMAS and parentheses. Returns null for
  /// malformed input or math errors (division by zero, overflow).
  static double? _evalTokens(List<_Tok> toks, {bool autoComplete = false}) {
    final t = List<_Tok>.of(toks);
    if (t.isEmpty) return null;
    if (autoComplete) {
      // A trailing operator has no operand yet: drop it so the pending
      // expression can still be previewed.
      while (t.isNotEmpty && _isBinaryOp(t.last.type)) {
        t.removeLast();
      }
      // Close anything the user left open, the same way a real pad would.
      var open = 0;
      for (final x in t) {
        if (x.type == _TokType.lpar) open++;
        if (x.type == _TokType.rpar) open--;
        if (open < 0) return null;
      }
      for (var i = 0; i < open; i++) {
        t.add(const _Tok(_TokType.rpar));
      }
    }

    final rpn = <_Tok>[];
    final stack = <_Tok>[];
    var expectValue = true;

    for (final tok in t) {
      switch (tok.type) {
        case _TokType.num:
          rpn.add(tok);
          expectValue = false;
        case _TokType.lpar:
          stack.add(tok);
          expectValue = true;
        case _TokType.rpar:
          while (stack.isNotEmpty && stack.last.type != _TokType.lpar) {
            rpn.add(stack.removeLast());
          }
          if (stack.isEmpty) return null;
          stack.removeLast();
          expectValue = false;
        case _TokType.add:
        case _TokType.sub:
        case _TokType.mul:
        case _TokType.div:
        case _TokType.neg:
          if (expectValue) {
            // Value position: only a minus is meaningful, as unary
            // negation (there is no +/- key, this is how you type -5).
            if (tok.type == _TokType.sub) {
              stack.add(const _Tok(_TokType.neg));
            } else if (tok.type == _TokType.neg) {
              stack.add(tok);
            } else {
              return null;
            }
          } else {
            while (stack.isNotEmpty &&
                stack.last.type != _TokType.lpar &&
                _prec(stack.last.type) >= _prec(tok.type)) {
              rpn.add(stack.removeLast());
            }
            stack.add(tok);
          }
      }
    }
    while (stack.isNotEmpty) {
      final x = stack.removeLast();
      if (x.type == _TokType.lpar) return null;
      rpn.add(x);
    }

    final vals = <double>[];
    for (final tok in rpn) {
      switch (tok.type) {
        case _TokType.num:
          vals.add(_parseTok(tok.text));
        case _TokType.neg:
          if (vals.isEmpty) return null;
          vals.add(-vals.removeLast());
        case _TokType.add:
        case _TokType.sub:
        case _TokType.mul:
        case _TokType.div:
          if (vals.length < 2) return null;
          final b = vals.removeLast();
          final a = vals.removeLast();
          switch (tok.type) {
            case _TokType.add:
              vals.add(a + b);
            case _TokType.sub:
              vals.add(a - b);
            case _TokType.mul:
              vals.add(a * b);
            case _TokType.div:
              if (b == 0) return null;
              vals.add(a / b);
            default:
              return null;
          }
        case _TokType.lpar:
        case _TokType.rpar:
          return null; // defensive: unmatched paren survived
      }
    }
    if (vals.length != 1) return null;
    final r = vals.single;
    if (r.isNaN || r.isInfinite) return null;
    return r;
  }

  // ---------- formatting ----------

  static String _cleanRaw(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    final a = v.abs();
    if (a != 0 && (a >= 1e12 || a < 1e-9)) {
      return v.toStringAsExponential(5);
    }
    var r = double.parse(v.toStringAsFixed(8));
    if (r == 0) r = 0; // kill -0
    if (r == r.roundToDouble()) return r.round().toString();
    var s = r.toString();
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  static double _parseTok(String raw) =>
      double.tryParse(raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw) ?? 0;

  static int _digitCount(String raw) =>
      raw.replaceAll('-', '').replaceAll('.', '').length;

  static String _glyph(_TokType t) => switch (t) {
    _TokType.add => '+',
    _TokType.sub => '-',
    _TokType.mul => '*',
    _TokType.div => '/',
    _TokType.lpar => '(',
    _TokType.rpar => ')',
    _TokType.neg => '-',
    _TokType.num => '',
  };

  static String _opKeyLabel(_Op op) => switch (op) {
    _Op.add => '+',
    _Op.sub => '\u2212',
    _Op.mul => '*',
    _Op.div => '\u00F7',
  };

  /// The expression exactly as typed, e.g. "205+50/2-(12*14)".
  String get _historyText {
    final parts = <String>[];
    for (final t in _expr) {
      parts.add(t.type == _TokType.num ? t.text : _glyph(t.type));
    }
    return parts.join('');
  }

  double? get _displayValue {
    if (_error) return null;
    if (_justEvaluated) return _result;
    return _evalTokens(_expr, autoComplete: true);
  }

  /// True while the only thing on the pad is a single number being typed
  /// ("5", "2.", "-5"): nothing binary or a closing paren sits before it.
  bool get _exprIsBareNumber {
    if (_expr.isEmpty) return false;
    for (var i = 0; i < _expr.length - 1; i++) {
      final t = _expr[i].type;
      if (_isBinaryOp(t) || t == _TokType.rpar) return false;
    }
    return _expr.last.type == _TokType.num;
  }

  String get _displayText {
    if (_error) return 'Error';
    if (!_justEvaluated && _exprIsBareNumber) {
      // Echo the raw digits so the "." or trailing "0" just pressed
      // stays visible instead of being normalised away.
      return _historyText;
    }
    final v = _displayValue;
    if (v == null) return '0';
    return _cleanRaw(v);
  }

  void _reset() {
    _expr.clear();
    _justEvaluated = false;
    _result = null;
    _error = false;
  }

  // ---------- input handlers ----------

  void _onDigit(String d) {
    setState(() {
      if (_error) _reset();
      if (_justEvaluated) {
        // Fresh calculation after a finished one.
        _expr.clear();
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _TokType.num) {
        if (_digitCount(last.text) >= _maxDigits) return;
        _expr.last = _Tok(_TokType.num, last.text == '0' ? d : last.text + d);
      } else {
        _expr.add(_Tok(_TokType.num, d));
      }
    });
  }

  void _onDecimal() {
    setState(() {
      if (_error) _reset();
      if (_justEvaluated) {
        _expr.clear();
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _TokType.num) {
        if (!last.text.contains('.')) {
          _expr.last = _Tok(_TokType.num, '${last.text}.');
        }
      } else {
        _expr.add(const _Tok(_TokType.num, '0.'));
      }
    });
  }

  void _onOperator(_Op op) {
    if (_error) return;
    setState(() {
      if (_justEvaluated) {
        // Continue from the result: the expression becomes [result].
        _expr
          ..clear()
          ..add(_Tok(_TokType.num, _cleanRaw(_result ?? 0)));
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      final lastIsBinOp = last != null && _isBinaryOp(last.type);
      if (lastIsBinOp && op != _Op.sub) {
        // Swap the pending operator: "5 ×" then "+" gives "5 +".
        _expr.removeLast();
        _expr.add(_Tok(_opTokType(op)));
        return;
      }
      if (last == null ||
          last.type == _TokType.lpar ||
          last.type == _TokType.neg ||
          lastIsBinOp) {
        // Value position: a minus becomes unary negation so negative
        // operands stay reachable now that the +/- key is gone.
        if (op == _Op.sub) _expr.add(const _Tok(_TokType.neg));
        return;
      }
      _expr.add(_Tok(_opTokType(op)));
    });
  }

  static _TokType _opTokType(_Op op) => switch (op) {
    _Op.add => _TokType.add,
    _Op.sub => _TokType.sub,
    _Op.mul => _TokType.mul,
    _Op.div => _TokType.div,
  };

  void _onOpenParen() {
    if (_error) return;
    setState(() {
      if (_justEvaluated) {
        _expr.clear();
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null &&
          last.type != _TokType.lpar &&
          last.type != _TokType.neg &&
          !_isBinaryOp(last.type)) {
        return; // after a number or ")": nothing sensible to open
      }
      _expr.add(const _Tok(_TokType.lpar));
    });
  }

  void _onCloseParen() {
    if (_error) return;
    setState(() {
      final last = _expr.isEmpty ? null : _expr.last;
      if (last == null) return;
      if (last.type != _TokType.num && last.type != _TokType.rpar) return;
      var open = 0;
      for (final t in _expr) {
        if (t.type == _TokType.lpar) open++;
        if (t.type == _TokType.rpar) open--;
      }
      if (open <= 0) return;
      _expr.add(const _Tok(_TokType.rpar));
    });
  }

  void _onDelete() {
    if (_error) return;
    setState(() {
      if (_justEvaluated) {
        // Step back into editing the expression that produced the result.
        _justEvaluated = false;
        _result = null;
      }
      if (_expr.isEmpty) return;
      final last = _expr.last;
      if (last.type == _TokType.num && last.text.length > 1) {
        _expr.last = _Tok(
          _TokType.num,
          last.text.substring(0, last.text.length - 1),
        );
      } else {
        _expr.removeLast();
      }
    });
  }

  void _onClear() {
    // One tap clears the whole screen: expression, result and error
    // state are all dropped, so the pad always restarts from 0.
    setState(_reset);
  }

  void _onEquals() {
    if (_error || _expr.isEmpty) return;
    final r = _evalTokens(_expr, autoComplete: true);
    setState(() {
      if (r == null) {
        _error = true;
        _result = null;
      } else {
        _result = r;
        _justEvaluated = true;
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final label = event.character;
    if (label != null && label.length == 1) {
      final c = label;
      if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
        _onDigit(c);
        return KeyEventResult.handled;
      }
      switch (c) {
        case '+':
          _onOperator(_Op.add);
          return KeyEventResult.handled;
        case '-':
          _onOperator(_Op.sub);
          return KeyEventResult.handled;
        case '*':
          _onOperator(_Op.mul);
          return KeyEventResult.handled;
        case '/':
          _onOperator(_Op.div);
          return KeyEventResult.handled;
        case '(':
          _onOpenParen();
          return KeyEventResult.handled;
        case ')':
          _onCloseParen();
          return KeyEventResult.handled;
        case '=':
          _onEquals();
          return KeyEventResult.handled;
        case '.':
        case ',':
          _onDecimal();
          return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _onEquals();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _onClear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _onDelete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- palette (reference mock) ----------
  bool get _dark => widget.dark;
  Color get _bg => _dark ? Colors.black : Colors.white;
  Color get _backdrop => _dark ? const Color(0xFF1C1C1E) : const Color(0xFFD1D1D6);
  Color get _displayFg => _dark ? Colors.white : Colors.black;
  Color get _topFg => _dark ? Colors.white : Colors.black;
  // Neutral keys: numbers, parentheses and DEL.
  Color get _keyBg => _dark ? const Color(0xFF333333) : Colors.white;
  Color get _keyFg => _dark ? Colors.white : Colors.black;
  static const Color _clearBgDark = Color(0xFFE5484D);
  static const Color _clearBgLight = Color(0xFFF87171);
  static const Color _opBg = Color(0xFF1D4ED8);
  static const Color _opFg = Colors.white;
  static const Color _eqBg = Color(0xFF16A34A);
  static const Color _eqFg = Colors.white;

  // ---------- keys ----------
  Widget _key({
    required String label,
    required Color bg,
    required Color fg,
    required double size,
    required VoidCallback onTap,
    double? height,
    double fontSize = 32,
    FontWeight weight = FontWeight.w400,
    bool bordered = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(size * 0.22),
      // Pale keys on a white background need an outline to keep their
      // edge defined. No-op in dark mode.
      side: bordered && !_dark
          ? BorderSide(color: Colors.black.withValues(alpha: 0.12), width: 1)
          : BorderSide.none,
    );
    // Splash must stay visible on both dark and light keys.
    final splashBase = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return _Pressable(
      child: Material(
        color: bg,
        shape: shape,
        elevation: 0,
        child: InkWell(
          customBorder: shape,
          splashColor: splashBase.withValues(alpha: 0.22),
          highlightColor: splashBase.withValues(alpha: 0.12),
          onTap: () {
            if (_haptics) HapticFeedback.lightImpact();
            onTap();
          },
          child: SizedBox(
            width: size,
            height: height ?? size,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  fontWeight: weight,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad(double d) {
    Widget row(List<Widget> cells) {
      final spaced = <Widget>[];
      for (var i = 0; i < cells.length; i++) {
        spaced.add(cells[i]);
        if (i != cells.length - 1) spaced.add(const SizedBox(width: _gap));
      }
      return SizedBox(
        height: d,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: spaced,
        ),
      );
    }

    Widget num(String l, VoidCallback fn) => _key(
          label: l,
          bg: _keyBg,
          fg: _keyFg,
          size: d,
          fontSize: 30,
          bordered: true,
          onTap: fn,
        );

    // The operator waiting for its right operand renders inverted,
    // like physical pads that light up the pending key.
    bool pendingOp(_Op o) =>
        !_error &&
        !_justEvaluated &&
        _expr.isNotEmpty &&
        _expr.last.type == _opTokType(o);

    Widget op(_Op o) {
      final pending = pendingOp(o);
      return _key(
        label: _opKeyLabel(o),
        bg: pending ? Colors.white : _opBg,
        fg: pending ? _opBg : _opFg,
        size: d,
        fontSize: 36,
        bordered: pending,
        onTap: () => _onOperator(o),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          _key(
            label: 'C',
            bg: _dark ? _clearBgDark : _clearBgLight,
            fg: _opFg,
            size: d,
            fontSize: 28,
            weight: FontWeight.w600,
            onTap: _onClear,
          ),
          num('(', _onOpenParen),
          num(')', _onCloseParen),
          op(_Op.add),
        ]),
        const SizedBox(height: _gap),
        row([
          num('7', () => _onDigit('7')),
          num('8', () => _onDigit('8')),
          num('9', () => _onDigit('9')),
          op(_Op.sub),
        ]),
        const SizedBox(height: _gap),
        row([
          num('4', () => _onDigit('4')),
          num('5', () => _onDigit('5')),
          num('6', () => _onDigit('6')),
          op(_Op.mul),
        ]),
        const SizedBox(height: _gap),
        row([
          num('3', () => _onDigit('3')),
          num('2', () => _onDigit('2')),
          num('1', () => _onDigit('1')),
          op(_Op.div),
        ]),
        const SizedBox(height: _gap),
        row([
          num('.', _onDecimal),
          num('0', () => _onDigit('0')),
          _key(
            label: 'DEL',
            bg: _keyBg,
            fg: _keyFg,
            size: d,
            fontSize: 15,
            weight: FontWeight.w600,
            bordered: true,
            onTap: _onDelete,
          ),
          _key(
            label: '=',
            bg: _eqBg,
            fg: _eqFg,
            size: d,
            fontSize: 36,
            onTap: _onEquals,
          ),
        ]),
      ],
    );
  }

  // ---------- chrome ----------
  Widget _topBar() {
    return SizedBox(
      height: _topBarHeight,
      child: Row(
        children: [
          IconButton(
            onPressed: _openDashboard,
            tooltip: 'Other calculators',
            splashRadius: 22,
            icon: Icon(Icons.menu, color: _topFg, size: 26),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _display() {
    final len = _displayText.length;
    final fontSize = len <= 6
        ? 96.0
        : len <= 8
            ? 78.0
            : len <= 11
                ? 62.0
                : 50.0;
    final expr = _historyText;
    return Expanded(
      child: Container(
        width: double.infinity,
        alignment: Alignment.bottomRight,
        padding: const EdgeInsets.only(right: 22, bottom: 8, left: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Reserved line keeps the big number from jumping between
            // states; calculators must update crisply, no fade. It stays
            // in the tree (empty) so the display height never shifts.
            SizedBox(
              height: 30,
              child: Text(
                expr,
                key: const Key('history'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _displayFg.withValues(alpha: 0.45),
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                  height: 1.1,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              // Glides between size steps as numbers grow instead of
              // jumping, so long results feel smooth rather than janky.
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: _displayFg,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                ),
                child: Text(
                  _displayText,
                  key: const Key('display'),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: _dark ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _phoneBody(double diameter) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _display(),
            _keypad(diameter),
            _homeIndicator(),
          ],
        ),
      ),
    );
  }

  void _openDashboard() {
    Navigator.push(
      context,
      smoothPageRoute(DashboardScreen(dark: _dark, haptics: _haptics)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backdrop,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final framed = constraints.maxWidth > 560;
          final phoneWidth = framed ? _phoneFrameWidth : constraints.maxWidth;
          final phoneHeight = framed
              ? (constraints.maxHeight - 48).clamp(600.0, 880.0)
              : constraints.maxHeight;

          // Button size fits both width and height so the keypad plus
          // the two-line display never overflow, even on short screens.
          final dFromWidth = (phoneWidth - 36 - _gap * 3) / 4;
          final sysPad = MediaQuery.of(context).padding;
          final budget = phoneHeight -
              sysPad.top -
              sysPad.bottom -
              _topBarHeight -
              _homeIndicatorHeight -
              _displayMinHeight;
          final dFromHeight = (budget - 4 * _gap) / 5;
          final diameter = (dFromWidth < dFromHeight ? dFromWidth : dFromHeight)
              .clamp(34.0, 96.0);

          Widget phone = SizedBox(
            width: phoneWidth,
            height: phoneHeight,
            child: _phoneBody(diameter),
          );

          if (framed) {
            phone = Container(
              width: phoneWidth,
              height: phoneHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(54),
                border: Border.all(
                  color: Colors.black.withValues(alpha: _dark ? 0.5 : 0.15),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: phone,
            );
          }

          return Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Container(
              color: framed ? _backdrop : _bg,
              alignment: Alignment.center,
              child: phone,
            ),
          );
        },
      ),
    );
  }
}
