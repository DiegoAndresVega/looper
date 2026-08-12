import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// The shape of a take, drawn as mirrored bars. It is there to recognise a
/// sound at a glance, not to edit it — trimming lives in the sound editor.
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    required this.color,
    this.height = 96,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
  });

  final Float32List peaks;
  final Color color;
  final double height;

  /// The kept region, 0..1. What falls outside is drawn faded: the sound is
  /// still there, it just will not be played.
  final double trimStart;
  final double trimEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(
          peaks: peaks,
          color: color,
          trimStart: trimStart,
          trimEnd: trimEnd,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.color,
    required this.trimStart,
    required this.trimEnd,
  });

  final Float32List peaks;
  final Color color;
  final double trimStart;
  final double trimEnd;

  static const double _barGap = 2;
  static const double _minBarHeight = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;

    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()..color = Palette.line,
    );

    if (peaks.isEmpty) return;

    final barWidth =
        ((size.width - _barGap * (peaks.length - 1)) / peaks.length)
            .clamp(1.0, size.width);
    final kept = Paint()..color = color;
    final dropped = Paint()..color = color.withValues(alpha: 0.2);

    for (var i = 0; i < peaks.length; i++) {
      final position = (i + 0.5) / peaks.length;
      final x = i * (barWidth + _barGap);
      final barHeight = (peaks[i] * middle).clamp(_minBarHeight, middle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, middle - barHeight, barWidth, barHeight * 2),
          const Radius.circular(1.5),
        ),
        position >= trimStart && position <= trimEnd ? kept : dropped,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks ||
      old.color != color ||
      old.trimStart != trimStart ||
      old.trimEnd != trimEnd;
}
