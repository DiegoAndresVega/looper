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
  });

  final Float32List peaks;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _WaveformPainter(peaks: peaks, color: color)),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.peaks, required this.color});

  final Float32List peaks;
  final Color color;

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
    final paint = Paint()..color = color;

    for (var i = 0; i < peaks.length; i++) {
      final x = i * (barWidth + _barGap);
      final barHeight =
          (peaks[i] * middle).clamp(_minBarHeight, middle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, middle - barHeight, barWidth, barHeight * 2),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks || old.color != color;
}
