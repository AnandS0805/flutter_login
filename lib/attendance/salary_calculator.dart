// lib/attendance/salary_calculator.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'attendance_record.dart';
import 'attendance_theme.dart';

class _Deduction {
  final TextEditingController reason = TextEditingController();
  final TextEditingController amount = TextEditingController();
  void dispose() {
    reason.dispose();
    amount.dispose();
  }
}

/// Ek din ka minimum shortfall jiske baad wo din "short day" gina jaata hai.
const _shortThreshold = Duration(minutes: 30);

class SalaryCalculator extends StatefulWidget {
  final Map<String, AttendanceRecord> records;
  const SalaryCalculator({super.key, required this.records});

  @override
  State<SalaryCalculator> createState() => _SalaryCalculatorState();
}

class _SalaryCalculatorState extends State<SalaryCalculator> {
  bool _open = false;
  DateTime? _month;

  final _baseSalaryCtrl = TextEditingController();
  final List<_Deduction> _deductions = [];

  @override
  void initState() {
    super.initState();
    _baseSalaryCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _baseSalaryCtrl.dispose();
    for (final d in _deductions) {
      d.dispose();
    }
    super.dispose();
  }

  void _click() => SystemSound.play(SystemSoundType.click);
  // Tumhare paas agar pehle se _playSound() helper hai (login_success.mp3 wala),
  // to upar wali line hata ke yahan unawaited(_playSound('click.mp3')); laga sakte ho.

  void _start() {
    _click();
    setState(() => _open = true);
  }

  void _pickMonth(DateTime m) {
    _click();
    setState(() => _month = DateTime(m.year, m.month));
  }

  void _addDeduction() {
    _click();
    final d = _Deduction();
    d.reason.addListener(() => setState(() {}));
    d.amount.addListener(() => setState(() {}));
    setState(() => _deductions.add(d));
  }

  void _removeDeduction(_Deduction d) {
    _click();
    setState(() {
      _deductions.remove(d);
      d.dispose();
    });
  }

  double get _baseSalary => double.tryParse(_baseSalaryCtrl.text.trim()) ?? 0;

  /// Mahine ke saare records (date order mein) is month ke liye.
  List<AttendanceRecord> get _monthRecords {
    if (_month == null) return [];
    final prefix = '${_month!.year}-${two(_month!.month)}-';
    final list = widget.records.values.where((r) => r.date.startsWith(prefix) && r.isComplete).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Short days nikal ke half-day wale din decide karta hai.
  /// Pehli short day maaf, dusri se half day.
  List<AttendanceRecord> get _halfDayRecords {
    final list = <AttendanceRecord>[];
    int shortCount = 0;
    for (final r in _monthRecords) {
      final shortfall = AttendanceRecord.baseWork - r.worked;
      if (shortfall >= _shortThreshold) {
        shortCount++;
        if (shortCount >= 2) list.add(r);
      }
    }
    return list;
  }

  /// Sirf wo din jaha 8h30m se zyada kaam hua (half-day wale din yahan nahi aayenge,
  /// kyunki unka worked base se kam hi hota hai).
  double get _totalOtAmount {
    if (_baseSalary <= 0) return 0;
    final perMinute = (_baseSalary / 30) / 8.5 / 60;
    double total = 0;
    for (final r in _monthRecords) {
      if (r.worked > AttendanceRecord.baseWork) {
        total += r.overtime.inMinutes * perMinute;
      }
    }
    return total;
  }

  double get _halfDayDeduction {
    if (_baseSalary <= 0) return 0;
    final perDay = _baseSalary / 30;
    return _halfDayRecords.length * (perDay / 2);
  }

  double get _userDeductionTotal {
    double total = 0;
    for (final d in _deductions) {
      total += double.tryParse(d.amount.text.trim()) ?? 0;
    }
    return total;
  }

  double get _totalInHand =>
      _baseSalary + _totalOtAmount - _halfDayDeduction - _userDeductionTotal;

  String _rs(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.calculate_outlined),
          label: Text('CALCULATE SALARY', style: mono(13, bold: true)),
          style: OutlinedButton.styleFrom(
            foregroundColor: kGreen,
            side: const BorderSide(color: kGreen),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: neonBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('> SALARY CALCULATOR', style: mono(14, bold: true)),
        const SizedBox(height: 12),
        _monthPicker(),
        if (_month != null) ...[
          const SizedBox(height: 16),
          _label('BASE SALARY (MONTHLY)'),
          _numberField(_baseSalaryCtrl, hint: 'e.g. 15000'),
          const SizedBox(height: 14),
          _readOnlyRow('TOTAL OT THIS MONTH', _rs(_totalOtAmount), kAmber),
          if (_halfDayRecords.isNotEmpty) ...[
            const SizedBox(height: 14),
            _halfDaySection(),
          ],
          const SizedBox(height: 16),
          ..._deductionFields(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addDeduction,
              icon: const Icon(Icons.add, size: 18),
              label: Text('ADD DEDUCTION', style: mono(12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: kGreen,
                side: const BorderSide(color: kGreen),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: kGreen.withOpacity(0.25)),
          const SizedBox(height: 14),
          _readOnlyRow('TOTAL IN-HAND', _rs(_totalInHand), kGreen, big: true),
        ],
      ]),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: mono(11, color: kGreen.withOpacity(0.65))),
      );

  Widget _monthPicker() {
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - i));
    return PopupMenuButton<DateTime>(
      color: kBg,
      onSelected: _pickMonth,
      itemBuilder: (_) => months
          .map((m) => PopupMenuItem(value: m, child: Text('${kMonths[m.month - 1]} ${m.year}', style: mono(13))))
          .toList(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: neonBox(),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_month == null ? 'SELECT MONTH' : '${kMonths[_month!.month - 1]} ${_month!.year}',
              style: mono(13, bold: true)),
          const Icon(Icons.arrow_drop_down, color: kGreen),
        ]),
      ),
    );
  }

  Widget _numberField(TextEditingController c, {required String hint}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: mono(15, bold: true),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: mono(13, color: kGreen.withOpacity(0.3)),
          prefixText: '₹ ',
          prefixStyle: mono(15, bold: true),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kGreen.withOpacity(0.4))),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kGreen, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );

  Widget _readOnlyRow(String label, String value, Color color, {bool big = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: mono(big ? 13 : 12, color: kGreen.withOpacity(0.7), bold: big)),
          Text(value, style: mono(big ? 20 : 14, color: color, bold: true)),
        ],
      );

  Widget _halfDaySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: neonBox(color: kRed),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('HALF DAY DEDUCTION (${_halfDayRecords.length})', style: mono(11, color: kRed, bold: true)),
          Text('-${_rs(_halfDayDeduction)}', style: mono(13, color: kRed, bold: true)),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _halfDayRecords
              .map((r) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: kRed.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(fmtDateShort(r.date), style: mono(10, color: kRed)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        Text('In dinon 8h30m se 30 min ya zyada kam kaam hua tha (pehli short day maaf hai).',
            style: mono(10, color: kRed.withOpacity(0.7))),
      ]),
    );
  }

  List<Widget> _deductionFields() {
    final widgets = <Widget>[];
    for (var i = 0; i < _deductions.length; i++) {
      final d = _deductions[i];
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: neonBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('DEDUCT ${i + 1}', style: mono(11, bold: true)),
              GestureDetector(
                onTap: () => _removeDeduction(d),
                child: const Icon(Icons.close, color: kRed, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: d.reason,
              style: mono(13),
              decoration: InputDecoration(
                hintText: 'Reason (e.g. Late fine)',
                hintStyle: mono(12, color: kGreen.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kGreen.withOpacity(0.4))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kGreen, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            _numberField(d.amount, hint: 'Amount'),
          ]),
        ),
      ));
    }
    return widgets;
  }
}
