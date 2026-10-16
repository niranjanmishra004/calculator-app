import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Scientific calculator screen
// ---------------------------------------------------------------------------
//
// Opened from the hamburger menu ("Scientific calculator"). A full
// scientific pad: trig + inverse trig (2nd), hyperbolic functions, powers,
// roots, logarithms, factorial, constants, EE entry, memory keys and a
// Deg/Rad angle toggle. The back arrow returns to the standard pad.
//
// The expression is a flat token list evaluated with shunting-yard + RPN,
// the same architecture as the standard pad, extended with prefix
// functions (auto-opening parenthesis), postfix operators, constants and
// a Deg/Rad-aware math layer.

/// Token kinds of the scientific expression under construction.
enum _ST {
  num,
  add,
  sub,
  mul,
  div,
  pow,
  yroot,
  neg,
  lp,
  rp,
  fn,
  post,
  pi,
  euler,
}

/// Prefix functions. All auto-insert an opening parenthesis, so the
/// expression always reads like "sin(30)" or "²√(9)".
enum _SFn {
  sin,
  cos,
  tan,
  asin,
  acos,
  atan,
  sinh,
  cosh,
  tanh,
  asinh,
  acosh,
  atanh,
  ln,
  log10,
  exp,
  pow10,
  sqrt,
  cbrt,
  recip,
}

/// Postfix operators, applied to the value just entered ("5!" → 120).
enum _SPost { sq, cube, fact, pct }

class _STok {
  const _STok(this.type, [this.text = '']) : fn = null, post = null;
  const _STok.fn(this.fn) : type = _ST.fn, text = '', post = null;
  const _STok.post(this.post) : type = _ST.post, text = '', fn = null;

  final _ST type;
  final String text;
  final _SFn? fn;
  final _SPost? post;
}

bool _isBin(_ST t) =>
    t == _ST.add ||
    t == _ST.sub ||
    t == _ST.mul ||
    t == _ST.div ||
    t == _ST.pow ||
    t == _ST.yroot;

/// A token after which a value may legally continue the expression.
bool _endsValue(_ST t) =>
    t == _ST.num ||
    t == _ST.rp ||
    t == _ST.pi ||
    t == _ST.euler ||
    t == _ST.post;

/// Tactile press physics for the scientific keys (mirrors the standard
/// pad): shrink slightly while the pointer is down, spring back on release.
class _SciPressable extends StatefulWidget {
  const _SciPressable({required this.child});

  final Widget child;

  @override
  State<_SciPressable> createState() => _SciPressableState();
}

class _SciPressableState extends State<_SciPressable> {
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

class ScientificScreen extends StatefulWidget {
  const ScientificScreen({
    super.key,
    required this.dark,
    required this.haptics,
  });

  final bool dark;
  final bool haptics;

  @override
  State<ScientificScreen> createState() => _ScientificScreenState();
}

class _ScientificScreenState extends State<ScientificScreen> {
  static const int _maxDigits = 12;

  final List<_STok> _expr = [];
  bool _justEvaluated = false;
  bool _error = false;
  double? _result;

  // Scientific state: 2nd-shift, angle mode and memory.
  bool _second = false;
  bool _deg = true;
  double _mem = 0;
  bool _memSet = false;
  final math.Random _rand = math.Random();

  static const List<_SFn> _trigFns = [_SFn.sin, _SFn.cos, _SFn.tan];
  static const List<_SFn> _invTrigFns = [_SFn.asin, _SFn.acos, _SFn.atan];
  static const List<_SFn> _hypFns = [_SFn.sinh, _SFn.cosh, _SFn.tanh];
  static const List<_SFn> _invHypFns = [_SFn.asinh, _SFn.acosh, _SFn.atanh];

  // ---------- evaluation (shunting-yard + RPN) ----------

  static int _prec(_ST t) => switch (t) {
    _ST.add || _ST.sub => 1,
    _ST.mul || _ST.div => 2,
    _ST.neg => 3,
    _ST.pow || _ST.yroot => 4,
    _ => 0,
  };

  static bool _rightAssoc(_ST t) => t == _ST.pow || t == _ST.yroot;

  /// Evaluates [toks] honouring precedence, parentheses and functions.
  /// Returns null for malformed input or math errors.
  static double? _eval(
    List<_STok> toks, {
    bool autoComplete = false,
    required bool deg,
  }) {
    final t = List<_STok>.of(toks);
    if (t.isEmpty) return null;
    if (autoComplete) {
      // A trailing operator has no operand yet: drop it so the pending
      // expression can still be previewed.
      while (t.isNotEmpty &&
          (_isBin(t.last.type) || t.last.type == _ST.neg)) {
        t.removeLast();
      }
      // Close anything the user left open, the same way a real pad would.
      var open = 0;
      for (final x in t) {
        if (x.type == _ST.lp) open++;
        if (x.type == _ST.rp) open--;
        if (open < 0) return null;
      }
      for (var i = 0; i < open; i++) {
        t.add(const _STok(_ST.rp));
      }
    }

    final rpn = <_STok>[];
    final stack = <_STok>[];
    var expectValue = true;

    for (final tok in t) {
      switch (tok.type) {
        case _ST.num:
        case _ST.pi:
        case _ST.euler:
          rpn.add(tok);
          expectValue = false;
        case _ST.fn:
          stack.add(tok);
          expectValue = true;
        case _ST.post:
          // Postfix binds to the value just emitted; anything else is
          // malformed (the pad never builds it).
          if (expectValue) return null;
          rpn.add(tok);
        case _ST.lp:
          stack.add(tok);
          expectValue = true;
        case _ST.rp:
          while (stack.isNotEmpty && stack.last.type != _ST.lp) {
            rpn.add(stack.removeLast());
          }
          if (stack.isEmpty) return null;
          stack.removeLast();
          if (stack.isNotEmpty && stack.last.type == _ST.fn) {
            rpn.add(stack.removeLast());
          }
          expectValue = false;
        case _ST.add:
        case _ST.sub:
        case _ST.mul:
        case _ST.div:
        case _ST.pow:
        case _ST.yroot:
        case _ST.neg:
          if (expectValue) {
            // Value position: only a minus is meaningful, as unary
            // negation (this is how "-5" and "5+-3" are typed).
            if (tok.type == _ST.sub || tok.type == _ST.neg) {
              stack.add(const _STok(_ST.neg));
            } else {
              return null;
            }
          } else {
            // Powers and y-roots are right-associative; everything else
            // is left-associative. Functions bind tighter than all.
            while (stack.isNotEmpty &&
                stack.last.type != _ST.lp &&
                stack.last.type != _ST.fn &&
                (_prec(stack.last.type) > _prec(tok.type) ||
                    (_prec(stack.last.type) == _prec(tok.type) &&
                        !_rightAssoc(tok.type)))) {
              rpn.add(stack.removeLast());
            }
            stack.add(tok);
            expectValue = true;
          }
      }
    }
    while (stack.isNotEmpty) {
      final x = stack.removeLast();
      if (x.type == _ST.lp) return null;
      rpn.add(x);
    }

    final vals = <double>[];
    for (final tok in rpn) {
      switch (tok.type) {
        case _ST.num:
          vals.add(_parseNum(tok.text));
        case _ST.pi:
          vals.add(math.pi);
        case _ST.euler:
          vals.add(math.e);
        case _ST.neg:
          if (vals.isEmpty) return null;
          vals.add(-vals.removeLast());
        case _ST.post:
          if (vals.isEmpty) return null;
          final v = _applyPost(tok.post!, vals.removeLast());
          if (v == null) return null;
          vals.add(v);
        case _ST.fn:
          if (vals.isEmpty) return null;
          final v = _applyFn(tok.fn!, vals.removeLast(), deg);
          if (v == null) return null;
          vals.add(v);
        case _ST.add:
        case _ST.sub:
        case _ST.mul:
        case _ST.div:
        case _ST.pow:
        case _ST.yroot:
          if (vals.length < 2) return null;
          final b = vals.removeLast();
          final a = vals.removeLast();
          final v = _applyBin(tok.type, a, b);
          if (v == null) return null;
          vals.add(v);
        case _ST.lp:
        case _ST.rp:
          return null; // defensive: unmatched paren survived
      }
    }
    if (vals.length != 1) return null;
    final r = vals.single;
    if (r.isNaN || r.isInfinite) return null;
    return r;
  }

  static double? _applyBin(_ST op, double a, double b) => switch (op) {
    _ST.add => a + b,
    _ST.sub => a - b,
    _ST.mul => a * b,
    _ST.div => b == 0 ? null : a / b,
    _ST.pow => () {
      final v = math.pow(a, b).toDouble();
      return v.isNaN ? null : v;
    }(),
    _ST.yroot => _yroot(a, b),
    _ => null,
  };

  /// y-root of x, i.e. x^(1/y), with real results for odd integer roots
  /// of negative numbers (³√(-27) = -3).
  static double? _yroot(double y, double x) {
    if (y == 0) return null;
    if (x >= 0) {
      final r = math.pow(x, 1 / y).toDouble();
      return r.isNaN ? null : r;
    }
    final n = y.round();
    if ((y - n).abs() < 1e-9 && n.isOdd) {
      return -math.pow(-x, 1 / y).toDouble();
    }
    return null;
  }

  static double? _applyPost(_SPost p, double x) => switch (p) {
    _SPost.sq => x * x,
    _SPost.cube => x * x * x,
    _SPost.fact => _fact(x),
    _SPost.pct => x / 100,
  };

  static double? _fact(double v) {
    if (v < 0 || v > 170) return null;
    final n = v.round();
    if ((v - n).abs() > 1e-9) return null;
    var r = 1.0;
    for (var i = 2; i <= n; i++) {
      r *= i;
    }
    return r;
  }

  static double? _applyFn(_SFn f, double x, bool deg) {
    double rad(double d) => deg ? d * math.pi / 180.0 : d;
    double out(double r) => deg ? r * 180.0 / math.pi : r;
    switch (f) {
      case _SFn.sin:
        return math.sin(rad(x));
      case _SFn.cos:
        return math.cos(rad(x));
      case _SFn.tan:
        return math.tan(rad(x));
      case _SFn.asin:
        if (x < -1 || x > 1) return null;
        return out(math.asin(x));
      case _SFn.acos:
        if (x < -1 || x > 1) return null;
        return out(math.acos(x));
      case _SFn.atan:
        return out(math.atan(x));
      case _SFn.sinh:
        return (math.exp(x) - math.exp(-x)) / 2;
      case _SFn.cosh:
        return (math.exp(x) + math.exp(-x)) / 2;
      case _SFn.tanh:
        final c = (math.exp(x) + math.exp(-x)) / 2;
        if (c == 0) return null;
        return ((math.exp(x) - math.exp(-x)) / 2) / c;
      case _SFn.asinh:
        return math.log(x + math.sqrt(x * x + 1));
      case _SFn.acosh:
        if (x < 1) return null;
        return math.log(x + math.sqrt(x * x - 1));
      case _SFn.atanh:
        if (x <= -1 || x >= 1) return null;
        return 0.5 * math.log((1 + x) / (1 - x));
      case _SFn.ln:
        if (x <= 0) return null;
        return math.log(x);
      case _SFn.log10:
        if (x <= 0) return null;
        return math.log(x) / math.log(10);
      case _SFn.exp:
        return math.exp(x);
      case _SFn.pow10:
        return math.pow(10, x).toDouble();
      case _SFn.sqrt:
        if (x < 0) return null;
        return math.sqrt(x);
      case _SFn.cbrt:
        return x >= 0
            ? math.pow(x, 1 / 3).toDouble()
            : -math.pow(-x, 1 / 3).toDouble();
      case _SFn.recip:
        if (x == 0) return null;
        return 1 / x;
    }
  }

  // ---------- formatting ----------

  static String _cleanSci(double v) {
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

  /// Parses a typed number, tolerating an in-progress decimal point or
  /// EE exponent ("5.", "1e", "1e-").
  static double _parseNum(String raw) {
    var s = raw;
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    s = s.replaceFirst(RegExp(r'e[+-]?$'), '');
    return double.tryParse(s) ?? 0;
  }

  static int _digitCount(String raw) =>
      raw.replaceAll('-', '').replaceAll('.', '').replaceAll('e', '').length;

  // Names only: the auto-inserted "(" token renders the parenthesis.
  static String _fnText(_SFn f) => switch (f) {
    _SFn.sin => 'sin',
    _SFn.cos => 'cos',
    _SFn.tan => 'tan',
    _SFn.asin => 'asin',
    _SFn.acos => 'acos',
    _SFn.atan => 'atan',
    _SFn.sinh => 'sinh',
    _SFn.cosh => 'cosh',
    _SFn.tanh => 'tanh',
    _SFn.asinh => 'asinh',
    _SFn.acosh => 'acosh',
    _SFn.atanh => 'atanh',
    _SFn.ln => 'ln',
    _SFn.log10 => 'log10',
    _SFn.exp => 'e^',
    _SFn.pow10 => '10^',
    _SFn.sqrt => '²√',
    _SFn.cbrt => '³√',
    _SFn.recip => '1/',
  };

  static String _postText(_SPost p) => switch (p) {
    _SPost.sq => '²',
    _SPost.cube => '³',
    _SPost.fact => '!',
    _SPost.pct => '%',
  };

  static String _tokText(_STok t) => switch (t.type) {
    _ST.num => t.text,
    _ST.add => '+',
    _ST.sub => '−',
    _ST.mul => '×',
    _ST.div => '÷',
    _ST.pow => '^',
    _ST.yroot => 'y√',
    _ST.neg => '-',
    _ST.lp => '(',
    _ST.rp => ')',
    _ST.pi => 'π',
    _ST.euler => 'e',
    _ST.fn => _fnText(t.fn!),
    _ST.post => _postText(t.post!),
  };

  /// The expression exactly as typed, e.g. "sin(30)+5!".
  String get _historyText => _expr.map(_tokText).join('');

  double? get _displayValue {
    if (_error) return null;
    if (_justEvaluated) return _result;
    return _eval(_expr, autoComplete: true, deg: _deg);
  }

  /// True while the only thing on the pad is a single number being typed:
  /// nothing binary or a closing paren sits before it.
  bool get _exprIsBareNumber {
    if (_expr.isEmpty) return false;
    for (var i = 0; i < _expr.length - 1; i++) {
      final t = _expr[i].type;
      if (_isBin(t) || t == _ST.rp) return false;
    }
    return _expr.last.type == _ST.num;
  }

  String get _displayText {
    if (_error) return 'Error';
    if (!_justEvaluated && _exprIsBareNumber) return _historyText;
    final v = _displayValue;
    if (v == null) return '0';
    return _cleanSci(v);
  }

  void _reset() {
    _expr.clear();
    _justEvaluated = false;
    _result = null;
    _error = false;
  }

  /// Drops any finished/error state so the next press starts fresh.
  void _fresh() {
    if (_error) _reset();
    if (_justEvaluated) {
      _expr.clear();
      _justEvaluated = false;
      _result = null;
    }
  }

  /// True when an operand (number, constant, function, "(") may follow.
  /// After a value ("2", ")", "π", "5!"), inserts an implicit "×" so
  /// "2π" and "2sin(30)" just work.
  bool _needOperand() {
    if (_expr.isEmpty) return true;
    final l = _expr.last.type;
    if (_endsValue(l)) {
      _expr.add(const _STok(_ST.mul));
      return true;
    }
    return l == _ST.lp || _isBin(l) || l == _ST.neg;
  }

  // ---------- input handlers ----------

  void _onDigit(String d) {
    setState(() {
      _fresh();
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _ST.num) {
        if (_digitCount(last.text) >= _maxDigits) return;
        final t = last.text;
        _expr.last = _STok(
          _ST.num,
          t == '0' ? d : (t == '-0' ? '-$d' : t + d),
        );
      } else {
        _expr.add(_STok(_ST.num, d));
      }
    });
  }

  void _onDecimal() {
    setState(() {
      _fresh();
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _ST.num) {
        // Exponents stay integral; the mantissa takes the point.
        if (!last.text.contains('e') && !last.text.contains('.')) {
          _expr.last = _STok(_ST.num, '${last.text}.');
        }
      } else {
        _expr.add(const _STok(_ST.num, '0.'));
      }
    });
  }

  /// EE: exponent entry, so "1 EE 5" types the number 1e5.
  void _onEE() {
    setState(() {
      if (_error) _reset();
      if (_justEvaluated) {
        _expr
          ..clear()
          ..add(_STok(_ST.num, _cleanSci(_result ?? 0)));
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last == null || last.type != _ST.num) return;
      if (last.text.contains('e')) return;
      var mantissa = last.text;
      if (mantissa.endsWith('.')) {
        mantissa = mantissa.substring(0, mantissa.length - 1);
      }
      if (mantissa.isEmpty || mantissa == '-') return;
      _expr.last = _STok(_ST.num, '${last.text}e');
    });
  }

  /// +/-: flips the sign of the number being entered.
  void _onNegate() {
    setState(() {
      if (_error) _reset();
      if (_justEvaluated) {
        _expr
          ..clear()
          ..add(_STok(_ST.num, _cleanSci(_result ?? 0)));
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _ST.num) {
        final t = last.text;
        _expr.last = _STok(
          _ST.num,
          t.startsWith('-') ? t.substring(1) : '-$t',
        );
        return;
      }
      if (last == null ||
          last.type == _ST.lp ||
          _isBin(last.type) ||
          last.type == _ST.neg) {
        _expr.add(const _STok(_ST.neg));
      }
    });
  }

  void _onBinary(_ST op) {
    if (_error) return;
    setState(() {
      if (_justEvaluated) {
        // Continue from the result: the expression becomes [result].
        _expr
          ..clear()
          ..add(_STok(_ST.num, _cleanSci(_result ?? 0)));
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      // A minus right after EE types a negative exponent ("1e-5").
      if (op == _ST.sub &&
          last != null &&
          last.type == _ST.num &&
          RegExp(r'e$').hasMatch(last.text)) {
        _expr.last = _STok(_ST.num, '${last.text}-');
        return;
      }
      if (last == null ||
          last.type == _ST.lp ||
          last.type == _ST.neg ||
          _isBin(last.type)) {
        // Value position: a minus becomes unary negation so negative
        // operands stay reachable.
        if (op == _ST.sub) _expr.add(const _STok(_ST.neg));
        return;
      }
      if (_endsValue(last.type)) {
        final lastIsBinOp = _isBin(last.type);
        if (lastIsBinOp && op != _ST.sub) {
          // Swap the pending operator: "5 ×" then "+" gives "5 +".
          _expr.removeLast();
        }
        _expr.add(_STok(op));
      }
    });
  }

  void _onFunc(_SFn f) {
    setState(() {
      _fresh();
      if (!_needOperand()) return;
      _expr.add(_STok.fn(f));
      _expr.add(const _STok(_ST.lp));
    });
  }

  void _onPostfix(_SPost p) {
    if (_error) return;
    setState(() {
      if (_justEvaluated) {
        _expr
          ..clear()
          ..add(_STok(_ST.num, _cleanSci(_result ?? 0)));
        _justEvaluated = false;
        _result = null;
      }
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && _endsValue(last.type)) {
        _expr.add(_STok.post(p));
      }
    });
  }

  void _onConst(_ST c) {
    setState(() {
      _fresh();
      if (!_needOperand()) return;
      _expr.add(_STok(c));
    });
  }

  void _onOpenParen() {
    setState(() {
      if (_error) return;
      if (_justEvaluated) {
        _expr.clear();
        _justEvaluated = false;
        _result = null;
      }
      if (!_needOperand()) return;
      // _needOperand already inserted "×" after a value; only open when
      // the position is genuinely empty of a value.
      if (_expr.isNotEmpty && _endsValue(_expr.last.type)) return;
      _expr.add(const _STok(_ST.lp));
    });
  }

  void _onCloseParen() {
    if (_error) return;
    setState(() {
      final last = _expr.isEmpty ? null : _expr.last;
      if (last == null) return;
      if (!_endsValue(last.type)) return;
      var open = 0;
      for (final t in _expr) {
        if (t.type == _ST.lp) open++;
        if (t.type == _ST.rp) open--;
      }
      if (open <= 0) return;
      _expr.add(const _STok(_ST.rp));
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
      if (last.type == _ST.num && last.text.length > 1) {
        _expr.last = _STok(
          _ST.num,
          last.text.substring(0, last.text.length - 1),
        );
      } else {
        _expr.removeLast();
      }
    });
  }

  void _onClear() {
    // One tap clears the whole screen: expression, result and error.
    setState(_reset);
  }

  void _onEquals() {
    if (_error || _expr.isEmpty) return;
    final r = _eval(_expr, autoComplete: true, deg: _deg);
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

  // ---------- memory ----------

  void _onMemoryClear() {
    setState(() {
      _mem = 0;
      _memSet = false;
    });
  }

  void _onMemoryAdd(bool add) {
    setState(() {
      final v = _displayValue;
      if (v == null) return;
      _mem = add ? _mem + v : _mem - v;
      _memSet = true;
    });
  }

  /// mr / Rand: values that replace the entry being typed, or are
  /// multiplied in after a value ("2 MR" → "2×mem").
  void _insertValue(double v) {
    setState(() {
      _fresh();
      final last = _expr.isEmpty ? null : _expr.last;
      if (last != null && last.type == _ST.num) {
        _expr.last = _STok(_ST.num, _cleanSci(v));
        return;
      }
      if (!_needOperand()) return;
      _expr.add(_STok(_ST.num, _cleanSci(v)));
    });
  }

  void _onMemoryRecall() => _insertValue(_mem);

  void _onRand() => _insertValue(_rand.nextDouble());

  void _onSecond() {
    setState(() => _second = !_second);
  }

  void _onAngle() {
    setState(() => _deg = !_deg);
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
          _onBinary(_ST.add);
          return KeyEventResult.handled;
        case '-':
          _onBinary(_ST.sub);
          return KeyEventResult.handled;
        case '*':
          _onBinary(_ST.mul);
          return KeyEventResult.handled;
        case '/':
          _onBinary(_ST.div);
          return KeyEventResult.handled;
        case '^':
          _onBinary(_ST.pow);
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

  // ---------- palette (matches the scientific reference) ----------
  bool get _dark => widget.dark;
  Color get _bg => _dark ? Colors.black : Colors.white;
  Color get _backdrop =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFD1D1D6);
  Color get _displayFg => _dark ? Colors.white : Colors.black;
  // Function and digit keys.
  Color get _keyBg => _dark ? const Color(0xFF333333) : Colors.white;
  Color get _keyFg => _dark ? Colors.white : Colors.black;
  // Utility keys (DEL, C, %): light grey with dark glyphs, both themes.
  static const Color _utilBg = Color(0xFFA5A5A5);
  static const Color _utilFg = Colors.black;
  // Operator column: app royal blue, like the standard pad.
  static const Color _sciOpBg = Color(0xFF1D4ED8);
  static const Color _sciOpFg = Colors.white;
  // Equals stays green, like the standard pad.
  static const Color _sciEqBg = Color(0xFF16A34A);
  static const Color _sciEqFg = Colors.white;

  // ---------- keys ----------
  Widget _sciKey({
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
    double fontSize = 16,
    FontWeight weight = FontWeight.w500,
    bool bordered = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: bordered && !_dark
          ? BorderSide(color: Colors.black.withValues(alpha: 0.12), width: 1)
          : BorderSide.none,
    );
    final splashBase =
        bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Expanded(
      child: _SciPressable(
        child: Material(
          color: bg,
          shape: shape,
          elevation: 0,
          child: InkWell(
            customBorder: shape,
            splashColor: splashBase.withValues(alpha: 0.22),
            highlightColor: splashBase.withValues(alpha: 0.12),
            onTap: () {
              if (widget.haptics) HapticFeedback.lightImpact();
              onTap();
            },
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
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
        ),
      ),
    );
  }

  Widget _row(List<Widget> cells) {
    final spaced = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      spaced.add(cells[i]);
      if (i != cells.length - 1) spaced.add(const SizedBox(width: 8));
    }
    return Expanded(child: Row(children: spaced));
  }

  Widget _grid() {
    // Function/digit key.
    Widget fn(String l, VoidCallback fn, {double fs = 16}) => _sciKey(
          label: l,
          bg: _keyBg,
          fg: _keyFg,
          fontSize: fs,
          bordered: true,
          onTap: fn,
        );
    // Utility key: DEL, C, %.
    Widget ut(String l, VoidCallback fn, {double fs = 20}) => _sciKey(
          label: l,
          bg: _utilBg,
          fg: _utilFg,
          fontSize: fs,
          weight: FontWeight.w600,
          onTap: fn,
        );
    // Operator column and equals.
    Widget op(String l, VoidCallback fn) => _sciKey(
          label: l,
          bg: _sciOpBg,
          fg: _sciOpFg,
          fontSize: 28,
          onTap: fn,
        );
    // Digit key.
    Widget dg(String l, VoidCallback fn, {double fs = 26}) => _sciKey(
          label: l,
          bg: _keyBg,
          fg: _keyFg,
          fontSize: fs,
          bordered: true,
          onTap: fn,
        );

    final trigLabels = _second
        ? const ['asin', 'acos', 'atan']
        : const ['sin', 'cos', 'tan'];
    final trigFns = _second ? _invTrigFns : _trigFns;
    final hypLabels = _second
        ? const ['asinh', 'acosh', 'atanh']
        : const ['sinh', 'cosh', 'tanh'];
    final hypFns = _second ? _invHypFns : _hypFns;

    const vGap = SizedBox(height: 8);
    return Column(
      children: [
        _row([
          fn('(', _onOpenParen, fs: 20),
          fn(')', _onCloseParen, fs: 20),
          fn('mc', _onMemoryClear),
          fn('m+', () => _onMemoryAdd(true)),
          fn('m-', () => _onMemoryAdd(false)),
          fn('mr', _onMemoryRecall),
        ]),
        vGap,
        _row([
          _sciKey(
            label: '2nd',
            bg: _second ? _utilBg : _keyBg,
            fg: _second ? _utilFg : _keyFg,
            fontSize: 16,
            weight: FontWeight.w700,
            bordered: !_second,
            onTap: _onSecond,
          ),
          fn('x²', () => _onPostfix(_SPost.sq), fs: 18),
          fn('x³', () => _onPostfix(_SPost.cube), fs: 18),
          fn('x^y', () => _onBinary(_ST.pow)),
          fn('e^x', () => _onFunc(_SFn.exp)),
          fn('10^x', () => _onFunc(_SFn.pow10)),
        ]),
        vGap,
        _row([
          fn('1/x', () => _onFunc(_SFn.recip)),
          fn('²√x', () => _onFunc(_SFn.sqrt)),
          fn('³√x', () => _onFunc(_SFn.cbrt)),
          fn('y√x', () => _onBinary(_ST.yroot)),
          fn('ln', () => _onFunc(_SFn.ln)),
          fn('log10', () => _onFunc(_SFn.log10)),
        ]),
        vGap,
        _row([
          fn('x!', () => _onPostfix(_SPost.fact), fs: 18),
          fn(trigLabels[0], () => _onFunc(trigFns[0])),
          fn(trigLabels[1], () => _onFunc(trigFns[1])),
          fn(trigLabels[2], () => _onFunc(trigFns[2])),
          fn('e', () => _onConst(_ST.euler)),
          fn('EE', _onEE),
        ]),
        vGap,
        _row([
          fn('Rand', _onRand),
          fn(hypLabels[0], () => _onFunc(hypFns[0])),
          fn(hypLabels[1], () => _onFunc(hypFns[1])),
          fn(hypLabels[2], () => _onFunc(hypFns[2])),
          fn('π', () => _onConst(_ST.pi), fs: 20),
          fn(_deg ? 'Deg' : 'Rad', _onAngle),
        ]),
        vGap,
        _row([
          ut('DEL', _onDelete, fs: 16),
          ut('C', _onClear),
          ut('%', () => _onPostfix(_SPost.pct)),
          op('÷', () => _onBinary(_ST.div)),
        ]),
        vGap,
        _row([
          dg('7', () => _onDigit('7')),
          dg('8', () => _onDigit('8')),
          dg('9', () => _onDigit('9')),
          op('×', () => _onBinary(_ST.mul)),
        ]),
        vGap,
        _row([
          dg('4', () => _onDigit('4')),
          dg('5', () => _onDigit('5')),
          dg('6', () => _onDigit('6')),
          op('−', () => _onBinary(_ST.sub)),
        ]),
        vGap,
        _row([
          dg('3', () => _onDigit('3')),
          dg('2', () => _onDigit('2')),
          dg('1', () => _onDigit('1')),
          op('+', () => _onBinary(_ST.add)),
        ]),
        vGap,
        _row([
          dg('+/-', _onNegate, fs: 20),
          dg('0', () => _onDigit('0')),
          dg('.', _onDecimal),
          _sciKey(
            label: '=',
            bg: _sciEqBg,
            fg: _sciEqFg,
            fontSize: 28,
            onTap: _onEquals,
          ),
        ]),
      ],
    );
  }

  // ---------- chrome ----------
  Widget _header() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Standard calculator',
            splashRadius: 22,
            icon: Icon(Icons.arrow_back, color: _displayFg, size: 26),
          ),
          Text(
            'Scientific',
            style: TextStyle(
              color: _displayFg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _display() {
    final len = _displayText.length;
    final fontSize = len <= 6
        ? 76.0
        : len <= 8
            ? 62.0
            : len <= 11
                ? 50.0
                : 40.0;
    return Container(
      width: double.infinity,
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.only(right: 18, bottom: 8, left: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                if (_memSet)
                  Text(
                    'M',
                    style: TextStyle(
                      color: _displayFg.withValues(alpha: 0.55),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_memSet) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _historyText,
                    key: const Key('sciHistory'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _displayFg.withValues(alpha: 0.45),
                      fontSize: 21,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomRight,
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
                key: const Key('sciDisplay'),
                maxLines: 1,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backdrop,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final framed = constraints.maxWidth > 560;
          const phoneWidth = 400.0;
          final width = framed ? phoneWidth : constraints.maxWidth;
          final height = framed
              ? (constraints.maxHeight - 48).clamp(600.0, 900.0)
              : constraints.maxHeight;

          Widget phone = SizedBox(
            width: width,
            height: height,
            child: Container(
              color: _bg,
              child: SafeArea(
                child: Column(
                  children: [
                    _header(),
                    Expanded(flex: 27, child: _display()),
                    Expanded(
                      flex: 73,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: _grid(),
                      ),
                    ),
                    _homeIndicator(),
                  ],
                ),
              ),
            ),
          );

          if (framed) {
            phone = Container(
              width: width,
              height: height,
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
