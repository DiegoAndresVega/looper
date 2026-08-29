import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';

/// Two parameters under one thumb.
///
/// It is the most expressive control a phone has — two axes at once, with no
/// menu and no second hand — and this instrument had never used it. It takes
/// the strip's row whole rather than sitting in a sheet, because a macro you
/// have to open something to reach is a macro you will not use while the
/// music is running.
///
/// Wide and short on purpose: the strip's height is the grid's height, and
/// the grid does not give any of it back.
class XyPad extends StatelessWidget {
  const XyPad({
    super.key,
    required this.x,
    required this.y,
    required this.xLabel,
    required this.yLabel,
    required this.xDisplay,
    required this.yDisplay,
    required this.onChanged,
  });

  /// Both 0..1, with y measured from the bottom the way a fader reads.
  final double x;
  final double y;

  final String xLabel;
  final String yLabel;
  final String xDisplay;
  final String yDisplay;

  final void Function(double x, double y) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void report(Offset local) {
          final nx = (local.dx / box.maxWidth).clamp(0.0, 1.0);
          final ny = 1 - (local.dy / box.maxHeight).clamp(0.0, 1.0);
          onChanged(nx, ny);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => report(d.localPosition),
          onPanUpdate: (d) => report(d.localPosition),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Palette.well,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Palette.line),
            ),
            child: CustomPaint(
              painter: _XyPainter(x: x, y: y),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$yLabel  $yDisplay'.toUpperCase(),
                      style: Brand.label(7.5, width: 75, color: Palette.inkFaint),
                    ),
                    Text(
                      '$xLabel  $xDisplay'.toUpperCase(),
                      style: Brand.label(7.5, width: 75, color: Palette.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The crosshair and its two guides. Lines rather than a dot alone: on a pad
/// this short, the guides are what say where the value sits on each axis.
class _XyPainter extends CustomPainter {
  const _XyPainter({required this.x, required this.y});

  final double x;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    final px = x * size.width;
    final py = (1 - y) * size.height;

    final guide = Paint()
      ..color = Palette.lineLive
      ..strokeWidth = 1;
    canvas.drawLine(Offset(px, 0), Offset(px, size.height), guide);
    canvas.drawLine(Offset(0, py), Offset(size.width, py), guide);

    canvas.drawCircle(
      Offset(px, py),
      7,
      Paint()..color = Palette.accent.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      Offset(px, py),
      4.5,
      Paint()..color = Palette.accent,
    );
  }

  @override
  bool shouldRepaint(_XyPainter old) => old.x != x || old.y != y;
}
