import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AgriSynth Design System
// Premium Minimalist — Soft Green × Deep Forest × Off-White
// ─────────────────────────────────────────────────────────────────────────────

abstract class AgriColors {
  // Backgrounds
  static const Color offWhite = Color(0xFFF7F5F0);
  static const Color surface = Color(0xFFEFECE4);
  static const Color cardWhite = Color(0xFFFBF9F6);

  // Forest greens
  static const Color deepForest = Color(0xFF0E3D24);
  static const Color forestMid = Color(0xFF165C38);
  static const Color canopy = Color(0xFF1E7A4A);
  static const Color leaf = Color(0xFF2EA05A);
  static const Color softGreen = Color(0xFF7DC99A);
  static const Color mintFrost = Color(0xFFB8E8CA);
  static const Color paleMint = Color(0xFFE2F5EA);

  // Neutrals
  static const Color inkDark = Color(0xFF1A2B22);
  static const Color inkMid = Color(0xFF3D5445);
  static const Color inkLight = Color(0xFF7A9885);
  static const Color borderGhost = Color(0xFFD8E8DC);

  // Semantic
  static const Color error = Color(0xFFD94F4F);
  static const Color errorLight = Color(0xFFFFF0F0);
  static const Color success = Color(0xFF2EA05A);
}

abstract class AgriRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 32;
}

abstract class AgriShadow {
  static List<BoxShadow> card = [
    BoxShadow(
      color: AgriColors.deepForest.withOpacity(0.08),
      blurRadius: 40,
      spreadRadius: 0,
      offset: const Offset(0, 16),
    ),
    BoxShadow(
      color: AgriColors.deepForest.withOpacity(0.04),
      blurRadius: 8,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> button = [
    BoxShadow(
      color: AgriColors.canopy.withOpacity(0.35),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> logoGlow = [
    BoxShadow(
      color: AgriColors.leaf.withOpacity(0.30),
      blurRadius: 40,
      spreadRadius: 4,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: AgriColors.deepForest.withOpacity(0.12),
      blurRadius: 16,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Scaffold Background
// ─────────────────────────────────────────────────────────────────────────────
class AgriBackground extends StatelessWidget {
  final Widget child;
  const AgriBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Warm off-white base
        Container(color: AgriColors.offWhite),
        // Soft radial glow top-left
        Positioned(
          top: -80,
          left: -80,
          child: _glowBlob(240, AgriColors.mintFrost.withOpacity(0.55)),
        ),
        // Bottom-right accent
        Positioned(
          bottom: -60,
          right: -60,
          child: _glowBlob(200, AgriColors.softGreen.withOpacity(0.18)),
        ),
        // Subtle dot texture
        CustomPaint(painter: _DotGridPainter(), size: Size.infinite),
        child,
      ],
    );
  }

  Widget _glowBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AgriColors.softGreen.withOpacity(0.10)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Logo Hero Widget
// ─────────────────────────────────────────────────────────────────────────────
class AgriLogoHero extends StatelessWidget {
  final double size;
  const AgriLogoHero({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'agrisynth_logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AgriColors.forestMid, AgriColors.deepForest],
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: AgriShadow.logoGlow,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Subtle inner highlight
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                width: size * 0.45,
                height: size * 0.45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            AgriWheatIcon(size: size * 0.52, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Wheat Icon (CustomPainter)
// ─────────────────────────────────────────────────────────────────────────────
class AgriWheatIcon extends StatelessWidget {
  final double size;
  final Color color;
  const AgriWheatIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _WheatIconPainter(color),
    );
  }
}

class _WheatIconPainter extends CustomPainter {
  final Color color;
  _WheatIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = s.width * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = s.width / 2;

    // Stalk
    canvas.drawLine(Offset(cx, s.height * 0.90), Offset(cx, s.height * 0.08), strokePaint);

    // Grain pairs
    void grain(double y, double sign) {
      final path = Path()
        ..moveTo(cx, y)
        ..quadraticBezierTo(cx + sign * s.width * 0.32, y - s.height * 0.03, cx + sign * s.width * 0.30, y - s.height * 0.13)
        ..quadraticBezierTo(cx + sign * s.width * 0.08, y - s.height * 0.10, cx, y);
      canvas.drawPath(path, fillPaint);
    }

    for (final row in [s.height * 0.26, s.height * 0.42, s.height * 0.58]) {
      grain(row, -1);
      grain(row, 1);
    }

    // Base leaf
    final leaf = Path()
      ..moveTo(cx, s.height * 0.74)
      ..quadraticBezierTo(cx - s.width * 0.28, s.height * 0.62, cx - s.width * 0.22, s.height * 0.50)
      ..quadraticBezierTo(cx - s.width * 0.06, s.height * 0.63, cx, s.height * 0.74);
    canvas.drawPath(leaf, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Premium Input Field
// ─────────────────────────────────────────────────────────────────────────────
class AgriInputField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const AgriInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  State<AgriInputField> createState() => _AgriInputFieldState();
}

class _AgriInputFieldState extends State<AgriInputField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: _focused ? AgriColors.canopy : AgriColors.inkMid,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
          child: Text(widget.label.toUpperCase()),
        ),
        const SizedBox(height: 7),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _focused ? AgriColors.cardWhite : AgriColors.surface,
            borderRadius: BorderRadius.circular(AgriRadius.md),
            border: Border.all(
              color: _focused ? AgriColors.canopy : AgriColors.borderGhost,
              width: _focused ? 1.8 : 1.2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AgriColors.canopy.withOpacity(0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            validator: widget.validator,
            textInputAction: widget.textInputAction ?? TextInputAction.next,
            style: const TextStyle(
              color: AgriColors.inkDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: AgriColors.inkLight.withOpacity(0.7),
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
              prefixIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.icon,
                  key: ValueKey(_focused),
                  color: _focused ? AgriColors.canopy : AgriColors.inkLight,
                  size: 19,
                ),
              ),
              suffixIcon: widget.suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              errorStyle: const TextStyle(
                color: AgriColors.error,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Primary Button
// ─────────────────────────────────────────────────────────────────────────────
class AgriPrimaryButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final IconData? icon;

  const AgriPrimaryButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.label,
    this.icon,
  });

  @override
  State<AgriPrimaryButton> createState() => _AgriPrimaryButtonState();
}

class _AgriPrimaryButtonState extends State<AgriPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        height: 58,
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.onPressed == null
                ? [AgriColors.softGreen.withOpacity(0.5), AgriColors.softGreen.withOpacity(0.5)]
                : [AgriColors.canopy, AgriColors.deepForest],
          ),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          boxShadow: widget.onPressed == null ? [] : AgriShadow.button,
        ),
        child: Center(
          child: widget.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: Colors.white, size: 19),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Section Label
// ─────────────────────────────────────────────────────────────────────────────
class AgriSectionLabel extends StatelessWidget {
  final String text;
  const AgriSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AgriColors.leaf,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AgriColors.inkMid,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Branded SnackBar helper
// ─────────────────────────────────────────────────────────────────────────────
void showAgriSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? AgriColors.error : AgriColors.canopy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.sm),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 3),
    ),
  );
}
