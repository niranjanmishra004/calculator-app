import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// SIP calculator
// ---------------------------------------------------------------------------
//
// Monthly SIP growth with live results. Beyond the reference layout it adds:
// a yearly step-up field (contributions grow every year), a duration sheet
// with quick chips plus year/month steppers, an invested-vs-gains bar, and
// results that recompute on every keypress instead of needing "=".
// App royal-blue theme throughout.

/// SIP outcome: what was put in, what it became, and the difference.
class SipResult {
  const SipResult({
    required this.invested,
    required this.total,
    required this.gains,
  });

  final double invested;
  final double total;
  final double gains;
}

/// Future value of a monthly SIP. Contributions compound monthly
/// (annuity-due, like standard SIP calculators); an optional yearly
/// step-up bumps each year's contribution by [stepUpPct]. A zero rate
/// simply returns the invested amount.
SipResult sipCalc(
  double monthly,
  double annualPct,
  int months, [
  double stepUpPct = 0,
]) {
  if (months <= 0 || monthly <= 0) {
    return const SipResult(invested: 0, total: 0, gains: 0);
  }
  final r = annualPct / 1200;
  final s = stepUpPct / 100;
  var balance = 0.0;
  var invested = 0.0;
  for (var m = 1; m <= months; m++) {
    final yearsDone = (m - 1) ~/ 12;
    final contrib = monthly * math.pow(1 + s, yearsDone);
    invested += contrib;
    balance = (balance + contrib) * (1 + r);
  }
  if (balance.isNaN || balance.isInfinite) {
    return SipResult(invested: invested, total: 0, gains: 0);
  }
  return SipResult(invested: invested, total: balance, gains: balance - invested);
}

/// Indian digit grouping for a plain digit string ("100000" → "1,00,000").
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.add(head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  parts.add(head);
  return '${parts.reversed.join(',')},$last3';
}

/// Indian Rupee formatting with Indian digit grouping ("₹1,00,000").
String inr(double v) {
  final n = v.round();
  final grouped = groupIndian(n.abs().toString());
  return '${n < 0 ? '-' : ''}₹$grouped';
}

/// Formats a typed entry with Indian grouping, preserving a trailing
/// decimal part ("10000" → "₹10,000", "12.5" → "₹12.5").
String entryInr(String raw) {
  if (raw.isEmpty) return '';
  final dot = raw.indexOf('.');
  final head = dot < 0 ? raw : raw.substring(0, dot);
  final tail = dot < 0 ? '' : raw.substring(dot);
  final grouped = head.isEmpty ? '0' : groupIndian(head);
  return '₹$grouped$tail';
}

class SipScreen extends StatefulWidget {
  const SipScreen({super.key, required this.dark, required this.haptics});

  final bool dark;
  final bool haptics;

  @override
  State<SipScreen> createState() => _SipScreenState();
}

class _SipScreenState extends State<SipScreen> {
  // Fields start empty with example placeholders; results stay zero
  // until the user types and picks a period.
  String _amount = '';
  String _rate = '';
  String _stepUp = '';
  int _years = 0;
  int _months = 0;
  // Persistent editors: creating/disposing a controller per sheet races
  // the sheet's exit transition, so they live as long as the screen.
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _rateCtrl = TextEditingController();
  final TextEditingController _stepCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _stepCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bip() {
    if (widget.haptics) HapticFeedback.lightImpact();
  }

  double get _p => double.tryParse(_amount) ?? 0;
  double get _r => double.tryParse(_rate) ?? 0;
  double get _s => double.tryParse(_stepUp) ?? 0;
  int get _n => _years * 12 + _months;
  SipResult get _res => sipCalc(_p, _r, _n, _s);

  String _periodText() {
    if (_n == 0) return 'Select Duration';
    final ys = _years == 1 ? '1 Yr' : '$_years Yrs';
    if (_months == 0) return ys;
    final ms = _months == 1 ? '1 Mo' : '$_months Mos';
    return _years == 0 ? ms : '$ys $ms';
  }

  /// Editor sheet with the normal system keyboard. Empty is a valid save
  /// (shows the example placeholder); only garbage is rejected.
  Future<void> _openEditor({
    required String title,
    required String hint,
    required bool decimal,
    required TextEditingController controller,
    required String current,
    required ValueChanged<String> onSave,
  }) async {
    _bip();
    controller.text = current;
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
                        title,
                        style: TextStyle(
                          color: _fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: decimal
                            ? const TextInputType.numberWithOptions(
                                decimal: true)
                            : TextInputType.number,
                        style: TextStyle(color: _fg, fontSize: 22),
                        decoration: InputDecoration(
                          hintText: hint,
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
                            final raw = controller.text
                                .replaceAll(RegExp(r'[, ]'), '');
                            final v = double.tryParse(
                                raw.isEmpty ? '0' : raw);
                            if (v == null || v < 0) {
                              setSheetState(() {
                                error = 'Enter a valid number';
                              });
                              return;
                            }
                            onSave(raw);
                            Navigator.pop(ctx);
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

  Future<void> _openAmount() => _openEditor(
        title: 'Monthly SIP Amount',
        hint: 'e.g. 10000',
        decimal: false,
        controller: _amountCtrl,
        current: _amount,
        onSave: (v) => setState(() => _amount = v),
      );

  Future<void> _openRate() => _openEditor(
        title: 'Rate (%)',
        hint: 'e.g. 12',
        decimal: true,
        controller: _rateCtrl,
        current: _rate,
        onSave: (v) => setState(() => _rate = v),
      );

  Future<void> _openStepUp() => _openEditor(
        title: 'Yearly Step-up (%)',
        hint: 'e.g. 10',
        decimal: true,
        controller: _stepCtrl,
        current: _stepUp,
        onSave: (v) => setState(() => _stepUp = v),
      );

  Future<void> _openDuration() async {
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
                  _years = (_years + d).clamp(0, 50);
                } else {
                  _months = (_months + d).clamp(0, 11);
                }
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
                      'Investment Period',
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
                        for (final y in [1, 3, 5, 10, 15])
                          _chip('${y}Y', _years == y && _months == 0, () {
                            _bip();
                            setState(() {
                              _years = y;
                              _months = 0;
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
                          backgroundColor: _accent,
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
  static const Color _gain = Color(0xFF16A34A);

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

  Widget _iconChip(Widget icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Center(child: icon),
    );
  }

  Widget _chipIcon(IconData icon) =>
      Icon(icon, color: _accent, size: 26);

  Widget _chipText(String glyph) => Text(
        glyph,
        style: TextStyle(
          color: _accent,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      );

  /// Input card with an icon chip, label and value. Tapping opens an
  /// editor sheet with the normal keyboard and scrolls the card into
  /// view, so editing always works even on short screens.
  Widget _field({
    required Widget icon,
    required String label,
    required String display,
    required String hint,
    required VoidCallback onTap,
    required String keyName,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  }) {
    return Padding(
      padding: padding,
      child: Builder(
        builder: (ctx) => Material(
          color: _card,
          shape: _cardShape(),
          elevation: 0,
          child: InkWell(
            customBorder: _cardShape(),
            onTap: () {
              _bip();
              onTap();
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  _iconChip(icon),
                  const SizedBox(width: 12),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          display.isEmpty ? hint : display,
                          key: Key(keyName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: display.isEmpty
                                ? _sub.withValues(alpha: 0.7)
                                : _fg,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
  Widget _results(SipResult r) {
    final invShare = r.total <= 0 ? 0 : (r.invested / r.total * 100).round();
    final gainShare = r.total <= 0 ? 0 : 100 - invShare;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: _dark ? null : Border.all(
              color: Colors.black.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Projected Value',
              style: TextStyle(
                color: _accent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                inr(r.total),
                key: const Key('sipTotal'),
                style: TextStyle(
                  color: _accent,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: r.total <= 0
                    ? Container(color: _sub.withValues(alpha: 0.25))
                    : Row(
                        children: [
                          if (invShare > 0)
                            Expanded(
                              flex: invShare,
                              child: Container(color: _accent),
                            ),
                          if (gainShare > 0)
                            Expanded(
                              flex: gainShare,
                              child: Container(color: _gain),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _resultRow(
              'Invested',
              '${inr(r.invested)} · ${r.total <= 0 ? 0 : invShare}%',
              'sipInvested',
              _accent,
            ),
            Divider(
              height: 20,
              thickness: 1,
              color: _fg.withValues(alpha: 0.1),
            ),
            _resultRow(
              'Est. gains',
              '${inr(r.gains)} · ${r.total <= 0 ? 0 : gainShare}%',
              'sipGains',
              _gain,
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, String keyName, Color dot) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: _fg,
            fontSize: 15,
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
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- chrome ----------
  Widget _header() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
            splashRadius: 22,
            icon: Icon(Icons.arrow_back, color: _fg, size: 28),
          ),
          const SizedBox(width: 4),
          Text(
            'SIP Calculator',
            style: TextStyle(
              color: _fg,
              fontSize: 20,
              fontWeight: FontWeight.w600,
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
    final r = _res;
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
                      // Centers short content in the viewport; taller
                      // content scrolls normally instead.
                      child: LayoutBuilder(
                        builder: (ctx, viewport) => SingleChildScrollView(
                          controller: _scroll,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: viewport.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    icon: _chipIcon(Icons.currency_rupee),
                                    label: 'SIP Amount',
                                    display: entryInr(_amount),
                                    hint: '₹10,000',
                                    onTap: _openAmount,
                                    keyName: 'sipAmount',
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 6, 12),
                                  ),
                                ),
                                Expanded(
                                  child: _field(
                                    icon: _chipText('%'),
                                    label: 'Rate (%)',
                                    display: _rate,
                                    hint: '12',
                                    onTap: _openRate,
                                    keyName: 'sipRate',
                                    padding: const EdgeInsets.fromLTRB(
                                        6, 0, 16, 12),
                                  ),
                                ),
                              ],
                            ),
                            _field(
                              icon: _chipIcon(Icons.trending_up),
                              label: 'Yearly Step-up (%) · optional',
                              display: _stepUp,
                              hint: 'Enter step-up',
                              onTap: _openStepUp,
                              keyName: 'sipStepUp',
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Builder(
                                builder: (ctx) => Material(
                                  color: _card,
                                  shape: _cardShape(),
                                  elevation: 0,
                                  child: InkWell(
                                    customBorder: _cardShape(),
                                    onTap: _openDuration,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          _iconChip(_chipIcon(
                                              Icons.calendar_month)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Investment Period',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: _sub,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _periodText(),
                                                  key: const Key('sipPeriod'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: _fg,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.keyboard_arrow_down,
                                            color: _accent,
                                            size: 28,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _results(r),
                          ],
                        ),
                      ),
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
