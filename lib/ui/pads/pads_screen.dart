import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../audio/fx_curves.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../data/factory_kit.dart';
import '../../domain/loop_length.dart';
import '../../domain/pad_config.dart';
import '../../state/session_controller.dart';
import 'bank_tabs.dart';
import 'control_surface.dart';
import 'pad_sheet.dart';
import 'pad_tile.dart';
import 'sequencer_bar.dart';
import 'tempo_stepper.dart';
import 'transport_bar.dart';

/// The root of the app. Banks, tempo, grid, control surface and transport —
/// everything a session needs, with no menu in the way.
class PadsScreen extends StatefulWidget {
  const PadsScreen({
    super.key,
    required this.controller,
    required this.onOpenSampler,
    required this.onOpenLibrary,
    required this.onOpenSessions,
  });

  final SessionController controller;
  final VoidCallback onOpenSampler;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSessions;

  @override
  State<PadsScreen> createState() => _PadsScreenState();
}

class _PadsScreenState extends State<PadsScreen> {
  SurfaceTab _tab = SurfaceTab.sound;
  Timer? _ringTicker;

  /// While armed, the next pad tapped opens its sheet instead of sounding.
  /// It is the only modal state in the instrument, it lasts one tap, and the
  /// grid says so out loud by lighting every pad as a target.
  bool _editArmed = false;

  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // The loop rings need a steady repaint; the controller only notifies on
    // real state changes, which is not often enough for a moving ring.
    _ringTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final moving =
          c.loops.isNotEmpty || c.mixdown.isRecording || c.sequencer.isPlaying;
      if (mounted && moving) setState(() {});
    });
  }

  @override
  void dispose() {
    _ringTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (c.session == null) {
      return const Scaffold(
        backgroundColor: Palette.ground,
        body: Center(child: CircularProgressIndicator(color: Palette.accent)),
      );
    }

    return Scaffold(
      backgroundColor: Palette.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 10),
              BankTabs(
                ids: kBankIds,
                labels: kBankLabels,
                activeIndex: c.activeBank,
                busyBanks: {
                  for (var i = 0; i < kBankCount; i++)
                    if (c.bankHasLoops(i)) i
                },
                onSelect: (i) => setState(() => c.selectBank(i)),
              ),
              const SizedBox(height: 10),
              TempoStepper(
                bpm: c.bpm,
                onChanged: (v) => setState(() => c.setBpm(v)),
              ),
              const SizedBox(height: 12),
              // The grid absorbs whatever height is left so no dead space is
              // wasted — on a tall phone the pads simply get taller.
              Expanded(child: _grid()),
              const SizedBox(height: 10),
              if (c.sequencer.isOn) ...[
                _sequencer(),
                const SizedBox(height: 8),
              ] else ...[
                _surface(),
                const SizedBox(height: 10),
              ],
              _transport(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: widget.onOpenSessions,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    c.session!.name,
                    overflow: TextOverflow.ellipsis,
                    style: Brand.title(17),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.expand_more, size: 15, color: Palette.inkFaint),
              ],
            ),
          ),
        ),
        if (c.mixdown.isRecording) ...[
          _mixdownBadge(),
          const SizedBox(width: 8),
        ],
        _iconButton(Icons.library_music_outlined, widget.onOpenLibrary),
        const SizedBox(width: 6),
        _iconButton(Icons.mic_none, widget.onOpenSampler),
      ],
    );
  }

  /// While a take runs, the only new thing on screen is this counter: the
  /// recording is signalled, never in the way.
  Widget _mixdownBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Palette.rec),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Palette.rec,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatElapsed(c.mixdown.elapsed),
            style: Brand.readout(10, weight: 700, color: Palette.rec),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Palette.line),
        ),
        child: Icon(icon, size: 16, color: Palette.inkDim),
      ),
    );
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      const rows = kPadsPerBank ~/ kGridColumns;
      final padWidth = (box.maxWidth - gap * (kGridColumns - 1)) / kGridColumns;
      final padHeight = (box.maxHeight - gap * (rows - 1)) / rows;
      return _buildGrid(padWidth / padHeight, gap);
    });
  }

  Widget _buildGrid(double aspectRatio, double gap) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kPadsPerBank,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kGridColumns,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, slot) {
        final pad = c.padAt(slot);
        final sound = c.soundFor(pad);
        return PadTile(
          pad: pad,
          sound: sound,
          state: _stateFor(slot, pad),
          stepLight: _stepLightFor(slot),
          progress: c.loopProgress(c.activeBank, slot),
          selected: c.selectedSlot == slot,
          onTap: () => _tapPad(slot),
          onLongPress: () => _holdPad(slot),
        );
      },
    );
  }

  /// A tap plays. Tapping in a rhythm plays that rhythm; on a pad that is
  /// looping it switches the loop off. With AJUSTAR armed it opens the sheet
  /// instead, which is the one place a tap does not make a sound.
  void _tapPad(int slot) {
    if (_editArmed) {
      setState(() => _editArmed = false);
      _openPadSheet(slot);
      return;
    }
    setState(() => c.tapPad(slot));
  }

  /// A long press leaves the pad looping, with a nudge so the finger knows it
  /// took without having to look.
  void _holdPad(int slot) {
    if (_editArmed) {
      setState(() => _editArmed = false);
      _openPadSheet(slot);
      return;
    }
    if (c.padAt(slot).isEmpty) {
      _openPadSheet(slot);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => c.holdPad(slot));
  }

  /// What sits on the pad and how it behaves. Edits land on the session as
  /// they are made, so closing the sheet is not a "save".
  Future<void> _openPadSheet(int slot) async {
    final bank = c.activeBank;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PadSheet(
        title: '${kBankIds[bank]} · ${(slot + 1).toString().padLeft(2, '0')}',
        pad: c.padAt(slot),
        sounds: c.librarySounds,
        onChanged: (pad) => c.updatePad(bank, slot, pad),
        onPreview: c.preview,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Pad number i is step number i. The corner light says what that step is
  /// doing, which turns the grid into the pattern display without adding a
  /// single row to the screen.
  StepLight _stepLightFor(int slot) {
    final seq = c.sequencer;
    if (!seq.isOn) return StepLight.off;
    if (seq.editingStep == slot) return StepLight.editing;
    if ((seq.isPlaying || seq.isRecording) && seq.currentStep == slot) {
      return StepLight.playing;
    }
    return seq.pattern.at(slot).isEmpty ? StepLight.off : StepLight.written;
  }

  PadVisualState _stateFor(int slot, PadConfig pad) {
    if (_editArmed) return PadVisualState.target;
    if (pad.isEmpty) return PadVisualState.empty;
    if (!c.isLooping(c.activeBank, slot)) return PadVisualState.loaded;
    return c.isQueued(c.activeBank, slot)
        ? PadVisualState.queued
        : PadVisualState.looping;
  }

  Widget _surface() {
    final slot = c.selectedSlot;
    final pad = slot == null ? null : c.padAt(slot);
    final sound = pad == null ? null : c.soundFor(pad);

    final label = sound == null
        ? 'Maestro'
        : '${kBankIds[c.activeBank]} · ${(slot! + 1).toString().padLeft(2, '0')} · ${sound.name}';

    return ControlSurface(
      targetLabel: label,
      // Phosphor for the master row: laser is reserved for writing the pattern.
      targetColor: sound?.family.color ?? Palette.accent,
      tab: _tab,
      onTabChanged: (t) => setState(() => _tab = t),
      knobs: _knobsFor(slot, pad),
    );
  }

  List<KnobSpec> _knobsFor(int? slot, PadConfig? pad) {
    // No pad picked: the surface points at the master output. Volume and the
    // performance effects — nothing fake, nothing greyed out.
    if (slot == null || pad == null || pad.isEmpty) {
      return [
        KnobSpec(
          label: 'Vol',
          display: (c.fx.volume * 100).round().toString(),
          value: c.fx.volume,
          accent: true,
          onChanged: (v) => setState(() => c.fx.volume = v),
        ),
        ..._fxKnobs(includeResonance: false),
      ];
    }

    switch (_tab) {
      case SurfaceTab.sound:
        return [
          KnobSpec(
            label: 'Vol',
            display: (pad.volume * 100).round().toString(),
            value: pad.volume,
            accent: true,
            onChanged: (v) => setState(() => c.setPadVolume(slot, v)),
          ),
          KnobSpec(
            label: 'Tono',
            display: pad.semitones > 0 ? '+${pad.semitones}' : '${pad.semitones}',
            value: (pad.semitones + 12) / 24,
            onChanged: (v) => setState(
                () => c.setPadSemitones(slot, (v * 24 - 12).round())),
          ),
          KnobSpec(
            label: 'Mute',
            display: pad.muted ? 'ON' : 'OFF',
            value: pad.muted ? 1 : 0,
            accent: pad.muted,
            onChanged: (v) {
              if ((v > 0.5) != pad.muted) setState(() => c.toggleMute(slot));
            },
          ),
          // Solo points at this pad, not at the session: with another pad
          // soloed this knob reads OFF, because this one is not the one
          // being heard.
          KnobSpec(
            label: 'Solo',
            display: c.isSoloOn(slot) ? 'ON' : 'OFF',
            value: c.isSoloOn(slot) ? 1 : 0,
            accent: c.isSoloOn(slot),
            onChanged: (v) {
              if ((v > 0.5) != c.isSoloOn(slot)) {
                setState(() => c.toggleSolo(slot));
              }
            },
          ),
        ];
      case SurfaceTab.fx:
        return _fxKnobs(includeResonance: true);
      case SurfaceTab.loop:
        final looping = c.isLooping(c.activeBank, slot);
        final choices = loopLengthChoices(pad.loopSteps);
        return [
          KnobSpec(
            label: 'Loop',
            display: looping ? 'ON' : 'OFF',
            value: looping ? 1 : 0,
            accent: looping,
            onChanged: (v) => setState(() => c.setPadLooping(slot, v > 0.5)),
          ),
          KnobSpec(
            label: 'Sync',
            display: pad.synced ? 'ON' : 'OFF',
            value: pad.synced ? 1 : 0,
            accent: pad.synced,
            onChanged: (v) => setState(() => c.setPadSynced(slot, v > 0.5)),
          ),
          KnobSpec(
            label: 'Tiempos',
            display: loopLengthLabel(pad.loopSteps),
            value: choices.indexOf(pad.loopSteps) / (choices.length - 1),
            onChanged: (v) => setState(() {
              final index =
                  (v * (choices.length - 1)).round().clamp(0, choices.length - 1);
              c.setPadLoopSteps(slot, choices[index]);
            }),
          ),
        ];
    }
  }

  /// The performance effects. They sit on the master output, so the same
  /// knobs appear whether a pad is selected or not — turning the filter
  /// while a loop runs is the point of them.
  List<KnobSpec> _fxKnobs({required bool includeResonance}) {
    final fx = c.fx;
    // The same threshold the effects bypass themselves at, so a knob reading
    // OFF is one that is genuinely out of the signal path.
    final filterOpen = fx.cutoff >= 1 - kFxEpsilon;
    return [
      KnobSpec(
        label: 'Filtro',
        display: filterOpen ? 'OFF' : (fx.cutoff * 100).round().toString(),
        value: fx.cutoff,
        accent: !filterOpen,
        onChanged: (v) => setState(() => fx.cutoff = v),
      ),
      if (includeResonance)
        KnobSpec(
          label: 'Reso',
          display: (fx.resonance * 100).round().toString(),
          value: fx.resonance,
          accent: fx.resonance > kFxEpsilon,
          onChanged: (v) => setState(() => fx.resonance = v),
        ),
      KnobSpec(
        label: 'Eco',
        display:
            fx.echo <= kFxEpsilon ? 'OFF' : (fx.echo * 100).round().toString(),
        value: fx.echo,
        accent: fx.echo > kFxEpsilon,
        onChanged: (v) => setState(() => fx.echo = v),
      ),
      KnobSpec(
        label: 'Drive',
        display:
            fx.drive <= kFxEpsilon ? 'OFF' : (fx.drive * 100).round().toString(),
        value: fx.drive,
        accent: fx.drive > kFxEpsilon,
        onChanged: (v) => setState(() => fx.drive = v),
      ),
    ];
  }

  /// The sequencer takes the control surface's place while it is on: the
  /// screen never grows, and what is under the thumb is what is being used.
  Widget _sequencer() {
    final seq = c.sequencer;
    return SequencerBar(
      isPlaying: seq.isPlaying,
      isRecording: seq.isRecording,
      currentStep: seq.currentStep,
      editingStep: seq.editingStep,
      patternIndex: seq.patternIndex,
      filledSteps: seq.pattern.filledSteps,
      chainLength: seq.chainLength,
      onPlay: () => setState(c.toggleSequencerPlay),
      onRecord: () => setState(c.toggleSequencerRecord),
      onRest: () => setState(seq.rest),
      onClear: () => setState(seq.clearPattern),
      onPattern: (index) => setState(() => c.selectPattern(index)),
      onChain: (bars) => setState(() => c.setChainLength(bars)),
    );
  }

  Widget _transport() {
    final slot = c.selectedSlot;
    final pad = slot == null ? null : c.padAt(slot);

    return TransportBar(
      actions: [
        TransportAction(
          icon: Icons.stop,
          label: 'Parar',
          onTap: () async {
            await c.stopAllLoops();
            if (mounted) setState(() {});
          },
        ),
        // Held, not tapped: while ROLL is down every pad you touch repeats at
        // its division, and touching another pad walks the fill across.
        //
        // AJUSTAR + tap changes that division instead of rolling, which is the
        // same bargain the grid already makes: armed, the next touch settles
        // the control rather than playing it.
        TransportAction(
          icon: Icons.repeat,
          label: 'Roll ${c.rollLabel}',
          active: c.isRolling,
          onTap: _editArmed
              ? () => setState(() {
                    c.cycleRollDivision();
                    _editArmed = false;
                  })
              : () {},
          onPressStart: _editArmed ? null : () => setState(c.startRoll),
          onPressEnd: _editArmed ? null : () => setState(c.stopRoll),
        ),
        TransportAction(
          icon: Icons.grid_view,
          label: 'Seq',
          active: c.sequencer.isOn,
          onTap: () => setState(c.toggleSequencer),
        ),
        TransportAction(
          icon: Icons.tune,
          label: 'Ajustar',
          active: _editArmed,
          onTap: () => setState(() => _editArmed = !_editArmed),
        ),
        TransportAction(
          icon: Icons.change_history,
          label: 'Metro',
          active: c.isMetronomeOn,
          onTap: () async {
            await c.toggleMetronome();
            if (mounted) setState(() {});
          },
        ),
        // One button, two gestures: tap silences the pad, holding it solos it.
        // With a solo up the caption says so — otherwise a solo left on in
        // another bank would read as an instrument that stopped working.
        TransportAction(
          icon: c.isSoloActive
              ? Icons.headphones_outlined
              : Icons.volume_off_outlined,
          label: c.isSoloActive ? 'Solo' : 'Mute',
          active: c.isSoloActive || (pad?.muted ?? false),
          // Lit and reading SOLO, a tap lifts it — including a solo left on a
          // pad in another bank, which is otherwise unreachable from here.
          onTap: c.isSoloActive
              ? () => setState(c.clearSolo)
              : slot == null
                  ? () => _notYet('Elige un pad para silenciarlo')
                  : () => setState(() => c.toggleMute(slot)),
          onLongPress: slot == null ? null : () => setState(() => c.toggleSolo(slot)),
        ),
        // The laser dot belongs to the sequencer and only to the sequencer.
        // Rendering the performance out is an export, and wears the icon
        // every phone already reads as "send this somewhere".
        TransportAction(
          icon: Icons.ios_share,
          label: 'Exportar',
          recording: c.mixdown.isRecording,
          onTap: _toggleMixdown,
        ),
      ],
    );
  }

  /// Export: renders what comes out of the mixer to a file while you keep
  /// playing. It never takes a control away — that is the whole point of it
  /// living next to the others instead of behind a screen.
  Future<void> _toggleMixdown() async {
    if (!c.mixdown.isRecording) {
      await c.startMixdown();
      if (mounted) setState(() {});
      return;
    }

    final file = await c.stopMixdown();
    if (!mounted) return;
    setState(() {});
    if (file == null) {
      _notYet('La mezcla salió vacía');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mezcla exportada: ${file.uri.pathSegments.last}'),
        backgroundColor: Palette.panelHigh,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'COMPARTIR',
          textColor: Palette.accent,
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path)],
              text: 'Una mezcla de ${c.session?.name ?? 'Looper'}',
            ),
          ),
        ),
      ),
    );
  }

  String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _notYet(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Palette.panelHigh,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }
}
