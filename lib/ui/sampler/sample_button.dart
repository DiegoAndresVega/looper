import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// The one big button of the recording screen: tap to start, tap to stop.
/// While a take runs it wears two rings — the input level breathing on the
/// outside, and how much of the ten seconds is gone on the inside.
class SampleButton extends StatelessWidget {
  const SampleButton({
    super.key,
    required this.isRecording,
    required this.level,
    required this.progress,
    required this.onTap,
    this.size = 168,
  });

  final bool isRecording;

  /// Input level, 0..1.
  final double level;

  /// Share of the maximum take length already used, 0..1.
  final double progress;

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingsPainter(
            isRecording: isRecording,
            level: level,
            progress: progress,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: isRecording ? size * 0.3 : size * 0.46,
              height: isRecording ? size * 0.3 : size * 0.46,
              decoration: BoxDecoration(
                color: Palette.rec,
                borderRadius: BorderRadius.circular(
                  isRecording ? size * 0.06 : size,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({
    required this.isRecording,
    required this.level,
    required this.progress,
  });

  final bool isRecording;
  final double level;
  final double progress;

  static const double _ringWidth = 3;
  static const double _levelBand = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2 - _ringWidth;
    final inner = outer - _levelBand;

    canvas.drawCircle(
      center,
      inner,
      Paint()
        ..color = Palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth,
    );

    if (!isRecording) return;

    // Level: a soft halo that grows with what the microphone hears.
    canvas.drawCircle(
      center,
      inner + _levelBand * level.clamp(0.0, 1.0),
      Paint()
        ..color = Palette.rec.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth * 2,
    );

    // Countdown: a solid arc closing on the ten second ceiling.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: inner),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = Palette.rec
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _ringWidth,
    );
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.isRecording != isRecording ||
      old.level != level ||
      old.progress != progress;
}
