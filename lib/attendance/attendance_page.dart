// lib/attendance/attendance_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vibration/vibration.dart';

import '../services/auth_service.dart';
import 'attendance_record.dart';
import 'attendance_storage.dart';
import 'attendance_theme.dart';
import 'month_history.dart';
import 'salary_calculator.dart';
import '../login_page.dart';
import '../services/token_service.dart';

class AttendancePage extends StatefulWidget {
  final String userName;
  final String email;
  final String mobile;

  const AttendancePage({
    super.key,
    required this.userName,
    required this.email,
    this.mobile = '',
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isCheckingSession = false;
  bool _isLoggingOut = false;

  // Profile API call karke session verify karo.
  // Refresh fail hone par AuthService 401 return karega.
  Future<void> _checkSession() async {
    if (_isCheckingSession || _isLoggingOut) return;

    _isCheckingSession = true;

    try {
      final tokenService = TokenService();
      final token = await tokenService.getToken();

      if (token == null || token.isEmpty) {
        print('Access Token Not Found - Logging Out');
        await _logoutForExpiredSession();
        return;
      }

      final response = await AuthService().getUserProfile(token: token);

      print('Profile Status: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode == 401) {
        print('Session Expired - Logging Out');
        await _logoutForExpiredSession();
      }
    } catch (e) {
      // Network/server issue par user ko logout nahi karna.
      print('Session Check Error: $e');
      _snack('Unable to verify session. Please check your internet.');
    } finally {
      _isCheckingSession = false;
    }
  }

  // Refresh token invalid/expired hone par bina confirmation logout.
  Future<void> _logoutForExpiredSession() async {
    if (_isLoggingOut) return;

    _isLoggingOut = true;
    await TokenService().deleteAllTokens();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSession();
    }
  }

  late final AttendanceStorage _storage;
  final _auth = LocalAuthentication();

  Map<String, AttendanceRecord> _records = {};
  late final AnimationController _pulse;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _pressed = false;
  String _status = '> SYSTEM READY';

  AttendanceRecord? get _today => _records[dateKey(_now)];
  bool get _isIn => _today?.punchIn != null && _today?.punchOut == null;
  bool get _isDone => _today?.punchIn != null && _today?.punchOut != null;

  /// Aaj ka abhi tak ka kaam (punch in ke baad live badhta hai)
  Duration get _workedNow {
    final r = _today;
    if (r?.punchIn == null) return Duration.zero;
    return (r!.punchOut ?? _now).difference(r.punchIn!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storage = AttendanceStorage(widget.email);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();

    // Attendance page open hone par session verify karo.
    _checkSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _storage.loadAll();
    if (mounted) setState(() => _records = data);
  }

  // ---------- Vibration (UX feedback) ----------
  Future<void> _vibrate(List<int> pattern) async {
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: pattern);
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  // ---------- Punch logic ----------
  Future<void> _punch() async {
    final now = DateTime.now();
    final key = dateKey(now);
    final rec = _records[key] ?? AttendanceRecord(date: key);

    if (rec.punchIn == null) {
      rec.punchIn = now;
      _status = '> PUNCH IN SUCCESS @ ${fmtTime(now)}';
      _vibrate([0, 80, 60, 160]); // chhota double buzz
    } else if (rec.punchOut == null) {
      rec.punchOut = now;
      _status = '> PUNCH OUT SUCCESS @ ${fmtTime(now)}';
      _vibrate([0, 200, 80, 200, 80, 300]); // lamba triple buzz
    } else {
      return;
    }
    _records[key] = rec;
    await _storage.save(rec);
    if (mounted) setState(() {});
  }

  /// Button tap: punch out se pehle confirm (galti se tap na ho)
  Future<void> _onPunchTap() async {
    if (_isDone) return;
    if (_isIn) {
      final left = AttendanceRecord.baseWork - _workedNow;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBg,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: kGreen),
            borderRadius: BorderRadius.circular(10),
          ),
          title: Text('> CONFIRM PUNCH OUT', style: mono(15, bold: true)),
          content: Text(
            left > Duration.zero
                ? 'Abhi 8h 30m poore nahi hue. ${fmtDuration(left)} baaki hai. Phir bhi punch out karna hai?'
                : 'Punch out karna hai?',
            style: mono(13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'CANCEL',
                style: mono(13, color: kGreen.withValues(alpha: 0.6)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'PUNCH OUT',
                style: mono(13, color: kRed, bold: true),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _punch();
  }

  Future<void> _fingerprintPunch() async {
    if (_isDone) return;
    try {
      if (!await _auth.canCheckBiometrics) {
        _snack('Fingerprint is device pe available nahi hai');
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason:
            'Scan fingerprint to ${_isIn ? 'punch out' : 'punch in'}',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (ok) {
        await _punch();
      } else {
        _vibrate([0, 300]);
      }
    } catch (e) {
      _snack('Fingerprint error: $e');
    }
  }

  // ---------- Logout ----------
  Future<void> _onLogoutTap() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: kGreen),
          borderRadius: BorderRadius.circular(10),
        ),
        title: Text('> CONFIRM LOGOUT', style: mono(15, bold: true)),
        content: Text('Are you sure you want to log out ?', style: mono(13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: mono(13, color: kGreen.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('LOGOUT', style: mono(13, color: kRed, bold: true)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Logout par Access aur Refresh dono tokens delete karo.
    _isLoggingOut = true;
    await TokenService().deleteAllTokens();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kDim,
        content: Text(msg, style: mono(13)),
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(),
            const SizedBox(height: 16),
            _clockCard(),
            const SizedBox(height: 24),
            Center(child: _punchButton()),
            const SizedBox(height: 14),
            _statusArea(),
            const SizedBox(height: 14),
            Center(child: _fingerprintButton()),
            const SizedBox(height: 20),
            _todaySummary(),
            const SizedBox(height: 28),
            MonthHistory(records: _records),
            const SizedBox(height: 24),
            SalaryCalculator(records: _records),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  Widget _header() {
    final name = widget.userName.trim().isEmpty
        ? 'AGENT'
        : widget.userName.trim();
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGreen, width: 2),
            boxShadow: [
              BoxShadow(color: kGreen.withValues(alpha: 0.4), blurRadius: 12),
            ],
          ),
          child: Text(name[0].toUpperCase(), style: mono(24, bold: true)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> $_greeting,',
                style: mono(11, color: kGreen.withValues(alpha: 0.6)),
              ),
              Text(
                name.toUpperCase(),
                style: mono(19, bold: true),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.email,
                style: mono(11, color: kGreen.withValues(alpha: 0.7)),
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.mobile.isNotEmpty)
                Text(
                  widget.mobile,
                  style: mono(11, color: kGreen.withValues(alpha: 0.7)),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: _onLogoutTap,
          icon: const Icon(Icons.logout, color: kRed, size: 22),
          tooltip: 'Logout',
          style: IconButton.styleFrom(
            side: const BorderSide(color: kRed),
            shape: const CircleBorder(),
          ),
        ),
      ],
    );
  }

  Widget _clockCard() {
    final d = _now;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: neonBox(),
      child: Column(
        children: [
          Text(
            '${two(d.hour)}:${two(d.minute)}:${two(d.second)}',
            style: mono(36, bold: true),
          ),
          const SizedBox(height: 4),
          Text(
            '${kDays[d.weekday - 1].toUpperCase()}, ${fmtDate(dateKey(d))}',
            style: mono(12, color: kGreen.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _punchButton() {
    final Color color = _isDone ? Colors.grey : (_isIn ? kRed : kGreen);
    final String label = _isDone ? 'DONE' : (_isIn ? 'PUNCH OUT' : 'PUNCH IN');
    final IconData icon = _isDone
        ? Icons.check_circle
        : (_isIn ? Icons.logout : Icons.login);

    // 8h30 ka progress ring
    final progress =
        (_workedNow.inSeconds / AttendanceRecord.baseWork.inSeconds).clamp(
          0.0,
          1.0,
        );
    final overBase = _workedNow > AttendanceRecord.baseWork;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = _isDone ? 0.0 : 8 + _pulse.value * 24;
        return SizedBox(
          width: 214,
          height: 214,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 214,
                height: 214,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  color: overBase ? kAmber : kGreen,
                  backgroundColor: kDim,
                ),
              ),
              AnimatedScale(
                scale: _pressed ? 0.9 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTapUp: (_) {
                    setState(() => _pressed = false);
                    _onPunchTap();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.08),
                      border: Border.all(color: color, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: glow,
                          spreadRadius: glow / 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (c, a) =>
                              ScaleTransition(scale: a, child: c),
                          child: Icon(
                            icon,
                            key: ValueKey(label),
                            color: color,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(label, style: mono(18, color: color, bold: true)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusArea() {
    final r = _today;
    String? extra;
    if (_isIn && r?.punchIn != null) {
      final target = r!.punchIn!.add(AttendanceRecord.baseWork);
      extra = '8h 30m poore honge: ${fmtTime(target)}';
    }
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(a),
              child: c,
            ),
          ),
          child: Text(
            _status,
            key: ValueKey(_status),
            textAlign: TextAlign.center,
            style: mono(13),
          ),
        ),
        if (extra != null) ...[
          const SizedBox(height: 6),
          Text('> $extra', style: mono(12, color: kAmber)),
        ],
      ],
    );
  }

  Widget _fingerprintButton() {
    return OutlinedButton.icon(
      onPressed: _isDone ? null : _fingerprintPunch,
      icon: const Icon(Icons.fingerprint, size: 28),
      label: Text(
        _isIn ? 'PUNCH OUT WITH FINGERPRINT' : 'PUNCH IN WITH FINGERPRINT',
        style: mono(12),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: kGreen,
        side: BorderSide(color: _isDone ? kDim : kGreen),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _todaySummary() {
    final r = _today;
    final worked = _workedNow;
    final diff = worked - AttendanceRecord.baseWork; // signed

    // Kaam chal raha ho aur 8h30 poore na hue ho -> "LEFT", warna "OT"
    String lastLabel;
    String lastValue;
    Color lastColor = kGreen;
    if (r?.punchIn == null) {
      lastLabel = 'OT';
      lastValue = '--';
    } else if (_isIn && diff.isNegative) {
      lastLabel = 'LEFT';
      lastValue = fmtDuration(-diff);
    } else {
      lastLabel = 'OT';
      lastValue = fmtSigned(diff);
      lastColor = diff.isNegative ? kRed : kAmber;
    }

    Widget cell(String t, String v, {Color color = kGreen}) => Expanded(
      child: Column(
        children: [
          Text(t, style: mono(10, color: kGreen.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text(v, style: mono(14, color: color, bold: true)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: neonBox(),
      child: Row(
        children: [
          cell('IN', fmtTime(r?.punchIn)),
          cell('OUT', fmtTime(r?.punchOut)),
          cell(
            _isIn ? 'WORKED (LIVE)' : 'WORKED',
            r?.punchIn == null ? '--' : fmtDuration(worked),
          ),
          cell(lastLabel, lastValue, color: lastColor),
        ],
      ),
    );
  }
}
