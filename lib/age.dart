import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Age calculator section
// ---------------------------------------------------------------------------
//
// Opened from the hamburger menu ("Age calculator"). Two tabs: Age and
// Birthday. The date math below is pure and unit-tested; the screen reads
// the device theme (dark cards like the reference, light cards on light
// mode).

// ---------- pure date math ----------

/// Days in [month] of [year]. `DateTime(y, m + 1, 0)` is the last day of
/// month m, which also handles December rolling into January.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Strips the time of day so "today" comparisons are exact calendar days.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isLeapYear(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);

/// Exact calendar age between two dates, borrowing months and days the
/// way people count age (so 10 Jan 1997 → 11 Jan 2026 is 29y 0m 1d).
class AgeResult {
  const AgeResult({
    required this.years,
    required this.months,
    required this.days,
    required this.totalDays,
  });

  final int years;
  final int months;
  final int days;
  final int totalDays;

  int get totalMonths => years * 12 + months;
  int get totalWeeks => totalDays ~/ 7;
}

AgeResult calculateAge(DateTime birth, DateTime now) {
  final b = dateOnly(birth);
  final n = dateOnly(now);
  var years = n.year - b.year;
  var months = n.month - b.month;
  var days = n.day - b.day;
  if (days < 0) {
    months -= 1;
    days += DateTime(n.year, n.month, 0).day;
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  return AgeResult(
    years: years,
    months: months,
    days: days,
    totalDays: n.difference(b).inDays,
  );
}

/// The next occurrence of a birthday. Feb 29 birthdays fall on Feb 28 in
/// non-leap years.
class NextBirthday {
  const NextBirthday({
    required this.date,
    required this.turning,
    required this.daysLeft,
  });

  final DateTime date;
  final int turning;
  final int daysLeft;
}

NextBirthday nextBirthday(DateTime birth, DateTime now) {
  final b = dateOnly(birth);
  final n = dateOnly(now);
  DateTime cand(int y) {
    if (b.month == 2 && b.day == 29 && !isLeapYear(y)) {
      return DateTime(y, 2, 28);
    }
    return DateTime(y, b.month, b.day);
  }

  var c = cand(n.year);
  if (c.isBefore(n)) c = cand(n.year + 1);
  return NextBirthday(
    date: c,
    turning: c.year - b.year,
    daysLeft: c.difference(n).inDays,
  );
}

// ---------- formatting ----------

const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "10 Jan 1997".
String fmtDate(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// Thousand grouping with dots, like the reference ("10.593").
String groupThousands(int v) {
  final neg = v < 0;
  final digits = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return neg ? '-${buf.toString()}' : buf.toString();
}

// ---------- screen ----------

class AgeScreen extends StatefulWidget {
  const AgeScreen({super.key, required this.dark, required this.haptics});

  final bool dark;
  final bool haptics;

  @override
  State<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends State<AgeScreen> {
  int _tab = 0;
  late final bool _haptics = widget.haptics;

  DateTime? _dob;

  void _bip() {
    if (_haptics) HapticFeedback.lightImpact();
  }

  /// Sensible picker default: 25 years ago today (clamped off Feb 29).
  DateTime _defaultDob() {
    final n = dateOnly(DateTime.now());
    final dim = daysInMonth(n.year - 25, n.month);
    final day = n.day > dim ? dim : n.day;
    return DateTime(n.year - 25, n.month, day);
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPick) async {
    final now = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _defaultDob(),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      _bip();
      setState(() => onPick(dateOnly(picked)));
    }
  }

  Future<void> _copyAgeSummary(AgeResult age) async {
    final text =
        'I am ${age.years} years, ${age.months} months and ${age.days} days old '
        '— ${groupThousands(age.totalDays)} days alive!';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied age summary')));
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
  Color get _card => _dark ? const Color(0xFF141419) : const Color(0xFFF4F4F6);
  Color get _pill =>
      _dark ? const Color(0xFF23232B) : const Color(0xFFE9E9EE);
  Color get _accent => _dark ? const Color(0xFF6EA8FF) : const Color(0xFF1D4ED8);
  Color get _unselected =>
      _dark ? const Color(0xFF9A9AA0) : const Color(0xFF6E6E73);
  // Varied icon colours, like the reference: blue, purple, orange, red.
  static const Color _blue = Color(0xFF4C8DFF);
  static const Color _purple = Color(0xFFB15CFF);
  static const Color _orange = Color(0xFFFF9F0A);
  static const Color _cake = Color(0xFFFF5A6E);

  BorderRadius get _radius => BorderRadius.circular(20);

  BoxBorder? get _cardBorder => _dark
      ? null
      : Border.all(color: Colors.black.withValues(alpha: 0.08));

  // ---------- shared pieces ----------
  Widget _iconChip(IconData icon, Color color, {double size = 22}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }

  Widget _header({required VoidCallback? onCopy}) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
            splashRadius: 22,
            icon: Icon(Icons.arrow_back, color: _fg, size: 26),
          ),
          const Spacer(),
          if (onCopy != null)
            IconButton(
              onPressed: () {
                _bip();
                onCopy();
              },
              tooltip: 'Copy summary',
              splashRadius: 22,
              icon: Icon(Icons.ios_share, color: _fg, size: 24),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: _fg,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Tappable date row ("Date of Birth" + date pill), like the reference.
  Widget _dateRow({
    required String label,
    required IconData icon,
    required Color iconColor,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: _card,
        borderRadius: _radius,
        child: InkWell(
          borderRadius: _radius,
          onTap: () {
            _bip();
            onTap();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: _radius,
              border: _cardBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _iconChip(icon, iconColor),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _pill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value == null ? 'Select date' : fmtDate(value),
                        style: TextStyle(
                          color: value == null ? _sub : _accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: value == null ? _sub : _accent,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: _fg,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _tabBar() {
    const items = [
      (Icons.person, 'Age'),
      (Icons.card_giftcard, 'Birthday'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(24),
          border: _cardBorder,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Material(
          // Ink canvas so tab ripples stay visible above the bar colour.
          color: Colors.transparent,
          child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    _bip();
                    setState(() => _tab = i);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _tab == i
                          ? (_dark
                                ? const Color(0xFF2C2C36)
                                : const Color(0xFFE1E1E8))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[i].$1,
                          color: _tab == i ? _accent : _unselected,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$2,
                          maxLines: 1,
                          style: TextStyle(
                            color: _tab == i ? _accent : _unselected,
                            fontSize: 11,
                            fontWeight: _tab == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
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

  // ---------- Age tab ----------
  Widget _ageTab() {
    final now = dateOnly(DateTime.now());
    final age = _dob == null ? null : calculateAge(_dob!, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Your Age'),
        _dateRow(
          label: 'Date of Birth',
          icon: Icons.cake,
          iconColor: _cake,
          value: _dob,
          onTap: () => _pickDate(_dob, (d) => _dob = d),
        ),
        // Big result card.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: _radius,
              border: _cardBorder,
            ),
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    age == null ? '–' : '${age.years}',
                    key: const Key('ageBig'),
                    style: TextStyle(
                      color: _fg,
                      fontSize: 84,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  age == null ? '' : 'Years Old',
                  style: TextStyle(
                    color: _fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  age == null
                      ? 'Pick your birthdate above'
                      : '${age.years} years, ${age.months} months, ${age.days} days',
                  key: const Key('ageSub'),
                  style: TextStyle(color: _sub, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        _sectionLabel('Breakdown'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              _breakdownCard(
                Icons.calendar_month,
                _blue,
                age?.years ?? 0,
                'Years',
                'bdYears',
                first: true,
              ),
              _breakdownCard(
                Icons.event_repeat,
                _purple,
                age?.months ?? 0,
                'Months',
                'bdMonths',
              ),
              _breakdownCard(
                Icons.wb_sunny,
                _orange,
                age?.days ?? 0,
                'Days',
                'bdDays',
              ),
            ],
          ),
        ),
        _sectionLabel('Total Time Alive'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: _radius,
              border: _cardBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _totalRow(
                  Icons.calendar_month,
                  _blue,
                  'Total Months',
                  groupThousands(age?.totalMonths ?? 0),
                  'totMonths',
                ),
                _totalRow(
                  Icons.date_range,
                  _purple,
                  'Total Weeks',
                  groupThousands(age?.totalWeeks ?? 0),
                  'totWeeks',
                ),
                _totalRow(
                  Icons.wb_sunny,
                  _orange,
                  'Total Days',
                  groupThousands(age?.totalDays ?? 0),
                  'totDays',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _breakdownCard(
    IconData icon,
    Color color,
    int value,
    String label,
    String keyName, {
    bool first = false,
  }) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: first ? 0 : 8),
        child: Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: _radius,
            border: _cardBorder,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              _iconChip(icon, color),
              const SizedBox(height: 8),
              Text(
                '$value',
                key: Key(keyName),
                style: TextStyle(
                  color: _fg,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: _sub, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalRow(
      IconData icon, Color color, String label, String value, String keyName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _iconChip(icon, color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: _fg,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            key: Key(keyName),
            style: TextStyle(
              color: _fg,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Birthday tab ----------
  Widget _birthdayTab() {
    final now = dateOnly(DateTime.now());
    final next = _dob == null ? null : nextBirthday(_dob!, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Birthday'),
        _dateRow(
          label: 'Date of Birth',
          icon: Icons.cake,
          iconColor: _cake,
          value: _dob,
          onTap: () => _pickDate(_dob, (d) => _dob = d),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: _radius,
              border: _cardBorder,
            ),
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    next == null ? '–' : '${next.daysLeft}',
                    key: const Key('bdayBig'),
                    style: TextStyle(
                      color: _fg,
                      fontSize: 84,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  next == null
                      ? ''
                      : (next.daysLeft == 0
                            ? 'Happy Birthday!'
                            : 'days to go'),
                  key: const Key('bdayMsg'),
                  style: TextStyle(
                    color: _fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  next == null
                      ? 'Pick your birthdate above'
                      : 'Turning ${next.turning} on ${weekdayName(next.date)}, ${fmtDate(next.date)}',
                  key: const Key('bdaySub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _sub, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        _sectionLabel('Details'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: _radius,
              border: _cardBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _totalRow(
                  Icons.celebration,
                  _blue,
                  'Next birthday',
                  next == null ? '–' : fmtDate(next.date),
                  'bdayDate',
                ),
                _totalRow(
                  Icons.calendar_month,
                  _purple,
                  'Falls on',
                  next == null ? '–' : weekdayName(next.date),
                  'bdayWeekday',
                ),
                _totalRow(
                  Icons.star,
                  _orange,
                  'Turning',
                  next == null ? '–' : '${next.turning}',
                  'bdayTurning',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now());
    final age = _dob == null ? null : calculateAge(_dob!, now);

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
                    _header(
                      onCopy: _tab == 0 && age != null
                          ? () => _copyAgeSummary(age)
                          : null,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: switch (_tab) {
                          0 => _ageTab(),
                          _ => _birthdayTab(),
                        },
                      ),
                    ),
                    _tabBar(),
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
