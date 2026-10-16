import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sip.dart' show inr;

// ---------------------------------------------------------------------------
// EMI calculator
// ---------------------------------------------------------------------------
//
// Loan EMI with explicit Calculate flow: three chevron rows (loan amount,
// interest rate, tenure) open normal editor sheets with the system
// keyboard — no custom keypad. Tapping "Calculate EMI" snapshots the
// inputs and renders the monthly EMI, total interest and total payment,
// plus a year-wise payment schedule. App royal-blue theme throughout.

/// EMI outcome for a snapshotted set of inputs.
class EmiResult {
  const EmiResult({
    required this.emi,
    required this.total,
    required this.interest,
    required this.months,
  });

  final double emi;
  final double total;
  final double interest;
  final int months;
}

/// Standard reducing-balance EMI, rounded to whole rupees like reference
/// calculators: total = rounded EMI × months, interest = total − principal.
EmiResult emiCalc(double principal, double annualPct, int months) {
  if (months <= 0 || principal <= 0) {
    return const EmiResult(emi: 0, total: 0, interest: 0, months: 0);
  }
  final r = annualPct / 1200;
  double emi;
  if (r == 0) {
    emi = principal / months;
  } else {
    // Iterative (1+r)^n; avoids pow's int/double edge cases.
    final f = (1 + r);
    var p = 1.0;
    for (var i = 0; i < months; i++) {
      p *= f;
    }
    emi = principal * r * p / (p - 1);
  }
  if (emi.isNaN || emi.isInfinite) {
    return EmiResult(emi: 0, total: 0, interest: 0, months: months);
  }
  final rounded = emi.roundToDouble();
  final total = rounded * months;
  return EmiResult(
    emi: rounded,
    total: total,
    interest: total - principal,
    months: months,
  );
}

/// One year of the amortisation schedule.
class EmiYear {
  const EmiYear({
    required this.year,
    required this.principal,
    required this.interest,
    required this.balance,
  });

  final int year;
  final double principal;
  final double interest;
  final double balance;
}

/// Year-wise principal/interest split of the loan above.
List<EmiYear> emiSchedule(
  double principal,
  double annualPct,
  int months,
  double emi,
) {
  final rows = <EmiYear>[];
  if (months <= 0 || principal <= 0 || emi <= 0) return rows;
  final r = annualPct / 1200;
  var balance = principal;
  var yearP = 0.0;
  var yearI = 0.0;
  for (var m = 1; m <= months; m++) {
    final interest = balance * r;
    var princ = emi - interest;
    if (princ > balance) princ = balance;
    if (princ < 0) princ = 0;
    balance -= princ;
    yearP += princ;
    yearI += interest;
    if (m % 12 == 0 || m == months) {
      rows.add(EmiYear(
        year: rows.length + 1,
        principal: yearP,
        interest: yearI,
        balance: balance < 0.01 ? 0 : balance,
      ));
      yearP = 0;
      yearI = 0;
    }
  }
  return rows;
}

class EmiScreen extends StatefulWidget {
  const EmiScreen({super.key, required this.dark, required this.haptics});

  final bool dark;
  final bool haptics;

  @override
  State<EmiScreen> createState() => _EmiScreenState();
}

class _EmiScreenState extends State<EmiScreen> {
  // Inputs start empty with example placeholders; results stay in the
  // prompt state until the first calculation.
  String _principal = '';
  String _rate = '';
  int _years = 0;
  int _months = 0;

  // Last calculated snapshot; results render from this, not the inputs.
  double _cP = 0;
  double _cR = 0;
  int _cN = 0;
  bool _calculated = false;

  final ScrollController _scroll = ScrollController();
  // Persistent editors: creating/disposing a controller per sheet races
  // the sheet's exit transition (focus teardown rebuilds the field after
  // pop), so the controllers live as long as the screen instead.
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _rateCtrl = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _bip() {
    if (widget.haptics) HapticFeedback.lightImpact();
  }

  static double _num(String raw) =>
      double.tryParse(raw.replaceAll(RegExp(r'[, ]'), '')) ?? -1;

  String _tenureText() {
    if (_years == 0 && _months == 0) return 'Select tenure';
    if (_months == 0) return _years == 1 ? '1 year' : '$_years years';
    if (_years == 0) return _months == 1 ? '1 month' : '$_months months';
    return '$_years years $_months months';
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openAmount() async {
    _bip();
    _amountCtrl.text = _principal;
    var error = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Scrollable so the open keyboard can never push content off.
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: _sheetHandle()),
                      const SizedBox(height: 12),
                      Text(
                        'Loan amount',
                      style: TextStyle(
                        color: _fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: _fg, fontSize: 22),
                      decoration: InputDecoration(
                        hintText: 'e.g. 500000',
                        prefixText: '₹ ',
                        errorText: error.isEmpty ? null : error,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _fg.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF1D4ED8),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          final v = _num(_amountCtrl.text);
                          // Zero is savable so Calculate can explain it is
                          // not a loan; only garbage is rejected here.
                          if (v >= 0) {
                            setState(() {
                              _principal = _amountCtrl.text
                                  .replaceAll(RegExp(r'[, ]'), '');
                              _calculated = false;
                            });
                            Navigator.pop(ctx);
                          } else {
                            setSheetState(() {
                              error = 'Enter a valid amount';
                            });
                          }
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }

  Future<void> _openRate() async {
    _bip();
    _rateCtrl.text = _rate;
    var error = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Scrollable so the open keyboard can never push content off.
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: _sheetHandle()),
                      const SizedBox(height: 12),
                      Text(
                        'Interest rate',
                      style: TextStyle(
                        color: _fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _rateCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(color: _fg, fontSize: 22),
                      decoration: InputDecoration(
                        hintText: 'e.g. 10.5',
                        suffixText: '%',
                        errorText: error.isEmpty ? null : error,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _fg.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF1D4ED8),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          final v = _num(_rateCtrl.text);
                          if (v >= 0) {
                            setState(() {
                              _rate = _rateCtrl.text
                                  .replaceAll(RegExp(r'[, ]'), '');
                              _calculated = false;
                            });
                            Navigator.pop(ctx);
                          } else {
                            setSheetState(() {
                              error = 'Enter a valid rate';
                            });
                          }
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }

  Future<void> _openTenure() async {
    _bip();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void bump(bool years, int d) {
              _bip();
              setState(() {
                if (years) {
                  _years = (_years + d).clamp(0, 30);
                } else {
                  _months = (_months + d).clamp(0, 11);
                }
                _calculated = false;
              });
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _sheetHandle()),
                    const SizedBox(height: 12),
                    Text(
                      'Loan tenure',
                      style: TextStyle(
                        color: _fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final y in [1, 3, 5, 10, 15, 20])
                          _chip('${y}Y', _years == y && _months == 0, () {
                            _bip();
                            setState(() {
                              _years = y;
                              _months = 0;
                              _calculated = false;
                            });
                            Navigator.pop(ctx);
                          }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _stepper('Years', '$_years', () => bump(true, -1),
                        () => bump(true, 1)),
                    _stepper('Months', '$_months', () => bump(false, -1),
                        () => bump(false, 1)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _calculate() {
    _bip();
    final p = _num(_principal);
    final r = _num(_rate);
    final n = _years * 12 + _months;
    if (p <= 0 || r < 0 || n <= 0) {
      _snack('Enter loan details to calculate');
      return;
    }
    setState(() {
      _cP = p;
      _cR = r;
      _cN = n;
      _calculated = true;
    });
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openSchedule(EmiResult res) async {
    _bip();
    if (!_calculated) {
      _snack('Tap Calculate EMI first');
      return;
    }
    final rows = emiSchedule(_cP, _cR, _cN, res.emi);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Payment Schedule',
                    style: TextStyle(
                      color: _fg,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _schedHead(),
                        for (final row in rows) _schedRow(row),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- palette (app theme) ----------
  bool get _dark => widget.dark;
  Color get _bg => _dark ? Colors.black : Colors.white;
  Color get _backdrop =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFD1D1D6);
  Color get _fg => _dark ? Colors.white : Colors.black;
  Color get _sub => _dark
      ? Colors.white.withValues(alpha: 0.55)
      : Colors.black.withValues(alpha: 0.55);
  Color get _card => _dark ? const Color(0xFF1C1C21) : const Color(0xFFF4F4F6);
  Color get _sheetBg => _dark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _accent => _dark ? const Color(0xFF5B9DFF) : const Color(0xFF1D4ED8);

  BorderSide get _cardSide => _dark
      ? BorderSide.none
      : BorderSide(color: Colors.black.withValues(alpha: 0.08));

  ShapeBorder _cardShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: _cardSide,
      );

  Widget _sheetHandle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: _fg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _iconChip(IconData icon) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _accent, size: 28),
    );
  }

  // ---------- input rows ----------
  Widget _row({
    required IconData icon,
    required String label,
    required String display,
    required String keyName,
    required VoidCallback onTap,
    bool placeholder = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: _card,
        shape: _cardShape(),
        elevation: 0,
        child: InkWell(
          customBorder: _cardShape(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                _iconChip(icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _sub,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        display,
                        key: Key(keyName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: placeholder
                              ? _sub.withValues(alpha: 0.7)
                              : _fg,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: _accent, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent : _card,
          borderRadius: BorderRadius.circular(12),
          border: selected ? null : Border.all(color: _cardSide.color),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _fg,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _stepper(
      String label, String value, VoidCallback dec, VoidCallback inc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: _fg,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: dec,
            tooltip: 'Decrease $label',
            icon: Icon(Icons.remove_circle_outline, color: _fg),
          ),
          SizedBox(
            width: 56,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: inc,
            tooltip: 'Increase $label',
            icon: Icon(Icons.add_circle_outline, color: _accent),
          ),
        ],
      ),
    );
  }

  // ---------- results ----------
  Widget _results(EmiResult r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: _dark
              ? null
              : Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: _calculated
            ? Column(
                children: [
                  Text(
                    'Monthly EMI',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      inr(r.emi),
                      key: const Key('emiTotal'),
                      style: TextStyle(
                        color: _fg,
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: _fg.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 14),
                  _resultRow('Total interest', inr(r.interest), 'emiInterest'),
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: _fg.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 14),
                  _resultRow('Total payment', inr(r.total), 'emiPayment'),
                ],
              )
            : Column(
                children: [
                  Text(
                    '–',
                    key: const Key('emiTotal'),
                    style: TextStyle(
                      color: _fg,
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Edit the details above and tap Calculate EMI',
                    key: const Key('emiInterest'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _sub, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '',
                    key: const Key('emiPayment'),
                    style: const TextStyle(fontSize: 1),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _resultRow(String label, String value, String keyName) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: _sub,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            key: Key(keyName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _fg,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _schedHead() {
    final s = TextStyle(
      color: _sub,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text('Year', style: s)),
          Expanded(
            flex: 2,
            child: Text('Principal', style: s, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('Interest', style: s, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('Balance', style: s, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _schedRow(EmiYear row) {
    final v = TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text('Year ${row.year}', style: v)),
          Expanded(
            flex: 2,
            child: Text(
              inr(row.principal),
              style: v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              inr(row.interest),
              style: v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              inr(row.balance),
              style: v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- chrome ----------
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _fg.withValues(alpha: 0.2)),
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.arrow_back, color: _fg, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'EMI Calculator',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _fg,
                fontSize: 22,
                fontWeight: FontWeight.w700,
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
    final res = emiCalc(_cP, _cR, _cN);
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
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Column(
                          children: [
                            _row(
                              icon: Icons.home_outlined,
                              label: 'Loan amount',
                              display: _principal.isEmpty
                                  ? '₹5,00,000'
                                  : inr(_num(_principal)),
                              keyName: 'emiAmount',
                              onTap: _openAmount,
                              placeholder: _principal.isEmpty,
                            ),
                            _row(
                              icon: Icons.percent,
                              label: 'Interest rate',
                              display:
                                  _rate.isEmpty ? '10.5%' : '$_rate%',
                              keyName: 'emiRate',
                              onTap: _openRate,
                              placeholder: _rate.isEmpty,
                            ),
                            _row(
                              icon: Icons.calendar_month,
                              label: 'Loan tenure',
                              display: _tenureText(),
                              keyName: 'emiTenure',
                              onTap: _openTenure,
                              placeholder:
                                  _years == 0 && _months == 0,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: Material(
                                  color: Colors.transparent,
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF1D4ED8),
                                          Color(0xFF3B82F6)
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: _calculate,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 17),
                                        child: Center(
                                          child: Text(
                                            'Calculate EMI',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 19,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _results(res),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(0, 6, 0, 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _openSchedule(res),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'View payment schedule',
                                        style: TextStyle(
                                          color: _accent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: _accent,
                                        size: 24,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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

          return Container(
            color: framed ? _backdrop : _bg,
            alignment: Alignment.center,
            child: phone,
          );
        },
      ),
    );
  }
}
