import 'dart:math';
import 'package:flutter/material.dart';

/// Animated avatar widget that changes pose based on guardian status.
/// Poses: idle (gentle sway), walking (limb swing), fall (tilted/spread),
///        impact (squish + shake), freeFall (arms-up float).
class AvatarWidget extends StatefulWidget {
  final String status;
  final bool fallDetected;
  final Color color;

  const AvatarWidget({
    super.key,
    required this.status,
    required this.fallDetected,
    required this.color,
  });

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget>
    with TickerProviderStateMixin {
  late AnimationController _loopCtrl;
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
  }

  @override
  void didUpdateWidget(AvatarWidget old) {
    super.didUpdateWidget(old);
    // Trigger shake when impact detected
    if (widget.status == 'Impact' && old.status != 'Impact') {
      _shakeCtrl.repeat(reverse: true);
    } else if (widget.status != 'Impact') {
      _shakeCtrl.stop();
      _shakeCtrl.reset();
    }

    // Speed up loop for walking
    if (widget.status == 'Walking') {
      _loopCtrl.duration = const Duration(milliseconds: 450);
    } else if (widget.status == 'Free Fall') {
      _loopCtrl.duration = const Duration(milliseconds: 1200);
    } else {
      _loopCtrl.duration = const Duration(milliseconds: 900);
    }
  }

  @override
  void dispose() {
    _loopCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loopCtrl, _shakeCtrl]),
      builder: (context, _) {
        final t = _loopCtrl.value; // 0.0 → 1.0, bounced
        final shake = _shakeCtrl.isAnimating
            ? (_shakeCtrl.value - 0.5) * 8.0
            : 0.0;

        return CustomPaint(
          size: const Size(160, 200),
          painter: _AvatarPainter(
            status: widget.fallDetected ? 'Fall' : widget.status,
            color: widget.color,
            t: t,
            shake: shake,
          ),
        );
      },
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final String status;
  final Color color;
  final double t; // animation phase 0..1
  final double shake;

  _AvatarPainter({
    required this.status,
    required this.color,
    required this.t,
    required this.shake,
  });

  // ── Drawing primitives ──────────────────────────────────────────────────

  Paint _paint(Color c, {double width = 6, bool fill = false}) => Paint()
    ..color = c
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  void _drawHead(Canvas c, Offset center, double r, Paint p) {
    // 3D-ish sphere effect: filled circle + highlight
    c.drawCircle(center, r, _paint(color, fill: true));
    c.drawCircle(center, r, _paint(Colors.white.withAlpha(60), width: 2));
    // specular highlight
    final hiPaint = Paint()
      ..color = Colors.white.withAlpha(120)
      ..style = PaintingStyle.fill;
    c.drawCircle(center + Offset(-r * 0.3, -r * 0.3), r * 0.25, hiPaint);
  }

  void _drawBody(Canvas c, Offset top, Offset bottom, Paint p) {
    // Thick rounded body segment
    final path = Path();
    final dx = 10.0;
    path.moveTo(top.dx - dx, top.dy);
    path.lineTo(top.dx + dx, top.dy);
    path.lineTo(bottom.dx + dx * 0.6, bottom.dy);
    path.lineTo(bottom.dx - dx * 0.6, bottom.dy);
    path.close();
    c.drawPath(path, _paint(color, fill: true));
    c.drawPath(
      path,
      _paint(Colors.white.withAlpha(40), width: 1.5, fill: false),
    );
  }

  void _drawLimb(Canvas c, Offset start, Offset end, Paint p) {
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final ctrl = Offset(
      mid.dx + (end.dx - start.dx) * 0.15,
      mid.dy + (end.dy - start.dy) * 0.1,
    );
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    c.drawPath(path, p);
  }

  // ── Main paint ──────────────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + shake;
    final cy = size.height / 2;

    canvas.save();

    switch (status) {
      case 'Walking':
        _paintWalking(canvas, cx, cy);
        break;
      case 'Fall':
        _paintFall(canvas, cx, cy);
        break;
      case 'Impact':
        _paintImpact(canvas, cx, cy);
        break;
      case 'Free Fall':
        _paintFreeFall(canvas, cx, cy);
        break;
      default: // Idle / Connecting
        _paintIdle(canvas, cx, cy);
    }

    canvas.restore();
  }

  // ── IDLE: gentle vertical sway ──────────────────────────────────────────
  void _paintIdle(Canvas canvas, double cx, double cy) {
    final bob = sin(t * pi) * 4;
    final bodyTop = Offset(cx, cy - 30 + bob);
    final bodyBot = Offset(cx, cy + 20 + bob);
    final head = Offset(cx, cy - 55 + bob);

    final p = _paint(color, width: 7);
    _drawHead(canvas, head, 22, p);
    _drawBody(canvas, bodyTop, bodyBot, p);
    // Arms hanging
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + Offset(-36, 30),
      p,
    );
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + Offset(36, 30),
      p,
    );
    // Legs straight
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(-18, 50), p);
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(18, 50), p);
    // Ground shadow
    _drawShadow(canvas, cx, bodyBot.dy + 54);
  }

  // ── WALKING: arm+leg swing ──────────────────────────────────────────────
  void _paintWalking(Canvas canvas, double cx, double cy) {
    final phase = sin(t * pi * 2);
    final bodyTop = Offset(cx, cy - 28);
    final bodyBot = Offset(cx, cy + 20);
    final head = Offset(cx, cy - 55);

    final p = _paint(color, width: 7);
    _drawHead(canvas, head, 22, p);
    _drawBody(canvas, bodyTop, bodyBot, p);
    // Arms swing opposite to legs
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + Offset(-30 + phase * 18, 38),
      p,
    );
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + Offset(30 - phase * 18, 38),
      p,
    );
    // Legs swing
    _drawLimb(
      canvas,
      bodyBot,
      bodyBot + Offset(-18 - phase * 22, 40 + phase.abs() * 8),
      p,
    );
    _drawLimb(
      canvas,
      bodyBot,
      bodyBot + Offset(18 + phase * 22, 40 - phase.abs() * 8),
      p,
    );
    _drawShadow(canvas, cx, bodyBot.dy + 52);
  }

  // ── FALL: body rotated ~70°, limbs spread ──────────────────────────────
  void _paintFall(Canvas canvas, double cx, double cy) {
    canvas.translate(cx, cy);
    canvas.rotate(1.2 + sin(t * pi) * 0.15); // ~70° tilted
    canvas.translate(-cx, -cy);

    final bodyTop = Offset(cx, cy - 30);
    final bodyBot = Offset(cx, cy + 20);
    final head = Offset(cx, cy - 55);

    final p = _paint(Colors.red, width: 7);
    _drawHead(canvas, head, 22, p);
    _drawBody(canvas, bodyTop, bodyBot, p);
    // Arms flung wide
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(-50, 10),
      p,
    );
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(50, 10),
      p,
    );
    // Legs spread
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(-30, 40), p);
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(30, 40), p);
  }

  // ── IMPACT: squished body + shaking ────────────────────────────────────
  void _paintImpact(Canvas canvas, double cx, double cy) {
    final squish = 0.75 + sin(t * pi) * 0.1;
    canvas.translate(cx, cy);
    canvas.scale(1.0, squish);
    canvas.translate(-cx, -cy);

    final bodyTop = Offset(cx, cy - 20);
    final bodyBot = Offset(cx, cy + 20);
    final head = Offset(cx, cy - 48);

    final p = _paint(Colors.orange, width: 8);
    _drawHead(canvas, head, 22, p);
    _drawBody(canvas, bodyTop, bodyBot, p);
    // Arms bracing
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(-40, 20),
      p,
    );
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(40, 20),
      p,
    );
    // Bent legs
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(-25, 35), p);
    _drawLimb(canvas, bodyBot, bodyBot + const Offset(25, 35), p);
    _drawShadow(canvas, cx, bodyBot.dy + 38);
  }

  // ── FREE FALL: arms raised, floating bounce ─────────────────────────────
  void _paintFreeFall(Canvas canvas, double cx, double cy) {
    final float = sin(t * pi) * 10;
    final bodyTop = Offset(cx, cy - 30 - float);
    final bodyBot = Offset(cx, cy + 20 - float);
    final head = Offset(cx, cy - 55 - float);

    final p = _paint(Colors.deepOrange, width: 7);
    _drawHead(canvas, head, 22, p);
    _drawBody(canvas, bodyTop, bodyBot, p);
    // Arms raised up
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(-38, -20),
      p,
    );
    _drawLimb(
      canvas,
      bodyTop + const Offset(0, 10),
      bodyTop + const Offset(38, -20),
      p,
    );
    // Legs dangling
    _drawLimb(canvas, bodyBot, bodyBot + Offset(-18, 45 + float * 0.3), p);
    _drawLimb(canvas, bodyBot, bodyBot + Offset(18, 45 + float * 0.3), p);
    // Faded shadow far below
    _drawShadow(canvas, cx, cy + 90, opacity: 0.15);
  }

  void _drawShadow(
    Canvas canvas,
    double cx,
    double y, {
    double opacity = 0.12,
  }) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, y), width: 60, height: 10),
      Paint()..color = Colors.black.withAlpha((opacity * 255).toInt()),
    );
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.t != t ||
      old.status != status ||
      old.shake != shake ||
      old.color != color;
}
