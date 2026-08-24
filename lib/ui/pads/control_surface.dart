import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/midi_target.dart';
import '../../state/midi_learn.dart';

/// Which set of four knobs the surface is showing.
enum SurfaceTab { sound, fx, loop, scale }

/// One knob's live value and label.
class KnobSpec {
  const KnobSpec({
    required this.label,
    required this.display,
    required this.value,
    required this.onChanged,
    this.accent = false,
    this.target,
  });

  final String label;
  final String display;

  /// 0..1
  final double value;
  final ValueChanged<double>? onChanged;
  final bool accent;

  /// What a physical control would be moving if it learned this knob, or null
  /// for the one knob that is not a parameter: the switch that points the FX
  /// row at the master or at a bus. A controller that changes the view is a
  /// controller you have to look at.
  final MidiTarget? target;
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
    required this.learn,
  });

  final String targetLabel;
  final Color targetColor;
  final SurfaceTab tab;
  final List<KnobSpec> knobs;
  final ValueChanged<SurfaceTab> onTabChanged;

  /// Which control of the desk moves what. The strip owns this gesture because
  /// the strip is where the knobs are: holding one down is the whole setup.
  final MidiLearn learn;

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
          // While a knob is waiting for a control, the row says so instead of
          // saying what is selected — and the tabs go away with it, because
          // changing tab now would be changing what you are about to marry.
          learn.armed == null ? _targetRow() : _learningRow(learn.armed!),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < knobs.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: i == knobs.length - 1 ? 0 : 6),
                    child: _Knob(spec: knobs[i], learn: learn),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetRow() {
    return Row(
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
            style: Brand.label(
              9,
              width: 75,
              weight: 700,
              tracking: 0.1,
              color: Palette.ink,
            ),
          ),
        ),
        for (final t in SurfaceTab.values) _tabChip(t),
      ],
    );
  }

  Widget _learningRow(MidiTarget armed) {
    final bound = learn.controllerFor(armed);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Palette.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'MUEVE UN MANDO DEL CONTROLADOR',
            overflow: TextOverflow.ellipsis,
            style: Brand.label(
              9,
              width: 75,
              weight: 700,
              tracking: 0.1,
              color: Palette.accent,
            ),
          ),
        ),
        if (bound != null)
          _chip('OLVIDAR CC$bound', onTap: () => learn.forget(armed)),
        _chip('CANCELAR', onTap: learn.cancel),
      ],
    );
  }

  Widget _chip(String text, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Palette.lineLive),
          ),
          child: Text(
            text,
            style: Brand.label(7.5, width: 75, weight: 700, color: Palette.ink),
          ),
        ),
      ),
    );
  }

  Widget _tabChip(SurfaceTab t) {
    const names = {
      SurfaceTab.sound: 'Sonido',
      SurfaceTab.fx: 'FX',
      SurfaceTab.loop: 'Loop',
      SurfaceTab.scale: 'Escala',
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
            style: Brand.label(
              7.5,
              width: 75,
              weight: on ? 700 : 600,
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
///
/// Holding it down is how it gets married to a control on the desk: the same
/// long press that opens a pad's insides opens a knob's. Learning is the only
/// thing the long press does here, so nothing else has to move out of the way.
class _Knob extends StatelessWidget {
  const _Knob({required this.spec, required this.learn});

  final KnobSpec spec;
  final MidiLearn learn;

  @override
  Widget build(BuildContext context) {
    final enabled = spec.onChanged != null;
    final target = spec.target;
    final armed = target != null && learn.isArmed(target);
    final controller = target == null ? null : learn.controllerFor(target);

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
      onLongPress: target == null || !enabled
          ? null
          : () => armed ? learn.cancel() : learn.arm(target),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(38),
                  painter: _KnobPainter(
                    value: spec.value,
                    color: armed
                        ? Palette.accent
                        : enabled
                            ? (spec.accent ? Palette.accent : Palette.inkDim)
                            : Palette.inkFaint,
                  ),
                ),
                // The control number lives inside the dial, where the hole
                // already is: a knob that answers to the desk says which key
                // it answers to without costing a row of screen.
                if (controller != null)
                  Text(
                    '$controller',
                    style: Brand.readout(
                      8,
                      weight: 700,
                      color: armed ? Palette.accent : Palette.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Brand.label(
              7,
              width: 75,
              color: armed ? Palette.accent : Palette.inkFaint,
            ),
          ),
          Text(
            armed ? 'MUEVE' : spec.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Brand.readout(
              9,
              weight: 600,
              color: armed
                  ? Palette.accent
                  : enabled
                      ? Palette.ink
                      : Palette.inkFaint,
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
