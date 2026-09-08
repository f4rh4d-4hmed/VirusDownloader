import 'package:flutter/material.dart';
import '../../core/enums.dart';

/// Outlined vector icon for a Turtle (Tortoise) matching Material outline style.
class TurtleOutlinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const TurtleOutlinePainter({
    required this.color,
    this.strokeWidth = 1.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.scale(scale);

    // 1. Shell Outline (Dome)
    final shellPath = Path();
    shellPath.moveTo(5.0, 14.5);
    shellPath.cubicTo(4.8, 8.5, 8.5, 6.8, 11.5, 6.8);
    shellPath.cubicTo(14.5, 6.8, 17.2, 8.5, 17.0, 14.5);
    shellPath.close();
    canvas.drawPath(shellPath, strokePaint);

    // 2. Shell pattern lines (inner arched plates)
    final shellPattern = Path();
    shellPattern.moveTo(7.8, 14.5);
    shellPattern.cubicTo(7.8, 10.2, 14.2, 10.2, 14.2, 14.5);
    shellPattern.moveTo(11.5, 6.8);
    shellPattern.lineTo(11.5, 10.2);
    canvas.drawPath(shellPattern, strokePaint);

    // 3. Head & Snout (facing right)
    final headPath = Path();
    headPath.moveTo(17.0, 11.8);
    headPath.cubicTo(19.0, 10.5, 20.8, 10.5, 21.6, 12.0);
    headPath.cubicTo(22.2, 13.2, 21.4, 14.5, 19.8, 14.6);
    headPath.lineTo(17.0, 14.5);
    canvas.drawPath(headPath, strokePaint);

    // Eye dot
    canvas.drawCircle(const Offset(19.8, 12.3), 0.75, dotPaint);

    // 4. Front leg / flipper
    final frontLeg = Path();
    frontLeg.moveTo(14.5, 14.5);
    frontLeg.cubicTo(15.2, 16.5, 16.4, 17.5, 17.6, 17.5);
    frontLeg.cubicTo(16.5, 18.3, 14.5, 18.0, 13.0, 14.5);
    canvas.drawPath(frontLeg, strokePaint);

    // 5. Hind leg
    final backLeg = Path();
    backLeg.moveTo(7.5, 14.5);
    backLeg.cubicTo(6.8, 16.5, 5.6, 17.5, 4.4, 17.5);
    backLeg.cubicTo(5.5, 18.3, 7.5, 18.0, 9.0, 14.5);
    canvas.drawPath(backLeg, strokePaint);

    // 6. Tail
    final tailPath = Path();
    tailPath.moveTo(5.0, 13.2);
    tailPath.lineTo(2.8, 14.0);
    tailPath.lineTo(5.0, 14.5);
    canvas.drawPath(tailPath, strokePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TurtleOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// A widget that paints an outlined turtle icon.
class TurtleOutlineIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const TurtleOutlineIcon({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: TurtleOutlinePainter(
          color: effectiveColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

/// Outlined vector icon for a Rabbit / Hare matching Material outline style.
class RabbitOutlinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const RabbitOutlinePainter({
    required this.color,
    this.strokeWidth = 1.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.scale(scale);

    // Ears (long upright / backward leaning ears)
    final ears = Path();
    // Ear 1 (front)
    ears.moveTo(11.5, 10.0);
    ears.cubicTo(10.5, 6.0, 10.0, 3.2, 12.0, 2.5);
    ears.cubicTo(13.5, 2.5, 13.8, 5.5, 13.2, 10.0);
    // Ear 2 (behind)
    ears.moveTo(13.5, 8.5);
    ears.cubicTo(14.2, 5.0, 15.0, 3.5, 16.5, 4.0);
    ears.cubicTo(17.5, 4.8, 16.5, 7.5, 15.0, 10.2);
    canvas.drawPath(ears, strokePaint);

    // Head & face
    final head = Path();
    head.moveTo(11.5, 10.0);
    head.cubicTo(9.5, 10.5, 8.0, 11.8, 7.5, 13.2);
    head.cubicTo(7.2, 14.5, 8.5, 15.5, 10.5, 15.2);
    head.lineTo(13.2, 14.5);
    canvas.drawPath(head, strokePaint);

    // Eye dot
    canvas.drawCircle(const Offset(10.2, 12.8), 0.7, dotPaint);

    // Body & back
    final body = Path();
    body.moveTo(13.2, 14.0);
    body.cubicTo(15.5, 13.5, 18.5, 14.5, 19.5, 17.5);
    // Hind leg / paw
    body.cubicTo(20.0, 19.5, 17.5, 20.5, 14.5, 20.0);
    // Belly to front paw
    body.lineTo(10.5, 20.0);
    body.cubicTo(9.5, 20.0, 9.2, 18.5, 10.2, 17.5);
    body.lineTo(11.8, 15.5);
    canvas.drawPath(body, strokePaint);

    // Fluffy tail
    final tail = Path();
    tail.moveTo(19.2, 17.2);
    tail.cubicTo(21.2, 16.8, 22.0, 18.0, 21.5, 19.0);
    tail.cubicTo(21.0, 19.8, 19.8, 19.8, 19.0, 19.2);
    canvas.drawPath(tail, strokePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RabbitOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// A widget that paints an outlined rabbit icon.
class RabbitOutlineIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const RabbitOutlineIcon({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RabbitOutlinePainter(
          color: effectiveColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

/// Unified SpeedLimitIcon providing proper outlined icons for all SpeedLimitModes.
class SpeedLimitIcon extends StatelessWidget {
  final SpeedLimitMode mode;
  final double size;
  final Color? color;

  const SpeedLimitIcon({
    super.key,
    required this.mode,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;

    switch (mode) {
      case SpeedLimitMode.rabbit:
        return RabbitOutlineIcon(size: size, color: effectiveColor);
      case SpeedLimitMode.turtle:
        return TurtleOutlineIcon(size: size, color: effectiveColor);
      case SpeedLimitMode.unlimited:
        return Icon(
          Icons.all_inclusive_rounded,
          size: size,
          color: effectiveColor,
        );
      case SpeedLimitMode.rocket:
        return Icon(
          Icons.rocket_launch_outlined,
          size: size,
          color: effectiveColor,
        );
    }
  }

  /// Optional accent color for mode badges and visual highlights.
  static Color getAccentColor(SpeedLimitMode mode, ColorScheme scheme) {
    switch (mode) {
      case SpeedLimitMode.rabbit:
        return const Color(0xFFFB8C00); // Warm amber / orange
      case SpeedLimitMode.turtle:
        return const Color(0xFF26A69A); // Teal / emerald green
      case SpeedLimitMode.unlimited:
        return scheme.primary; // App primary
      case SpeedLimitMode.rocket:
        return const Color(0xFFE53935); // Vivid rocket red/crimson
    }
  }
}

