import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';

/// The sequencer's own controls, only on screen while SEQ is lit. Everything
/// about the pattern that is not a pad lives here: transport, the rest key,
/// wiping it and which of the sixteen patterns is loaded.
class SequencerBar extends StatelessWidget {
  const SequencerBar({
    super.key,
    required this.isPlaying,
    required this.isRecording,
    required this.currentStep,
    required this.editingStep,
    required this.patternIndex,
    required this.filledSteps,
    required this.chainLength,
    required this.onPlay,
    required this.onRecord,
    required this.onRest,
    required this.onClear,
    required this.onPattern,
    required this.onChain,
  });

  final bool isPlaying;
  final bool isRecording;
  final int currentStep;
  final int? editingStep;
  final int patternIndex;
  final int filledSteps;

  /// Bars in the chain: 1 loops one pattern, N plays P1..PN back to back.
  final int chainLength;

  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final VoidCallback onRest;
  final VoidCallback onClear;
  final ValueChanged<int> onPattern;
  final ValueChanged<int> onChain;

  /// The chain lengths a tap cycles through: the musical ones.
  static const List<int> _chainChoices = [1, 2, 4, 8, 16];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isRecording ? Palette.rec : Palette.line,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _patternPicker(),
              const SizedBox(width: 6),
              _chainPill(),
              const SizedBox(width: 10),
              Expanded(child: _status()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _button(
                  label: isPlaying ? 'Stop' : 'Play',
                  icon: isPlaying ? Icons.stop : Icons.play_arrow,
                  active: isPlaying,
                  onTap: onPlay,
                ),
              ),
              const SizedBox(width: 6),
              // REC and the laser dot mean one thing in this app: writing the
              // pattern. Nothing else wears them.
              Expanded(
                child: _button(
                  label: 'Rec',
                  icon: Icons.fiber_manual_record,
                  active: isRecording,
                  danger: true,
                  onTap: onRecord,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _button(
                  label: 'Silencio',
                  icon: Icons.skip_next,
                  active: false,
                  enabled: isRecording,
                  onTap: onRest,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _button(
                  label: 'Borrar',
                  icon: Icons.backspace_outlined,
                  active: false,
                  enabled: filledSteps > 0,
                  onTap: onClear,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Which of the sixteen patterns is loaded. Wraps around, because sixteen
  /// taps to get back is not a design.
  Widget _patternPicker() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(Icons.chevron_left,
            () => onPattern((patternIndex - 1) % kPatternCount)),
        SizedBox(
          width: 34,
          child: Text(
            'P${patternIndex + 1}',
            textAlign: TextAlign.center,
            style: Brand.readout(13, weight: 700),
          ),
        ),
        _arrow(Icons.chevron_right,
            () => onPattern((patternIndex + 1) % kPatternCount)),
      ],
    );
  }

  /// One tap moves to the next musical length: 1, 2, 4, 8, 16 bars and back
  /// to 1. Lit while a real chain is on.
  Widget _chainPill() {
    final active = chainLength > 1;
    return GestureDetector(
      onTap: () {
        final at = _chainChoices.indexOf(chainLength);
        final next =
            _chainChoices[(at + 1) % _chainChoices.length];
        onChain(next);
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? Palette.accent : Palette.line),
        ),
        child: Text(
          '$chainLength ${chainLength == 1 ? 'compás' : 'compases'}'
              .toUpperCase(),
          style: Brand.label(
            8,
            width: 75,
            tracking: 0.05,
            weight: 700,
            color: active ? Palette.onAccent : Palette.inkDim,
          ),
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.line),
        ),
        child: Icon(icon, size: 15, color: Palette.inkDim),
      ),
    );
  }

  Widget _status() {
    final String text;
    final Color color;
    if (editingStep != null) {
      text = 'Editando el paso ${editingStep! + 1} · toca pads para ponerlos';
      color = Palette.ink;
    } else if (isRecording) {
      text = 'Escribiendo el paso ${currentStep + 1} de $kPatternSteps';
      color = Palette.rec;
    } else if (isPlaying) {
      text = chainLength > 1
          ? 'P${patternIndex + 1} de $chainLength · paso ${currentStep + 1}'
          : 'Paso ${currentStep + 1} · $filledSteps con notas';
      color = Palette.accent;
    } else {
      text = filledSteps == 0
          ? 'Patrón vacío · mantén un pad para escribir en su paso'
          : '$filledSteps pasos con notas';
      color = Palette.inkDim;
    }

    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Brand.body(9.5, color: color, height: 1.32),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    bool enabled = true,
    bool danger = false,
  }) {
    final Color background;
    final Color foreground;
    if (active) {
      background = danger ? Palette.rec : Palette.accent;
      foreground = Palette.onAccent;
    } else {
      background = Colors.transparent;
      foreground = enabled ? Palette.inkDim : Palette.inkFaint;
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? (danger ? Palette.rec : Palette.accent)
                : Palette.line,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(height: 1),
            Text(
              label.toUpperCase(),
              style: Brand.label(6.5, width: 75, weight: 700, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
