// lib/attendance/attendance_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_record.dart';

/// Data user ke email ke hisaab se alag save hota hai,
/// taaki ek phone pe 2 account ka data mix na ho.
/// Backend jodte waqt sirf loadAll() aur save() ko API calls se badalna hai.
class AttendanceStorage {
  final String userKey;
  AttendanceStorage(this.userKey);

  String get _key => 'attendance_records_${userKey.toLowerCase()}';

  Future<Map<String, AttendanceRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final Map<String, dynamic> map = jsonDecode(raw);
    return map.map((k, v) => MapEntry(k, AttendanceRecord.fromJson(v)));
  }

  Future<void> save(AttendanceRecord record) async {
    final all = await loadAll();
    all[record.date] = record;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
