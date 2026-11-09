import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'login_page.dart'; // fadeRoute + LoginPage

import 'package:vibration/vibration.dart';

// =============================================================================
// Shared theme + widgets (also used by login_page.dart)
// =============================================================================

/// Hacker terminal palette: near-black, neon green, cyan and alert red.
class AppColors {
  static const primary = Color(0xFF00FF88); // neon green
  static const background = Color(0xFF030806); // near black
  static const panel = Color(0xFF06110B);
  static const cyan = Color(0xFF00E5FF);
  static const text = Color(0xFFCFFFE5);
  static const muted = Color(0xFF4F9A6E);
  static const line = Color(0xFF14402A);
  static const error = Color(0xFFFF3B5C);
  static const warn = Color(0xFFFFC107);
}

/// Monospace text style used everywhere for the terminal look.
TextStyle mono({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color color = AppColors.text,
  double? spacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const [
      'Courier New',
      'Courier',
      'Menlo',
      'Roboto Mono',
    ],
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
    height: height,
  );
}

// ---------------------------------------------------------------------------
// Matrix rain background
// ---------------------------------------------------------------------------

class MatrixRain extends StatefulWidget {
  const MatrixRain({super.key, required this.time});

  /// Elapsed seconds, updated every frame by the page's ticker.
  final ValueNotifier<double> time;

  @override
  State<MatrixRain> createState() => _MatrixRainState();
}

class _MatrixRainState extends State<MatrixRain> {
  static const _chars = '01<>/{}[]#\$%&*+=?!ABCDEFX';
  static const _alphas = [18, 36, 70, 120, 235];

  late final List<List<TextPainter>> _glyphs;

  @override
  void initState() {
    super.initState();
    _glyphs = [
      for (final a in _alphas)
        [
          for (var i = 0; i < _chars.length; i++)
            TextPainter(
              text: TextSpan(
                text: _chars[i],
                style: mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color:
                      (a == _alphas.last
                              ? const Color(0xFFE6FFF2)
                              : AppColors.primary)
                          .withAlpha(a),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _RainPainter(widget.time, _glyphs),
        size: Size.infinite,
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.time, this.glyphs) : super(repaint: time);

  final ValueNotifier<double> time;
  final List<List<TextPainter>> glyphs;

  static const _cellW = 16.0;
  static const _cellH = 18.0;

  double _hash(int x) {
    final v = math.sin(x * 12.9898) * 43758.5453;
    return v - v.floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final cols = (size.width / _cellW).floor();
    final rows = (size.height / _cellH).ceil();
    final n = glyphs[0].length;
    final flicker = (t * 12).floor();

    for (var c = 0; c < cols; c++) {
      final h = _hash(c);
      final speed = 4 + h * 8; // rows per second
      final trail = 8 + ((h * 100).floor() % 10);
      final cycle = rows + trail + 6;
      final offset = _hash(c + 97) * cycle;
      final headRow = ((t * speed + offset) % cycle).floor();

      for (var i = 0; i < trail; i++) {
        final row = headRow - i;
        if (row < 0 || row >= rows) continue;
        final level = i == 0
            ? 4
            : i < 3
            ? 3
            : i < trail * 0.5
            ? 2
            : i < trail * 0.8
            ? 1
            : 0;
        final idx = i == 0 ? (c * 7 + flicker) % n : (c * 31 + row * 17) % n;
        glyphs[level][idx].paint(canvas, Offset(c * _cellW + 2, row * _cellH));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// CRT scanlines + vignette
// ---------------------------------------------------------------------------

class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _ScanPainter(), size: Size.infinite),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [Colors.transparent, Colors.black.withAlpha(200)],
          stops: const [0.5, 1],
        ).createShader(rect),
    );
    final line = Paint()..color = const Color(0x22000000);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Glitching title
// ---------------------------------------------------------------------------

class GlitchText extends StatelessWidget {
  const GlitchText(this.text, {super.key, required this.time, this.size = 28});

  final String text;
  final ValueNotifier<double> time;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: time,
      builder: (context, t, _) {
        final phase = t % 4.0;
        final glitch = phase < 0.16 || (phase > 2.0 && phase < 2.08);
        final dx = glitch ? math.sin(t * 90) * 3 : 0.0;

        Widget layer(Color c, double off, {bool glow = false}) {
          return Transform.translate(
            offset: Offset(off, 0),
            child: Text(
              text,
              style:
                  mono(
                    size: size,
                    weight: FontWeight.w800,
                    color: c,
                    spacing: 1,
                  ).copyWith(
                    shadows: glow
                        ? [
                            Shadow(
                              color: AppColors.primary.withAlpha(150),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
            ),
          );
        }

        return Stack(
          children: [
            if (glitch) layer(AppColors.error.withAlpha(210), -3 + dx),
            if (glitch) layer(AppColors.cyan.withAlpha(210), 3 - dx),
            layer(AppColors.primary, 0, glow: true),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Terminal window container
// ---------------------------------------------------------------------------

class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.title,
    required this.pulse,
    required this.child,
  });

  final String title;
  final Animation<double> pulse;
  final Widget child;

  Widget _dot(Color c) => Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.only(right: 6),
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = 35 + (pulse.value * 45).round();
        return Container(
          decoration: BoxDecoration(
            color: AppColors.panel.withAlpha(238),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withAlpha(
                110 + (pulse.value * 60).round(),
              ),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(glow),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B1C13),
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    children: [
                      _dot(AppColors.error),
                      _dot(AppColors.warn),
                      _dot(AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(size: 12, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Typewriter boot log with blinking cursor
// ---------------------------------------------------------------------------

class BootLog extends StatelessWidget {
  const BootLog({
    super.key,
    required this.lines,
    required this.progress,
    required this.time,
  });

  final List<String> lines;
  final Animation<double> progress;
  final ValueNotifier<double> time;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([progress, time]),
      builder: (context, _) {
        final total = lines.fold<int>(0, (s, l) => s + l.length);
        var shown = (total * progress.value).floor();
        final blinkOn = (time.value * 2.5).floor().isEven;
        final children = <Widget>[];

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final isLast = i == lines.length - 1;
          final take = math.min(shown, line.length);
          shown -= take;
          final typedAll = take == line.length;
          final style = mono(
            size: 12,
            height: 1.5,
            color: isLast ? AppColors.text : AppColors.muted,
          );
          children.add(
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: line.substring(0, take), style: style),
                  if (!typedAll || isLast)
                    TextSpan(
                      text: '_',
                      style: style.copyWith(
                        color: blinkOn ? AppColors.primary : Colors.transparent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          );
          if (!typedAll) break;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Terminal-style text field
// ---------------------------------------------------------------------------

class HackerField extends StatefulWidget {
  const HackerField({
    super.key,
    required this.tag,
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.error,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.footer,
  });

  final String tag;
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String? error;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final Widget? footer;

  @override
  State<HackerField> createState() => _HackerFieldState();
}

class _HackerFieldState extends State<HackerField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant HackerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Shake only when an error newly appears on this field.
    if (oldWidget.error == null && widget.error != null) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 4) * 7 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: widget.focusNode,
            builder: (context, _) {
              final focused = widget.focusNode.hasFocus;
              final accent = hasError
                  ? AppColors.error
                  : focused
                  ? AppColors.primary
                  : AppColors.muted;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '\$ ',
                        style: mono(
                          size: 13,
                          weight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      Text(
                        widget.label,
                        style: mono(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: accent,
                          spacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: focused
                          ? const Color(0xFF0A2216)
                          : const Color(0xFF040C08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: hasError
                            ? AppColors.error
                            : focused
                            ? AppColors.primary
                            : AppColors.line,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (hasError ? AppColors.error : AppColors.primary)
                                  .withAlpha(focused || hasError ? 55 : 0),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 6),
                          child: Text(
                            '[${widget.tag}]',
                            style: mono(
                              size: 12,
                              weight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            obscureText: widget.obscure,
                            obscuringCharacter: '*',
                            keyboardType: widget.keyboardType,
                            inputFormatters: widget.inputFormatters,
                            textInputAction: widget.textInputAction,
                            textCapitalization: widget.textCapitalization,
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: widget.onChanged,
                            onSubmitted: widget.onSubmitted,
                            cursorColor: AppColors.primary,
                            cursorWidth: 9,
                            cursorHeight: 18,
                            cursorRadius: Radius.zero,
                            style: mono(size: 15, weight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: widget.hint,
                              hintStyle: mono(
                                size: 14,
                                weight: FontWeight.w400,
                                color: AppColors.muted.withAlpha(150),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 15,
                              ),
                            ),
                          ),
                        ),
                        if (widget.onToggleObscure != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onToggleObscure,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Text(
                                widget.obscure ? 'SHOW' : 'HIDE',
                                style: mono(
                                  size: 11.5,
                                  weight: FontWeight.w800,
                                  color: AppColors.cyan,
                                  spacing: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          // Error message: opens smoothly and collapses when cleared.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-0.05, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: hasError
                  ? Padding(
                      key: ValueKey(widget.error),
                      padding: const EdgeInsets.only(top: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[ERR] ',
                            style: mono(
                              size: 12,
                              weight: FontWeight.w800,
                              color: AppColors.error,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.error!,
                              style: mono(
                                size: 12,
                                height: 1.3,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('no-error'),
                      width: double.infinity,
                    ),
            ),
          ),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terminal-style button
// ---------------------------------------------------------------------------

enum HackerBtnState { idle, loading, success }

class HackerButton extends StatefulWidget {
  const HackerButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.time,
    this.filled = true,
    this.color = AppColors.primary,
    this.state = HackerBtnState.idle,
    this.busyLabel = 'PROCESSING',
    this.successLabel = 'ACCESS GRANTED',
  });

  final String label;
  final VoidCallback? onTap;
  final ValueNotifier<double> time;
  final bool filled;
  final Color color;
  final HackerBtnState state;
  final String busyLabel;
  final String successLabel;

  @override
  State<HackerButton> createState() => _HackerButtonState();
}

class _HackerButtonState extends State<HackerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final idle = widget.state == HackerBtnState.idle;
    final base = enabled ? widget.color : widget.color.withAlpha(80);
    final fg = widget.filled
        ? AppColors.background
        : (enabled ? widget.color : widget.color.withAlpha(110));

    final style = mono(
      size: 15,
      weight: FontWeight.w800,
      color: fg,
      spacing: 1.5,
    );

    Widget label;
    if (widget.state == HackerBtnState.loading) {
      label = ValueListenableBuilder<double>(
        valueListenable: widget.time,
        builder: (context, t, _) {
          final spin = '|/-\\'[(t * 10).floor() % 4];
          return Text('[$spin] ${widget.busyLabel}', maxLines: 1, style: style);
        },
      );
    } else if (widget.state == HackerBtnState.success) {
      label = Text('[OK] ${widget.successLabel}', maxLines: 1, style: style);
    } else {
      label = Text('[ ${widget.label} ]', maxLines: 1, style: style);
    }

    return GestureDetector(
      onTapDown: (_) {
        if (enabled && idle) setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.filled ? base : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: base, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: base.withAlpha(
                  enabled && idle ? (widget.filled ? 100 : 40) : 0,
                ),
                blurRadius: 18,
              ),
            ],
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: label),
        ),
      ),
    );
  }
}

// =============================================================================
// Registration page
// =============================================================================

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage>
    with TickerProviderStateMixin {
  static const _keys = ['name', 'email', 'mobile', 'password', 'confirm'];
  static const _mismatchMessage = 'Passwords do not match.';
  static const _bootLines = [
    '> booting secure_register v2.0 ...',
    '> encryption: AES-256 [ACTIVE]',
    '> awaiting new user credentials',
  ];

  final Map<String, TextEditingController> _controllers = {
    for (final k in _keys) k: TextEditingController(),
  };
  final Map<String, FocusNode> _focusNodes = {
    for (final k in _keys) k: FocusNode(),
  };

  // Current error message for each field (absent = no error).
  final Map<String, String> _errors = {};

  bool _hidePassword = true;
  bool _hideConfirm = true;
  HackerBtnState _status = HackerBtnState.idle;

  // Seconds since the page opened; drives rain, glitch, cursor and spinner.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) {
    _time.value = elapsed.inMicroseconds / 1000000.0;
  });

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _type = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
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
    // Respect the system "reduce motion" setting.
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
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _controllers[key]!.text;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  Map<String, String> _validate() {
    final errors = <String, String>{};

    final name = _text('name').trim();
    if (name.isEmpty) {
      errors['name'] = 'Please enter your full name.';
    } else if (name.length < 3) {
      errors['name'] = 'Name must be at least 3 characters long.';
    } else if (!RegExp(r"^[A-Za-z][A-Za-z .'-]*$").hasMatch(name)) {
      errors['name'] = 'Name can only contain letters and spaces.';
    }

    final email = _text('email').trim();
    if (email.isEmpty) {
      errors['email'] = 'Please enter your email address.';
    } else if (!RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[A-Za-z]{2,}$')
        .hasMatch(email)) {
      errors['email'] = 'Enter a valid email, for example name@example.com.';
    }

    final mobile = _text('mobile').trim();
    if (mobile.isEmpty) {
      errors['mobile'] = 'Please enter your mobile number.';
    } else if (mobile.length != 10) {
      errors['mobile'] = 'Mobile number must be exactly 10 digits.';
    } else if (!RegExp(r'^[6-9]').hasMatch(mobile)) {
      errors['mobile'] = 'Mobile number must start with 6, 7, 8 or 9.';
    }

    final password = _text('password');
    if (password.isEmpty) {
      errors['password'] = 'Please create a password.';
    } else if (password.length < 8) {
      errors['password'] = 'Password must be at least 8 characters long.';
    } else if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      errors['password'] = 'Password must contain letters and numbers.';
    }

    final confirm = _text('confirm');
    if (confirm.isEmpty) {
      errors['confirm'] = 'Please confirm your password.';
    } else if (confirm != password) {
      errors['confirm'] = _mismatchMessage;
    }

    return errors;
  }

  // Removes the error of a field as soon as the user starts typing in it.
  void _onChanged(String key) {
    setState(() {
      _errors.remove(key);
      if (key == 'password' && _errors['confirm'] == _mismatchMessage) {
        _errors.remove('confirm');
      }
    });
  }

  // Number of fields that are currently valid (drives the progress bar).
  int get _completed {
    final errors = _validate();
    return _keys.where((k) => !errors.containsKey(k)).length;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _register() async {
    if (_status != HackerBtnState.idle) return;
    FocusScope.of(context).unfocus();

    final errors = _validate();
    if (errors.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      final firstKey = _keys.firstWhere(errors.containsKey);
      _focusNodes[firstKey]!.requestFocus();
      return;
    }

    setState(() => _status = HackerBtnState.loading);

    // TODO: Replace this delay with your real API call.
    // await Future.delayed(const Duration(seconds: 2));
    // if (!mounted) return;
    try {
      // Flutter form se values lekar Node.js API call karenge
      final response = await _authService.registerUser(
        name: _controllers['name']!.text.trim(),
        email: _controllers['email']!.text.trim(),
        mobile: _controllers['mobile']!.text.trim(),
        password: _controllers['password']!.text,
        confirmPassword: _controllers['confirm']!.text,
      );

      if (!mounted) return;

      // Server ka response terminal me check karenge
      // Server ka response print karenge
      print(response.statusCode);
      print(response.body);

      // Agar status code 201 hai, to registration successful hai
      if (response.statusCode == 201) {
        setState(() {
          _status = HackerBtnState.success;
        });

        _showMessage('Account created successfully.');
      } else {
        // Agar registration fail hua, to server ka error message dikhayenge
        setState(() {
          _status = HackerBtnState.idle;
        });

        // _showMessage(response.body);
        _showMessage(response.body, isError: true);
        return;
      }
    } catch (e) {
      // Error terminal mein print karenge
      print('Registration Error: $e');

      // Screen abhi active hai ya nahi check karenge
      if (!mounted) return;

      // Button ko normal state mein laayenge
      setState(() {
        _status = HackerBtnState.idle;
      });

      // User ko error message dikhayenge
      _showMessage('Something went wrong. Please try again.');
    }

    // if (!mounted) return;
    // setState(() => _status = HackerBtnState.success);
    // _showMessage('Account created successfully.');

    // await Future.delayed(const Duration(milliseconds: 1800));
    // if (!mounted) return;

    // for (final c in _controllers.values) {
    //   c.clear();
    // }
    // setState(() => _status = HackerBtnState.idle);
  }

  final AuthService _authService = AuthService(); //Is object ke through hum registerUser() function call karenge.

  void _login() {
    FocusScope.of(context).unfocus();
    Navigator.pushReplacement(context, fadeRoute(const LoginPage()));
  }

  void _showMessage(String message, {bool isError = false}) async {
    if (isError) {
      Vibration.vibrate(duration: 150);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.panel,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isError ? AppColors.error : AppColors.primary,
            ),
          ),
          content: Text(
            '> $message',
            style: mono(
              size: 13.5,
              weight: FontWeight.w700,
              color: isError ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
      );

    // 1. Success animation ko 1.8 seconds tak dikhayenge
    await Future.delayed(const Duration(milliseconds: 1800));

    // 2. Check karenge ki widget abhi screen par hai ya nahi
    if (!mounted) return;

    // 3. Registration ke saare fields clear karenge
    for (final c in _controllers.values) {
      c.clear();
    }

    // 4. Register button ko normal state mein laayenge
    setState(() {
      _status = HackerBtnState.idle;
    });
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  Widget _reveal(
    int index,
    Widget child, {
    Offset from = const Offset(0, 0.1),
  }) {
    final start = (index * 0.07).clamp(0.0, 0.6);
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

  Widget _field(int index, HackerField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _reveal(index, field, from: Offset(index.isEven ? -0.1 : 0.1, 0)),
    );
  }

  Widget _progress() {
    final done = _completed;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: done / _keys.length),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        const segs = 20;
        final filled = (v * segs).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'FORM_INTEGRITY',
                  style: mono(size: 11, color: AppColors.muted, spacing: 1.5),
                ),
                const Spacer(),
                Text(
                  '${(v * 100).round()}%',
                  style: mono(
                    size: 11,
                    weight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: List.generate(segs, (i) {
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 8,
                    margin: EdgeInsets.only(right: i == segs - 1 ? 0 : 2),
                    color: i < filled ? AppColors.primary : AppColors.line,
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  int get _strengthScore {
    final p = _text('password');
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score;
  }

  Widget _strengthMeter() {
    final score = _strengthScore;
    const labels = ['TOO WEAK', 'WEAK', 'FAIR', 'GOOD', 'STRONG'];
    const colors = [
      AppColors.error,
      AppColors.error,
      AppColors.warn,
      AppColors.cyan,
      AppColors.primary,
    ];
    final show = _text('password').isNotEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Text(
                    'STRENGTH',
                    style: mono(size: 11, color: AppColors.muted, spacing: 1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: List.generate(4, (i) {
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 6,
                            margin: EdgeInsets.only(right: i == 3 ? 0 : 3),
                            color: i < score ? colors[score] : AppColors.line,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    labels[score],
                    style: mono(
                      size: 11,
                      weight: FontWeight.w800,
                      color: colors[score],
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _reveal(
                      0,
                      TerminalPanel(
                        title: 'root@secure-portal:~/register',
                        pulse: _pulse,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '// NEW_USER_REGISTRATION',
                              style: mono(
                                size: 11,
                                color: AppColors.muted,
                                spacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GlitchText('CREATE ACCOUNT', time: _time),
                            const SizedBox(height: 14),
                            BootLog(
                              lines: _bootLines,
                              progress: _type,
                              time: _time,
                            ),
                            const SizedBox(height: 18),
                            _progress(),
                            const SizedBox(height: 18),
                            Container(height: 1, color: AppColors.line),
                            const SizedBox(height: 18),
                            _field(
                              2,
                              HackerField(
                                tag: 'USR',
                                label: 'full_name',
                                hint: 'Enter your full name',
                                controller: _controllers['name']!,
                                focusNode: _focusNodes['name']!,
                                error: _errors['name'],
                                keyboardType: TextInputType.name,
                                textCapitalization: TextCapitalization.words,
                                onChanged: (_) => _onChanged('name'),
                              ),
                            ),
                            _field(
                              3,
                              HackerField(
                                tag: 'MAIL',
                                label: 'email_address',
                                hint: 'name@example.com',
                                controller: _controllers['email']!,
                                focusNode: _focusNodes['email']!,
                                error: _errors['email'],
                                keyboardType: TextInputType.emailAddress,
                                onChanged: (_) => _onChanged('email'),
                              ),
                            ),
                            _field(
                              4,
                              HackerField(
                                tag: 'TEL',
                                label: 'mobile_number',
                                hint: '10-digit mobile number',
                                controller: _controllers['mobile']!,
                                focusNode: _focusNodes['mobile']!,
                                error: _errors['mobile'],
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                onChanged: (_) => _onChanged('mobile'),
                              ),
                            ),
                            _field(
                              5,
                              HackerField(
                                tag: 'PWD',
                                label: 'password',
                                hint: 'At least 8 characters',
                                controller: _controllers['password']!,
                                focusNode: _focusNodes['password']!,
                                error: _errors['password'],
                                obscure: _hidePassword,
                                onToggleObscure: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                onChanged: (_) => _onChanged('password'),
                                footer: _strengthMeter(),
                              ),
                            ),
                            _field(
                              6,
                              HackerField(
                                tag: 'CNF',
                                label: 'confirm_password',
                                hint: 'Re-enter your password',
                                controller: _controllers['confirm']!,
                                focusNode: _focusNodes['confirm']!,
                                error: _errors['confirm'],
                                obscure: _hideConfirm,
                                onToggleObscure: () => setState(
                                  () => _hideConfirm = !_hideConfirm,
                                ),
                                textInputAction: TextInputAction.done,
                                onChanged: (_) => _onChanged('confirm'),
                                onSubmitted: (_) => _register(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _reveal(
                              7,
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: HackerButton(
                                      label: 'REGISTER',
                                      time: _time,
                                      state: _status,
                                      onTap: _register,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: HackerButton(
                                      label: 'LOGIN',
                                      time: _time,
                                      filled: false,
                                      color: AppColors.cyan,
                                      onTap: _status == HackerBtnState.idle
                                          ? _login
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
        ],
      ),
    );
  }
}
