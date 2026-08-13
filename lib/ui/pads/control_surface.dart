import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// Which set of four knobs the surface is showing.
enum SurfaceTab { sound, fx, loop }

/// One knob's live value and label.
class KnobSpec {
  const KnobSpec({
    required this.label,
    required this.display,
    required this.value,
    required this.onChanged,
    this.accent = false,
  });

  final String label;
  final String display;

  /// 0..1
  final double value;
  final ValueChanged<double>? onChanged;
  final bool accent;
}

/// The strip that lives under the grid and never goes away. If it is something
/// you touch while the music runs, it is here — not behind a sheet.
class ControlSurface extends StatelessWidget {
  const ControlSurface({
    super.key,
    required this.targetLabel,
    required this.targetColor,
    required this.tab,
    required this.knobs,
    required this.onTabChanged,
  });

  final String targetLabel;
  final Color targetColor;
  final SurfaceTab tab;
  final List<KnobSpec> knobs;
  final ValueChanged<SurfaceTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: targetColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  targetLabel.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                    color: Palette.ink,
                  ),
                ),
              ),
              for (final t in SurfaceTab.values) _tabChip(t),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < knobs.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: i == knobs.length - 1 ? 0 : 6),
                    child: _Knob(spec: knobs[i]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabChip(SurfaceTab t) {
    const names = {
      SurfaceTab.sound: 'Sonido',
      SurfaceTab.fx: 'FX',
      SurfaceTab.loop: 'Loop',
    };
    final on = t == tab;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
        onTap: () => onTabChanged(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: on ? Palette.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? Palette.ink : Palette.line),
          ),
          child: Text(
            names[t]!.toUpperCase(),
            style: TextStyle(
              fontSize: 7.5,
              letterSpacing: 1.0,
              fontWeight: on ? FontWeight.w700 : FontWeight.w600,
              color: on ? Palette.ground : Palette.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

/// How far the thumb travels to take a knob from nothing to everything.
const double _fullThrowPixels = 120;

/// A knob you drag vertically. Big target, no fiddly arc dragging.
class _Knob extends StatelessWidget {
  const _Knob({required this.spec});

  final KnobSpec spec;

  @override
  Widget build(BuildContext context) {
    final enabled = spec.onChanged != null;
    return GestureDetector(
      // The whole column takes the drag, not just the 38 pixels of dial: a
      // thumb that lands beside the ring was doing nothing at all before.
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: enabled
          ? (details) {
              final next =
                  (spec.value - details.delta.dy / _fullThrowPixels)
                      .clamp(0.0, 1.0);
              spec.onChanged!(next);
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CustomPaint(
              painter: _KnobPainter(
                value: spec.value,
                color: enabled
                    ? (spec.accent ? Palette.accent : Palette.inkDim)
                    : Palette.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 7,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
              color: Palette.inkFaint,
            ),
          ),
          Text(
            spec.display,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: enabled ? Palette.ink : Palette.inkFaint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({required this.value, required this.color});

  final double value;
  final Color color;

  /// The dial sweeps 270 degrees, leaving a gap at the bottom like real gear.
  static const double _start = 2.356; // 135 degrees
  static const double _sweep = 4.712; // 270 degrees

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = Palette.line;
    canvas.drawArc(rect, _start, _sweep, false, track);

    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, _start, _sweep * value.clamp(0.0, 1.0), false, bar);
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.value != value || old.color != color;
}
