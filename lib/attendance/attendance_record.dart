// lib/attendance/attendance_record.dart

const kDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const kMonths = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
];

String two(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String fmtTime(DateTime? t) {
  if (t == null) return '--:--';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${two(h)}:${two(t.minute)} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

String fmtDuration(Duration d) => '${d.inHours}h ${two(d.inMinutes % 60)}m';

/// +1h 20m / -0h 45m / 0h 00m
String fmtSigned(Duration d) {
  if (d == Duration.zero) return '0h 00m';
  return d.isNegative ? '-${fmtDuration(-d)}' : '+${fmtDuration(d)}';
}

// "2026-11-05" -> "05-11-2026"
String fmtDate(String key) {
  final p = key.split('-');
  return '${p[2]}-${p[1]}-${p[0]}';
}

// "2026-11-05" -> "05-11 Thu"
String fmtDateShort(String key) {
  final d = DateTime.parse(key);
  return '${two(d.day)}-${two(d.month)} ${kDays[d.weekday - 1]}';
}

class AttendanceRecord {
  /// Base work = 8 hours 30 minutes (8.30)
  static const Duration baseWork = Duration(hours: 8, minutes: 30);

  final String date; // yyyy-MM-dd
  DateTime? punchIn;
  DateTime? punchOut;

  AttendanceRecord({required this.date, this.punchIn, this.punchOut});

  bool get isComplete => punchIn != null && punchOut != null;

  Duration get worked => isComplete ? punchOut!.difference(punchIn!) : Duration.zero;

  /// SIGNED overtime: 8h30 se zyada kaam => plus, kam kaam => minus.
  Duration get overtime => isComplete ? worked - baseWork : Duration.zero;

  Map<String, dynamic> toJson() => {
        'date': date,
        'punchIn': punchIn?.toIso8601String(),
        'punchOut': punchOut?.toIso8601String(),
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        date: j['date'],
        punchIn: j['punchIn'] == null ? null : DateTime.parse(j['punchIn']),
        punchOut: j['punchOut'] == null ? null : DateTime.parse(j['punchOut']),
      );
}
