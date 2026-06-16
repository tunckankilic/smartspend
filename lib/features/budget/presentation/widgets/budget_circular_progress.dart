import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_tone_color.dart';

/// Custom-painted circular progress indicator used by the general budget
/// card. `fl_chart`'s gauge widget would work too, but we want fine
/// control over the track color, stroke width, and overshoot rendering
/// (progress > 100 % wraps and paints in [BudgetTone.exceeded] red).
class BudgetCircularProgress extends StatelessWidget {
  const BudgetCircularProgress({
    required this.percentSpent,
    required this.tone,
    this.diameter = 180,
    this.strokeWidth = 14,
    this.child,
    super.key,
  });

  /// `0.0 - inf`. Values `> 1.0` paint a full ring in the exceeded tone.
  final double percentSpent;
  final BudgetTone tone;
  final double diameter;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        painter: _BudgetRingPainter(
          percent: percentSpent.clamp(0.0, 1.0),
          overflow: percentSpent > 1.0,
          strokeWidth: strokeWidth,
          progressColor: budgetToneColor(tone),
          trackColor: budgetToneColor(tone, dim: true),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _BudgetRingPainter extends CustomPainter {
  const _BudgetRingPainter({
    required this.percent,
    required this.overflow,
    required this.strokeWidth,
    required this.progressColor,
    required this.trackColor,
  });

  final double percent;
  final bool overflow;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;

    final Paint trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (percent <= 0 && !overflow) return;

    final Paint progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final double sweep = (overflow ? 1.0 : percent) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_BudgetRingPainter old) {
    return percent != old.percent ||
        overflow != old.overflow ||
        progressColor != old.progressColor ||
        trackColor != old.trackColor ||
        strokeWidth != old.strokeWidth;
  }
}
