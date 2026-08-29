import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';

/// The lengths the chain pill walks through, and where a tap lands next.
///
/// The song joins the ring as one more position rather than getting a switch
/// of its own: the chain and the song answer the same question — what plays
/// after this bar — and two controls for one question can disagree.
const List<int> kChainChoices = [1, 2, 4, 8, 16];

/// Where one tap on the chain pill leaves things: a chain of [bars], or the
/// song taking over. A song that has not been written is not offered, so the
/// ring never lands on a running order that does not exist.
({int bars, bool song}) nextChainStop({
  required int chainLength,
  required bool songMode,
  required bool hasSong,
}) {
  // Coming out of the song, the ring starts over rather than carrying on
  // from where it was: one bar is the position everyone knows.
  if (songMode) return (bars: kChainChoices.first, song: false);

  final at = kChainChoices.indexOf(chainLength);
  if (at == kChainChoices.length - 1 && hasSong) {
    return (bars: chainLength, song: true);
  }
  return (bars: kChainChoices[(at + 1) % kChainChoices.length], song: false);
}

/// The four things a selected step can say about itself. One slider serves
/// them all — tapping its label cycles through — so editing a step never
/// costs the screen more than one row.
enum _StepParam { accent, probability, nudge, ratchet }

/// The sequencer's own controls, only on screen while SEQ is lit. Everything
/// about the pattern that is not a pad lives here: transport, the rest key,
/// wiping it and which of the sixteen patterns is loaded.
class SequencerBar extends StatefulWidget {
  const SequencerBar({
    super.key,
    required this.isPlaying,
    required this.isRecording,
    required this.currentStep,
    required this.editingStep,
    required this.patternIndex,
    required this.filledSteps,
    required this.chainLength,
    required this.songMode,
    required this.songBars,
    required this.songBar,
    required this.onSongMode,
    required this.onOpenSong,
    required this.swing,
    required this.editingVelocity,
    required this.editingProbability,
    required this.editingNudge,
    required this.editingRatchet,
    required this.isCountingIn,
    required this.countInBeat,
    required this.onSwing,
    required this.onVelocity,
    required this.onProbability,
    required this.onNudge,
    required this.onRatchet,
    required this.onCopyPattern,
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

  /// The song: whether it is the one in charge, how long it is, and which of
  /// its bars is sounding. Zero bars means nothing has been written yet, and
  /// then the chain pill never offers it.
  final bool songMode;
  final int songBars;
  final int songBar;

  final ValueChanged<bool> onSongMode;

  /// A long press on the chain pill opens the running order. It is the same
  /// gesture the pattern label already uses to lift a pattern: hold the thing
  /// you want to work on.
  final VoidCallback onOpenSong;

  /// How much the off-beat sixteenths lag, 0.5..0.75.
  final double swing;

  /// How hard the step being edited hits, 0..1.
  final double editingVelocity;

  /// The other three layers of the step being edited.
  final double editingProbability;
  final double editingNudge;
  final int editingRatchet;

  /// True during the courtesy bar between pressing REC and writing starting.
  final bool isCountingIn;
  final int countInBeat;

  final ValueChanged<double> onSwing;
  final ValueChanged<double> onVelocity;
  final ValueChanged<double> onProbability;
  final ValueChanged<double> onNudge;
  final ValueChanged<int> onRatchet;

  /// A long press on the pattern label lifts the pattern; where it lands is
  /// the screen's business.
  final VoidCallback onCopyPattern;

  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final VoidCallback onRest;
  final VoidCallback onClear;
  final ValueChanged<int> onPattern;
  final ValueChanged<int> onChain;

  @override
  State<SequencerBar> createState() => _SequencerBarState();
}

class _SequencerBarState extends State<SequencerBar> {
  _StepParam _param = _StepParam.accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: widget.isRecording || widget.isCountingIn ? Palette.rec : Palette.line,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _patternPicker(),
              const SizedBox(width: 5),
              _chainPill(),
              const SizedBox(width: 5),
              _swingPill(),
              const SizedBox(width: 8),
              // The step slider takes the status line's place while a step
              // is selected: the screen never grows, and what is under the
              // thumb is what is being used. Tapping its label walks through
              // the four layers of the step.
              Expanded(
                child: widget.editingStep == null ? _status() : _stepSlider(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _button(
                  label: widget.isPlaying ? 'Stop' : 'Play',
                  icon: widget.isPlaying ? Icons.stop : Icons.play_arrow,
                  active: widget.isPlaying,
                  onTap: widget.onPlay,
                ),
              ),
              const SizedBox(width: 6),
              // REC and the laser dot mean one thing in this app: writing the
              // pattern. Nothing else wears them.
              Expanded(
                child: _button(
                  label: widget.isCountingIn ? '${widget.countInBeat}…' : 'Rec',
                  icon: Icons.fiber_manual_record,
                  active: widget.isRecording || widget.isCountingIn,
                  danger: true,
                  onTap: widget.onRecord,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _button(
                  label: 'Silencio',
                  icon: Icons.skip_next,
                  active: false,
                  enabled: widget.isRecording,
                  onTap: widget.onRest,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _button(
                  label: 'Borrar',
                  icon: Icons.backspace_outlined,
                  active: false,
                  enabled: widget.filledSteps > 0,
                  onTap: widget.onClear,
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
            () => widget.onPattern((widget.patternIndex - 1) % kPatternCount)),
        GestureDetector(
          onLongPress: widget.onCopyPattern,
          child: SizedBox(
            width: 34,
            child: Text(
              'P${widget.patternIndex + 1}',
              textAlign: TextAlign.center,
              style: Brand.readout(13, weight: 700),
            ),
          ),
        ),
        _arrow(Icons.chevron_right,
            () => widget.onPattern((widget.patternIndex + 1) % kPatternCount)),
      ],
    );
  }

  /// One tap moves to the next musical length: 1, 2, 4, 8, 16 bars and back
  /// to 1. Once a song is written it joins the ring as one more position, so
  /// the chain and the song are the same choice rather than two switches that
  /// can disagree. Holding the pill opens the song itself.
  Widget _chainPill() {
    final hasSong = widget.songBars > 0;
    final active = widget.songMode || widget.chainLength > 1;
    final label = widget.songMode
        ? 'Canción ${widget.songBars}'
        : '${widget.chainLength} ${widget.chainLength == 1 ? 'compás' : 'compases'}';

    return GestureDetector(
      onTap: () {
        final next = nextChainStop(
          chainLength: widget.chainLength,
          songMode: widget.songMode,
          hasSong: hasSong,
        );
        if (next.song) {
          widget.onSongMode(true);
          return;
        }
        if (widget.songMode) widget.onSongMode(false);
        if (next.bars != widget.chainLength) widget.onChain(next.bars);
      },
      onLongPress: widget.onOpenSong,
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
          label.toUpperCase(),
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

  /// Swing as three named feels rather than a number: straight, a light
  /// shuffle, and the triplet. A player picking a groove is choosing between
  /// those three, not between 0.58 and 0.59.
  Widget _swingPill() {
    final at = _nearestSwing();
    final active = kSwingMarks[at] > kSwingMin;
    const names = ['Recto', 'Suave', 'Tresillo'];

    return GestureDetector(
      onTap: () => widget.onSwing(kSwingMarks[(at + 1) % kSwingMarks.length]),
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
          names[at].toUpperCase(),
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

  /// Which named feel the session's swing is sitting on. It is stored as a
  /// number, so it is matched rather than looked up.
  int _nearestSwing() {
    var best = 0;
    for (var i = 1; i < kSwingMarks.length; i++) {
      if ((kSwingMarks[i] - widget.swing).abs() < (kSwingMarks[best] - widget.swing).abs()) {
        best = i;
      }
    }
    return best;
  }

  /// One slider, four meanings: acento, probabilidad, micro y ratchet.
  /// Tapping the label cycles through them, so a step's whole voice fits in
  /// the row the status line already occupied.
  Widget _stepSlider() {
    final (label, display, value, min, max, divisions, onChanged) =
        switch (_param) {
      _StepParam.accent => (
          'ACENTO',
          '${(widget.editingVelocity * 100).round()}',
          widget.editingVelocity.clamp(kVelocityMin, kVelocityMax),
          kVelocityMin,
          kVelocityMax,
          null,
          widget.onVelocity,
        ),
      _StepParam.probability => (
          'PROB',
          '${(widget.editingProbability * 100).round()}%',
          widget.editingProbability.clamp(kProbabilityMin, 1.0),
          kProbabilityMin,
          1.0,
          null,
          widget.onProbability,
        ),
      _StepParam.nudge => (
          'MICRO',
          _nudgeDisplay(widget.editingNudge),
          widget.editingNudge.clamp(-kNudgeMax, kNudgeMax),
          -kNudgeMax,
          kNudgeMax,
          // Snapped to 5 % of a step, so «a tiempo» is reachable by feel.
          20,
          widget.onNudge,
        ),
      _StepParam.ratchet => (
          'RATCHET',
          '×${widget.editingRatchet}',
          widget.editingRatchet.toDouble(),
          1.0,
          kRatchetMax.toDouble(),
          kRatchetMax - 1,
          (double v) => widget.onRatchet(v.round()),
        ),
    };

    return Row(
      children: [
        // The step number plus which layer this slider is set to. Tapping it
        // moves to the next layer.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            final all = _StepParam.values;
            _param = all[(all.indexOf(_param) + 1) % all.length];
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'P${(widget.editingStep ?? 0) + 1} · $label ▸',
              style:
                  Brand.label(7.5, width: 75, weight: 700, color: Palette.ink),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: Palette.accent,
              inactiveTrackColor: Palette.lineLive,
              thumbColor: Palette.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: Brand.readout(10, weight: 700, color: Palette.accent),
          ),
        ),
      ],
    );
  }

  /// Early is a minus, late a plus, and zero reads as the machine it is.
  String _nudgeDisplay(double nudge) {
    final pct = (nudge * 100).round();
    if (pct == 0) return '0';
    return pct > 0 ? '+$pct' : '$pct';
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
    if (widget.isCountingIn) {
      text = 'Preparado… entra en ${widget.countInBeat} de $kStepsPerBeat';
      color = Palette.rec;
    } else if (widget.editingStep != null) {
      text = 'Editando el paso ${widget.editingStep! + 1} · toca pads para ponerlos';
      color = Palette.ink;
    } else if (widget.isRecording) {
      text = 'Escribiendo el paso ${widget.currentStep + 1} de $kPatternSteps';
      color = Palette.rec;
    } else if (widget.isPlaying && widget.songMode && widget.songBars > 0) {
      text = 'P${widget.patternIndex + 1} · compás '
          '${widget.songBar % widget.songBars + 1} de ${widget.songBars}';
      color = Palette.accent;
    } else if (widget.isPlaying) {
      text = widget.chainLength > 1
          ? 'P${widget.patternIndex + 1} de ${widget.chainLength} · paso ${widget.currentStep + 1}'
          : 'Paso ${widget.currentStep + 1} · ${widget.filledSteps} con notas';
      color = Palette.accent;
    } else {
      text = widget.filledSteps == 0
          ? 'Patrón vacío · mantén un pad para escribir en su paso'
          : '${widget.filledSteps} pasos con notas';
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
