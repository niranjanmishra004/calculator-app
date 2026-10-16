import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'age.dart';
import 'scientific.dart';
import 'sip.dart';

// ---------------------------------------------------------------------------
// Other Calculator dashboard
// ---------------------------------------------------------------------------
//
// Opened from the hamburger icon. A tile grid matching the reference:
// SIP, Loan, GST, Investment, Currency, Saving, Age, BMI, Unit, Date,
// Discount, plus Scientific (keeps every feature reachable).
//
// Icons are genuine Bootstrap Icons SVGs (MIT, https://icons.getbootstrap.com),
// vendored under assets/icons/ and tinted orange like the reference.
// Age, Scientific and SIP open their real screens; the rest show a
// "coming soon" note until their calculators are built.

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.dark,
    required this.haptics,
  });

  final bool dark;
  final bool haptics;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // (label, bootstrap icon file name).
  static const List<(String, String)> _tiles = [
    ('SIP', 'graph-up-arrow'),
    ('Loan', 'bank'),
    ('GST', 'receipt'),
    ('Investment', 'coin'),
    ('Currency', 'currency-exchange'),
    ('Saving', 'piggy-bank'),
    ('Age', 'cake'),
    ('BMI', 'clipboard2-pulse'),
    ('Unit', 'rulers'),
    ('Date', 'calendar'),
    ('Discount', 'percent'),
    ('Scientific', 'calculator'),
  ];

  void _bip() {
    if (widget.haptics) HapticFeedback.lightImpact();
  }

  void _onTile(String label) {
    _bip();
    if (label == 'Age') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AgeScreen(dark: widget.dark, haptics: widget.haptics),
        ),
      );
      return;
    }
    if (label == 'Scientific') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScientificScreen(
            dark: widget.dark,
            haptics: widget.haptics,
          ),
        ),
      );
      return;
    }
    if (label == 'SIP') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SipScreen(
            dark: widget.dark,
            haptics: widget.haptics,
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label calculator coming soon')),
    );
  }

  // ---------- palette (app theme, reference styling) ----------
  bool get _dark => widget.dark;
  Color get _bg => _dark ? Colors.black : Colors.white;
  Color get _backdrop =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFD1D1D6);
  Color get _fg => _dark ? Colors.white : Colors.black;
  Color get _card => _dark ? const Color(0xFF1C1C21) : const Color(0xFFF4F4F6);
  // Tile icons: app royal blue (brighter variant on dark cards so they
  // stay luminous like the reference).
  Color get _tileIcon =>
      _dark ? const Color(0xFF5B9DFF) : const Color(0xFF1D4ED8);

  BorderSide get _cardSide => _dark
      ? BorderSide.none
      : BorderSide(color: Colors.black.withValues(alpha: 0.08));

  // ---------- tiles ----------
  Widget _tile(String label, String icon) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: _cardSide,
    );
    return Material(
      color: _card,
      shape: shape,
      elevation: 0,
      child: InkWell(
        customBorder: shape,
        onTap: () => _onTile(label),
        child: Padding(
          // Compact enough that icon + label always fit the cell, even
          // with large system text scaling.
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 40,
                height: 40,
                colorFilter: ColorFilter.mode(
                  _tileIcon,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
            'Other Calculator',
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
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          // Square-ish cells: all twelve tiles fit without
                          // scrolling on phone heights; shorter screens
                          // scroll instead of clipping.
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _tiles.length,
                        itemBuilder: (ctx, i) =>
                            _tile(_tiles[i].$1, _tiles[i].$2),
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
