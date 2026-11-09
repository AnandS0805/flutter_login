// lib/attendance/month_history.dart
import 'package:flutter/material.dart';
import 'attendance_record.dart';
import 'attendance_theme.dart';

/// Month select -> month ka table + totals -> date select -> us din ki detail.
class MonthHistory extends StatefulWidget {
  final Map<String, AttendanceRecord> records;
  const MonthHistory({super.key, required this.records});

  @override
  State<MonthHistory> createState() => _MonthHistoryState();
}

class _MonthHistoryState extends State<MonthHistory> {
  late DateTime _month;
  String? _pickedKey;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  String get _prefix => '${_month.year}-${two(_month.month)}-';
  String get _label => '${kMonths[_month.month - 1]} ${_month.year}';

  void _setMonth(DateTime m) => setState(() {
        _month = DateTime(m.year, m.month);
        _pickedKey = null;
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(_month.year, _month.month, 1);
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    final last = monthEnd.isAfter(now) ? now : monthEnd;
    final initial = (_isCurrentMonth || last.isBefore(now)) ? last : first;

    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kGreen,
            onPrimary: Colors.black,
            surface: kBg,
            onSurface: kGreen,
          ),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _pickedKey = dateKey(d));
  }

  @override
  Widget build(BuildContext context) {
    final recs = widget.records.values.where((r) => r.date.startsWith(_prefix)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final done = recs.where((r) => r.isComplete).toList();

    final totalWorked = done.fold<Duration>(Duration.zero, (a, r) => a + r.worked);
    final otPlus = done.fold<Duration>(Duration.zero, (a, r) => r.overtime > Duration.zero ? a + r.overtime : a);
    final short = done.fold<Duration>(Duration.zero, (a, r) => r.overtime < Duration.zero ? a - r.overtime : a);
    final net = otPlus - short;
    final avg = done.isEmpty ? Duration.zero : Duration(minutes: totalWorked.inMinutes ~/ done.length);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('> ATTENDANCE_LOG', style: mono(14, bold: true)),
      const SizedBox(height: 10),
      _monthSelector(),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          _stat('TOTAL HOURS', fmtDuration(totalWorked), kGreen),
          _stat('DAYS WORKED', '${done.length}', kGreen),
          _stat('OT EARNED (+)', fmtDuration(otPlus), kAmber),
          _stat('SHORT (-)', fmtDuration(short), kRed),
          _stat('NET OT', fmtSigned(net), net.isNegative ? kRed : kAmber),
          _stat('AVG / DAY', fmtDuration(avg), kGreen),
        ],
      ),
      const SizedBox(height: 14),
      _dateSearch(),
      if (_pickedKey != null) ...[const SizedBox(height: 10), _dayResult()],
      const SizedBox(height: 14),
      _table(recs, totalWorked, net),
    ]);
  }

  Widget _monthSelector() {
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - i));
    return Container(
      decoration: neonBox(),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: kGreen),
          onPressed: () => _setMonth(DateTime(_month.year, _month.month - 1)),
        ),
        Expanded(
          child: PopupMenuButton<DateTime>(
            color: kBg,
            onSelected: _setMonth,
            itemBuilder: (_) => months
                .map((m) => PopupMenuItem(
                      value: m,
                      child: Text('${kMonths[m.month - 1]} ${m.year}', style: mono(13)),
                    ))
                .toList(),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_label, style: mono(14, bold: true)),
              const Icon(Icons.arrow_drop_down, color: kGreen),
            ]),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, color: _isCurrentMonth ? kDim : kGreen),
          onPressed: _isCurrentMonth ? null : () => _setMonth(DateTime(_month.year, _month.month + 1)),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: neonBox(color: color),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: mono(10, color: color.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(value, style: mono(16, color: color, bold: true)),
        ]),
      );

  Widget _dateSearch() => Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.search, size: 20),
            label: Text(_pickedKey == null ? 'SEARCH A DATE IN THIS MONTH' : 'DATE: ${fmtDate(_pickedKey!)}',
                style: mono(12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: kGreen,
              side: const BorderSide(color: kGreen),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_pickedKey != null)
          IconButton(
            icon: const Icon(Icons.close, color: kRed),
            onPressed: () => setState(() => _pickedKey = null),
          ),
      ]);

  Widget _dayResult() {
    final key = _pickedKey!;
    final r = widget.records[key];
    final title = '${fmtDate(key)} (${kDays[DateTime.parse(key).weekday - 1]})';

    late final Color color;
    late final String headline;
    final lines = <Widget>[];

    if (r == null || r.punchIn == null) {
      color = kRed;
      headline = 'NO PUNCH RECORD';
      lines.add(Text('Is din na punch in hua, na punch out.', style: mono(12, color: kRed)));
    } else if (!r.isComplete) {
      color = kAmber;
      headline = 'PUNCH OUT MISSING';
      lines.add(Text('Punch IN: ${fmtTime(r.punchIn)}', style: mono(13)));
      lines.add(Text('Punch OUT nahi hua.', style: mono(12, color: kAmber)));
    } else {
      color = kGreen;
      headline = 'PUNCHED IN & OUT';
      final ot = r.overtime;
      lines.addAll([
        Text('IN   : ${fmtTime(r.punchIn)}', style: mono(13)),
        Text('OUT  : ${fmtTime(r.punchOut)}', style: mono(13)),
        Text('TOTAL: ${fmtDuration(r.worked)}', style: mono(13)),
        Text('OT   : ${fmtSigned(ot)}${ot.isNegative ? '  (kam kaam)' : ''}',
            style: mono(13, color: ot.isNegative ? kRed : kAmber, bold: true)),
      ]);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(key + headline),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: neonBox(color: color),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: mono(12, color: color.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(headline, style: mono(15, color: color, bold: true)),
          const SizedBox(height: 8),
          ...lines,
        ]),
      ),
    );
  }

  Widget _table(List<AttendanceRecord> recs, Duration totalWorked, Duration net) {
    if (recs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: neonBox(),
        child: Text('> NO DATA FOR THIS MONTH', textAlign: TextAlign.center, style: mono(13, color: kGreen.withOpacity(0.6))),
      );
    }

    Widget c(String t, TextStyle s) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Text(t, style: s));

    final head = mono(12, bold: true);
    final cell = mono(12, color: kGreen.withOpacity(0.85));

    Widget otCell(AttendanceRecord r) {
      if (!r.isComplete) {
        final running = r.date == dateKey(DateTime.now());
        return c(running ? 'RUNNING' : 'NO OUT', mono(12, color: running ? kGreen : kRed));
      }
      final ot = r.overtime;
      return c(fmtSigned(ot), mono(12, color: ot.isNegative ? kRed : (ot > Duration.zero ? kAmber : kGreen), bold: true));
    }

    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: kDim),
        children: [c('DATE', head), c('IN', head), c('OUT', head), c('TOTAL', head), c('OT', head)],
      ),
      for (final r in recs)
        TableRow(children: [
          c(fmtDateShort(r.date), cell),
          c(fmtTime(r.punchIn), cell),
          c(fmtTime(r.punchOut), cell),
          c(r.isComplete ? fmtDuration(r.worked) : '--', cell),
          otCell(r),
        ]),
      TableRow(
        decoration: BoxDecoration(color: kGreen.withOpacity(0.12)),
        children: [
          c('MONTH', head),
          c('', head),
          c('TOTAL', head),
          c(fmtDuration(totalWorked), head),
          c(fmtSigned(net), mono(12, color: net.isNegative ? kRed : kAmber, bold: true)),
        ],
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: kGreen.withOpacity(0.25)),
          children: rows,
        ),
      ),
    );
  }
}
