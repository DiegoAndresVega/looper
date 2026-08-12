import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../domain/pad_config.dart';
import '../../domain/sound.dart';

/// The six states a pad can be in. Read by colour and movement, never by text.
enum PadVisualState { empty, loaded, firing, looping, target, blocked }

/// The second light, in the corner opposite the sound dot. With the sequencer
/// on, the sixteen pads double as the sixteen steps: this is where the bar is
/// read, without taking a single pixel away from the grid.
enum StepLight {
  /// Sequencer off, or a step with nothing written on it.
  off,

  /// This step carries notes.
  written,

  /// The head is on this step right now.
  playing,

  /// This step is the one being written into by hand.
  editing,
}

/// One square of the grid. Everything it needs to say fits here: which sound,
/// which mode, whether it is sounding, and how far the loop has run.
class PadTile extends StatefulWidget {
  const PadTile({
    super.key,
    required this.pad,
    required this.sound,
    required this.state,
    required this.progress,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.stepLight = StepLight.off,
  });

  final PadConfig pad;
  final Sound? sound;
  final PadVisualState state;
  final StepLight stepLight;

  /// 0..1 around the border while looping.
  final double progress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<PadTile> createState() => _PadTileState();
}

class _PadTileState extends State<PadTile> {
  bool _pressed = false;

  Color get _familyColor =>
      widget.sound?.family.color ?? Palette.inkFaint;

  bool get _isEmpty => widget.state == PadVisualState.empty;

  double get _washOpacity {
    if (_isEmpty || widget.state == PadVisualState.blocked) return 0;
    if (_pressed || widget.state == PadVisualState.firing) return 0.60;
    if (widget.pad.muted) return 0.07;
    if (widget.state == PadVisualState.looping) return 0.32;
    return 0.14;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.state == PadVisualState.target
        ? Palette.accent
        : _familyColor;
    final looping = widget.state == PadVisualState.looping;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: BoxDecoration(
            color: Palette.panelHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _borderColor(color, looping),
              width: widget.selected || widget.state == PadVisualState.target ? 2 : 1,
            ),
          ),
          child: CustomPaint(
            painter: looping
                ? _LoopRingPainter(color: color, progress: widget.progress)
                : null,
            child: Stack(
              children: [
                if (!_isEmpty)
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: _washOpacity),
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                if (!_isEmpty) _modeDot(color, looping),
                if (widget.stepLight != StepLight.off) _stepDot(),
                _label(),
                if (widget.state == PadVisualState.blocked)
                  const Center(
                    child: Icon(Icons.lock_outline,
                        size: 18, color: Palette.inkFaint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _borderColor(Color color, bool looping) {
    if (widget.selected) return Palette.ink;
    if (widget.state == PadVisualState.target) return Palette.accent;
    if (looping) return color;
    return Palette.line;
  }

  Widget _modeDot(Color color, bool looping) {
    return Positioned(
      top: 9,
      left: 9,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color.withValues(alpha: looping ? 1.0 : 0.55),
          shape: BoxShape.circle,
          boxShadow: looping
              ? [BoxShadow(color: color.withValues(alpha: 0.32), spreadRadius: 3)]
              : null,
        ),
      ),
    );
  }

  /// The step light, top right. The head is a filled dot with a halo, a
  /// written step is a quiet one, and the step being edited wears a ring so it
  /// cannot be mistaken for the head.
  Widget _stepDot() {
    final playing = widget.stepLight == StepLight.playing;
    final editing = widget.stepLight == StepLight.editing;
    final color = editing ? Palette.ink : Palette.accent;

    return Positioned(
      top: 8,
      right: 8,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: playing ? 9 : 7,
        height: playing ? 9 : 7,
        decoration: BoxDecoration(
          color: editing
              ? Colors.transparent
              : color.withValues(alpha: playing ? 1.0 : 0.4),
          shape: BoxShape.circle,
          border: editing ? Border.all(color: color, width: 1.5) : null,
          boxShadow: playing
              ? [BoxShadow(color: color.withValues(alpha: 0.45), spreadRadius: 3.5)]
              : null,
        ),
      ),
    );
  }

  Widget _label() {
    final name = widget.sound?.name ?? 'Vacío';
    final bright = widget.state == PadVisualState.looping ||
        widget.state == PadVisualState.firing ||
        _pressed;
    return Positioned(
      left: 8,
      right: 6,
      bottom: 8,
      child: Text(
        name.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8.5,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: _isEmpty
              ? Palette.inkFaint.withValues(alpha: 0.6)
              : (bright ? Palette.ink : Palette.inkDim),
        ),
      ),
    );
  }
}

/// Draws the loop progress as a ring hugging the pad's border. The ring is
/// both the "this is looping" signal and the position indicator.
class _LoopRingPainter extends CustomPainter {
  const _LoopRingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(11));

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.22);
    canvas.drawRRect(rrect, track);

    if (progress <= 0) return;

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length * progress.clamp(0.0, 1.0);

    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawPath(metric.extractPath(0, length), bar);
  }

  @override
  bool shouldRepaint(_LoopRingPainter old) =>
      old.progress != progress || old.color != color;
}
