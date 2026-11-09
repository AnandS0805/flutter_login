import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

import 'registration_page.dart';
import '../services/auth_service.dart';
import '../services/token_service.dart';
import '../attendance/attendance_page.dart';

/// Smooth fade + slight slide transition used to move between pages.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  static const _bootLines = [
    '> booting secure_login v2.0 ...',
    '> encryption: AES-256 [ACTIVE]',
    '> enter credentials to gain access',
  ];

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  final Map<String, String> _errors = {};

  bool _hidePassword = true;

  HackerBtnState _status = HackerBtnState.idle;

  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker((elapsed) {
    _time.value = elapsed.inMicroseconds / 1000000.0;
  });

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  late final AnimationController _type = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();

    _intro.forward();
    _type.forward();
    _pulse.repeat(reverse: true);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.of(context).disableAnimations) {
      _ticker.stop();
      _pulse.stop();
      _intro.value = 1;
      _type.value = 1;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();

    _intro.dispose();
    _type.dispose();
    _pulse.dispose();

    _emailController.dispose();
    _passwordController.dispose();

    _emailFocus.dispose();
    _passwordFocus.dispose();

    _audioPlayer.dispose();

    super.dispose();
  }

  // --------------------------------------------------
  // Validation
  // --------------------------------------------------

  Map<String, String> _validate() {
    final errors = <String, String>{};

    final email = _emailController.text.trim();

    if (email.isEmpty) {
      errors['email'] = 'Please enter your email address.';
    } else if (!RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[A-Za-z]{2,}$')
        .hasMatch(email)) {
      errors['email'] = 'Enter a valid email, for example name@example.com.';
    }

    final password = _passwordController.text;

    if (password.isEmpty) {
      errors['password'] = 'Please enter your password.';
    } else if (password.length < 8) {
      errors['password'] = 'Password must be at least 8 characters long.';
    }

    return errors;
  }

  void _onChanged(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors.remove(key));
    }
  }

  // --------------------------------------------------
  // Audio
  // --------------------------------------------------

  Future<void> _playSound(String fileName) async {
    final audioData = await rootBundle.load('assets/audio/$fileName');
    debugPrint('Audio asset loaded: ${audioData.lengthInBytes} bytes');
    try {
      await _audioPlayer.stop();

      await _audioPlayer.play(AssetSource('audio/$fileName'));
    } catch (e) {
      debugPrint('Audio Error: $e');
    }
  }

  // --------------------------------------------------
  // Login
  // --------------------------------------------------

  Future<void> _login() async {
    if (_status != HackerBtnState.idle) return;

    FocusScope.of(context).unfocus();

    final errors = _validate();

    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });

      (errors.containsKey('email') ? _emailFocus : _passwordFocus)
          .requestFocus();

      return;
    }

    setState(() => _status = HackerBtnState.loading);

    try {
      final authService = AuthService();

      // Step 1: Login API Call
      final response = await authService.userLogin(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      debugPrint('Login Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Step 2: Convert JSON Response
        final responseData = jsonDecode(response.body);

        // Step 3: Get Tokens
        final accessToken = responseData['accessToken'];
        final refreshToken = responseData['refreshToken'];

        if (accessToken is! String ||
            accessToken.isEmpty ||
            refreshToken is! String ||
            refreshToken.isEmpty) {
          throw Exception('Token Not Found');
        }

        // Step 4: Save Both Tokens
        final tokenService = TokenService();

        await tokenService.saveRefreshToken(refreshToken);
        await tokenService.savetoken(accessToken);

        // Step 5: Get Saved Access Token
        final savedToken = await tokenService.getToken();

        if (savedToken == null || savedToken.isEmpty) {
          throw Exception('Access Token Not Found');
        }

        debugPrint('Token Saved Successfully');

        if (!mounted) return;

        // Step 6: Profile API Call
        // AuthService automatically handles 401 and token refresh.

        final profileResponse = await authService.getUserProfile(
          token: savedToken,
        );

        if (!mounted) return;

        // Step 7: Check Profile API Status
        debugPrint('Profile Status: ${profileResponse.statusCode}');

        if (profileResponse.statusCode != 200) {
          throw Exception('Profile API Failed');
        }

        // Step 8: Convert Profile JSON
        final profile = jsonDecode(profileResponse.body);

        final user = (profile is Map && profile['user'] is Map)
            ? profile['user']
            : profile;

        // Step 9: Extract User Details
        final name = (user['name'] ?? 'Agent').toString();

        final email = (user['email'] ?? _emailController.text.trim())
            .toString();

        final mobile = (user['mobile'] ?? '').toString();

        if (!mounted) return;

        // Step 10: Login Success
        setState(() => _status = HackerBtnState.success);

        _showMessage('Logged in successfully.');

        // Success Sound
        unawaited(_playSound('login_success.mp3'));

        // Wait for Sound
        await Future.delayed(const Duration(milliseconds: 2000));

        if (!mounted) return;

        // Step 11: Navigate to Attendance Page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AttendancePage(userName: name, email: email, mobile: mobile),
          ),
        );
      } else {
        // Invalid Login
        if (!mounted) return;

        setState(() => _status = HackerBtnState.idle);

        _showMessage('Invalid email or password.', isError: true);

        // Vibration + Invalid Login Sound
        unawaited(
          Future.wait([
            Vibration.vibrate(duration: 700, amplitude: 255),
            _playSound('invalid_login.mp3'),
          ]),
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() => _status = HackerBtnState.idle);

      _showMessage(
        'Unable to connect to server. Please try again.',
        isError: true,
      );

      debugPrint('Login Error: $error');
    }
  }

  // --------------------------------------------------
  // Snackbar
  // --------------------------------------------------

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.panel,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: isError ? Colors.red : AppColors.primary),
          ),
          content: Text(
            '> $message',
            style: mono(
              size: 13.5,
              weight: FontWeight.w700,
              color: isError ? Colors.red : AppColors.primary,
            ),
          ),
        ),
      );
  }

  // --------------------------------------------------
  // Navigation
  // --------------------------------------------------

  void _goToRegister() {
    FocusScope.of(context).unfocus();

    Navigator.pushReplacement(context, fadeRoute(const RegistrationPage()));
  }

  // --------------------------------------------------
  // UI Helpers
  // --------------------------------------------------

  Widget _reveal(
    int index,
    Widget child, {
    Offset from = const Offset(0, 0.1),
  }) {
    final start = (index * 0.09).clamp(0.0, 0.6);
    final end = (start + 0.4).clamp(0.0, 1.0);

    final fade = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOut),
    );

    final slide = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(begin: from, end: Offset.zero).animate(slide),
        child: child,
      ),
    );
  }

  // --------------------------------------------------
  // Build UI - Original Design Preserved
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(child: MatrixRain(time: _time)),

          const Positioned.fill(child: ScanlineOverlay()),

          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0.0, constraints.maxHeight - 50),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _reveal(
                          0,
                          TerminalPanel(
                            title: 'root@secure-portal:~/login',
                            pulse: _pulse,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '// AUTHORIZED_ACCESS_ONLY',
                                  style: mono(
                                    size: 11,
                                    color: AppColors.muted,
                                    spacing: 2,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                GlitchText('USER LOGIN', time: _time),

                                const SizedBox(height: 14),

                                BootLog(
                                  lines: _bootLines,
                                  progress: _type,
                                  time: _time,
                                ),

                                const SizedBox(height: 18),

                                Container(height: 1, color: AppColors.line),

                                const SizedBox(height: 18),

                                _reveal(
                                  2,
                                  HackerField(
                                    tag: 'MAIL',
                                    label: 'email_address',
                                    hint: 'name@example.com',
                                    controller: _emailController,
                                    focusNode: _emailFocus,
                                    error: _errors['email'],
                                    keyboardType: TextInputType.emailAddress,
                                    onChanged: (_) => _onChanged('email'),
                                  ),
                                  from: const Offset(-0.1, 0),
                                ),

                                const SizedBox(height: 14),

                                _reveal(
                                  3,
                                  HackerField(
                                    tag: 'PWD',
                                    label: 'password',
                                    hint: 'Enter your password',
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    error: _errors['password'],
                                    obscure: _hidePassword,
                                    onToggleObscure: () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onChanged: (_) => _onChanged('password'),
                                    onSubmitted: (_) => _login(),
                                  ),
                                  from: const Offset(0.1, 0),
                                ),

                                const SizedBox(height: 24),

                                _reveal(
                                  4,
                                  Row(
                                    children: [
                                      Expanded(
                                        child: HackerButton(
                                          label: 'LOGIN',
                                          time: _time,
                                          state: _status,
                                          successLabel: 'OK',
                                          busyLabel: 'WAIT',
                                          onTap: _login,
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: HackerButton(
                                          label: 'REGISTER',
                                          time: _time,
                                          filled: false,
                                          color: AppColors.cyan,
                                          onTap: _status == HackerBtnState.idle
                                              ? _goToRegister
                                              : null,
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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
