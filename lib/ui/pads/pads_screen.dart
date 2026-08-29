import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../audio/fx_curves.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../data/factory_kit.dart';
import '../../domain/knob_scale.dart';
import '../../domain/loop_length.dart';
import '../../domain/midi_target.dart';
import '../../domain/pad_config.dart';
import '../../domain/scale.dart';
import '../../state/session_controller.dart';
import 'bank_tabs.dart';
import 'control_surface.dart';
import 'pad_sheet.dart';
import 'pad_tile.dart';
import 'scene_strip.dart';
import 'sequencer_bar.dart';
import 'song_sheet.dart';
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
    required this.onOpenMidi,
    required this.isMidiConnected,
  });

  final SessionController controller;
  final VoidCallback onOpenSampler;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenMidi;

  /// Lit while a controller is attached, so the icon is a state and not just
  /// a door: whether the grid is listening to plastic is worth knowing at a
  /// glance from the instrument.
  final bool isMidiConnected;

  @override
  State<PadsScreen> createState() => _PadsScreenState();
}

class _PadsScreenState extends State<PadsScreen> {
  SurfaceTab _tab = SurfaceTab.sound;
  Timer? _ringTicker;

  /// Where the FX tab is pointing: at the master output, or at the bus of the
  /// selected pad's family. It opens on the master, which is what the tab has
  /// always been, and the first knob of the row moves it.
  bool _fxOnFamily = false;

  /// While armed, the next pad tapped opens its sheet instead of sounding.
  /// It is the only modal state in the instrument, it lasts one tap, and the
  /// grid says so out loud by lighting every pad as a target.
  bool _editArmed = false;

  /// While armed, the next pad tapped receives the copied pad instead of
  /// sounding. Same bargain as AJUSTAR: one modal state, one tap long.
  bool _pasteArmed = false;

  /// Whether the scenes have the strip. The strip under the grid holds one
  /// thing at a time — knobs, the sequencer, or the scenes — because the grid
  /// is what the screen is for and it never gives up height for a panel.
  bool _scenesOpen = false;

  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Nothing on this screen used to change without a finger on it, so nobody
    // was listening. A controller changes that: a knob turned on the desk, or
    // a pad played from it, has to reach the paint.
    c.addListener(_onInstrumentChanged);
    c.midiLearn.addListener(_onInstrumentChanged);
    // From here on the last half-minute of the master is always within reach,
    // so something worth keeping can be rescued after it happened rather than
    // having to be armed for beforehand.
    c.listenToMaster();
    // The loop rings need a steady repaint; the controller only notifies on
    // real state changes, which is not often enough for a moving ring.
    _ringTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final moving = c.loops.isNotEmpty ||
          c.mixdown.isRecording ||
          c.sequencer.isPlaying ||
          // A hit fades out on its own, so the frame that turns it off has to
          // come from here: nothing else is going to notify anybody.
          c.hasFlashes;
      if (mounted && moving) setState(() {});
    });
  }

  void _onInstrumentChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onInstrumentChanged);
    c.midiLearn.removeListener(_onInstrumentChanged);
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
              if (_scenesOpen) ...[
                _scenes(),
                const SizedBox(height: 8),
              ] else if (c.sequencer.isOn) ...[
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
        if (c.canUndo) ...[
          _iconButton(Icons.undo, _undo),
          const SizedBox(width: 6),
        ],
        // The fourth capture: the master, effects and all, onto a pad. The
        // microphone is never opened, which is what separates it from
        // SAMPLEAR next door.
        _iconButton(Icons.history, _resample),
        const SizedBox(width: 6),
        _iconButton(Icons.library_music_outlined, widget.onOpenLibrary),
        const SizedBox(width: 6),
        _iconButton(Icons.mic_none, widget.onOpenSampler),
        const SizedBox(width: 6),
        _iconButton(
          Icons.piano_outlined,
          widget.onOpenMidi,
          lit: widget.isMidiConnected,
        ),
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

  Widget _iconButton(IconData icon, VoidCallback onTap, {bool lit = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: lit ? Palette.accent : Palette.line),
        ),
        child: Icon(icon, size: 16, color: lit ? Palette.accent : Palette.inkDim),
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
        // As a keyboard, every pad wears the source sound — same colour, same
        // wash — and says which note it is. The pad it came from keeps the
        // selected border so it is obvious what is being played.
        final source = c.scaleSource;
        final pad = source == null ? c.padAt(slot) : c.padAt(source);
        final sound = c.soundFor(pad);
        return PadTile(
          pad: pad,
          sound: sound,
          state: _stateFor(source ?? slot, pad),
          stepLight: _stepLightFor(slot),
          stepNotes: c.sequencer.isOn ? c.sequencer.pattern.at(slot).length : 0,
          accent: _accentFor(slot),
          labelOverride: source == null ? null : c.scaleLabelFor(slot),
          progress: c.loopProgress(c.activeBank, slot),
          selected: source == null ? c.selectedSlot == slot : slot == source,
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
    if (_pasteArmed) {
      setState(() => _pasteArmed = false);
      _pastePadOn(slot);
      return;
    }
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
        onChanged: (pad) async {
          final soundChanged = c.padAt(slot).soundId != pad.soundId;
          await c.updatePad(bank, slot, pad);
          if (!mounted || !soundChanged) return;
          _offerUndo(pad.isEmpty ? 'Pad vaciado' : 'Sonido cambiado');
        },
        onCopy: () {
          Navigator.of(context).pop();
          c.copyPad(slot);
          _armPastePad();
        },
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

  /// The accent bar only shows where it means something: the sequencer on,
  /// and a step that actually has notes in it. Drawing a full bar under every
  /// empty step would turn a real reading into decoration.
  double? _accentFor(int slot) {
    final seq = c.sequencer;
    if (!seq.isOn) return null;
    if (seq.pattern.at(slot).isEmpty) return null;
    return seq.pattern.velocityAt(slot);
  }

  PadVisualState _stateFor(int slot, PadConfig pad) {
    if (_editArmed || _pasteArmed) return PadVisualState.target;
    if (pad.isEmpty) return PadVisualState.empty;
    if (!c.isLooping(c.activeBank, slot)) {
      // A hit outranks «loaded» for as long as it lasts: it is the only
      // moment the pad has anything to say.
      return c.isFlashing(c.activeBank, slot)
          ? PadVisualState.firing
          : PadVisualState.loaded;
    }
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
        : '${kBankIds[c.activeBank]} · ${(slot! + 1).toString().padLeft(2, '0')} · ${sound.name}'
            '${c.isScaleOn ? ' · TECLADO' : ''}';

    return ControlSurface(
      targetLabel: label,
      // Phosphor for the master row: laser is reserved for writing the pattern.
      targetColor: sound?.family.color ?? Palette.accent,
      tab: _tab,
      onTabChanged: (t) => setState(() => _tab = t),
      knobs: _knobsFor(slot, pad),
      learn: c.midiLearn,
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
          target: const MidiTarget(MidiParam.masterVolume),
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
            target: const MidiTarget(MidiParam.padVolume),
            onChanged: (v) => setState(() => c.setPadVolume(slot, v)),
          ),
          KnobSpec(
            label: 'Tono',
            display: pad.semitones > 0 ? '+${pad.semitones}' : '${pad.semitones}',
            value: semitonesAsKnob(pad.semitones),
            target: const MidiTarget(MidiParam.padPitch),
            onChanged: (v) =>
                setState(() => c.setPadSemitones(slot, knobAsSemitones(v))),
          ),
          KnobSpec(
            label: 'Pan',
            // L and R rather than a signed number: nobody thinks in −0,4.
            display: pad.pan.abs() < kPanDeadZone
                ? 'C'
                : '${pad.pan < 0 ? 'L' : 'R'}${(pad.pan.abs() * 100).round()}',
            value: panAsKnob(pad.pan),
            accent: pad.pan.abs() >= kPanDeadZone,
            target: const MidiTarget(MidiParam.padPan),
            onChanged: (v) => setState(() => c.setPadPan(slot, knobAsPan(v))),
          ),
          KnobSpec(
            label: 'Mute',
            display: pad.muted ? 'ON' : 'OFF',
            value: switchAsKnob(pad.muted),
            accent: pad.muted,
            target: const MidiTarget(MidiParam.padMute),
            onChanged: (v) {
              if (knobAsSwitch(v) != pad.muted) {
                setState(() => c.toggleMute(slot));
              }
            },
          ),
          // Solo points at this pad, not at the session: with another pad
          // soloed this knob reads OFF, because this one is not the one
          // being heard.
          KnobSpec(
            label: 'Solo',
            display: c.isSoloOn(slot) ? 'ON' : 'OFF',
            value: switchAsKnob(c.isSoloOn(slot)),
            accent: c.isSoloOn(slot),
            target: const MidiTarget(MidiParam.padSolo),
            onChanged: (v) {
              if (knobAsSwitch(v) != c.isSoloOn(slot)) {
                setState(() => c.toggleSolo(slot));
              }
            },
          ),
        ];
      case SurfaceTab.scale:
        return _scaleKnobs(slot);
      case SurfaceTab.fx:
        final sound = c.soundFor(pad);
        if (sound == null) return _fxKnobs(includeResonance: true);
        return [
          KnobSpec(
            label: 'Bus',
            display: _fxOnFamily ? sound.family.label : 'Maestro',
            value: switchAsKnob(_fxOnFamily),
            accent: _fxOnFamily,
            onChanged: (v) => setState(() => _fxOnFamily = knobAsSwitch(v)),
          ),
          if (_fxOnFamily)
            ..._busKnobs(sound.family)
          else
            ..._fxKnobs(includeResonance: true),
        ];
      case SurfaceTab.loop:
        final looping = c.isLooping(c.activeBank, slot);
        final choices = loopLengthChoices(pad.loopSteps);
        return [
          KnobSpec(
            label: 'Loop',
            display: looping ? 'ON' : 'OFF',
            value: switchAsKnob(looping),
            accent: looping,
            target: const MidiTarget(MidiParam.padLoop),
            onChanged: (v) =>
                setState(() => c.setPadLooping(slot, knobAsSwitch(v))),
          ),
          KnobSpec(
            label: 'Sync',
            display: pad.synced ? 'ON' : 'OFF',
            value: switchAsKnob(pad.synced),
            accent: pad.synced,
            target: const MidiTarget(MidiParam.padSync),
            onChanged: (v) =>
                setState(() => c.setPadSynced(slot, knobAsSwitch(v))),
          ),
          KnobSpec(
            label: 'Tiempos',
            display: loopLengthLabel(pad.loopSteps),
            value: indexAsKnob(choices.indexOf(pad.loopSteps), choices.length),
            target: const MidiTarget(MidiParam.padLoopSteps),
            onChanged: (v) => setState(() => c.setPadLoopSteps(
                slot, choices[knobAsIndex(v, choices.length)])),
          ),
        ];
    }
  }

  /// The grid as a keyboard. The pad picked before opening this tab is the
  /// one whose sound gets played at every degree — the same bargain the rest
  /// of the surface makes, where the knobs point at whatever is selected.
  List<KnobSpec> _scaleKnobs(int slot) {
    final scales = Scale.values;
    final atOctave = kScaleOctaves.indexOf(c.scaleOctave);

    return [
      KnobSpec(
        label: 'Teclado',
        display: c.isScaleOn ? 'ON' : 'OFF',
        value: switchAsKnob(c.isScaleOn),
        accent: c.isScaleOn,
        target: const MidiTarget(MidiParam.scaleOn),
        onChanged: (v) {
          final wanted = knobAsSwitch(v);
          if (wanted == c.isScaleOn) return;
          setState(() => c.toggleScale(wanted ? slot : null));
        },
      ),
      KnobSpec(
        label: 'Tónica',
        display: noteName(c.scaleRoot),
        value: rootAsKnob(c.scaleRoot),
        target: const MidiTarget(MidiParam.scaleRoot),
        onChanged: (v) => setState(() => c.setScaleRoot(knobAsRoot(v))),
      ),
      KnobSpec(
        label: 'Escala',
        display: c.scale.label,
        value: indexAsKnob(scales.indexOf(c.scale), scales.length),
        target: const MidiTarget(MidiParam.scaleKind),
        onChanged: (v) => setState(
            () => c.setScale(scales[knobAsIndex(v, scales.length)])),
      ),
      KnobSpec(
        label: 'Octava',
        display: c.scaleOctave > 0 ? '+${c.scaleOctave}' : '${c.scaleOctave}',
        value: indexAsKnob(
            atOctave < 0 ? kScaleOctaves.indexOf(0) : atOctave,
            kScaleOctaves.length),
        target: const MidiTarget(MidiParam.scaleOctave),
        onChanged: (v) => setState(() => c
            .setScaleOctave(kScaleOctaves[knobAsIndex(v, kScaleOctaves.length)])),
      ),
    ];
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
        target: const MidiTarget(MidiParam.masterCutoff),
        onChanged: (v) => setState(() => fx.cutoff = v),
      ),
      if (includeResonance)
        KnobSpec(
          label: 'Reso',
          display: (fx.resonance * 100).round().toString(),
          value: fx.resonance,
          accent: fx.resonance > kFxEpsilon,
          target: const MidiTarget(MidiParam.masterResonance),
          onChanged: (v) => setState(() => fx.resonance = v),
        ),
      KnobSpec(
        label: 'Eco',
        display:
            fx.echo <= kFxEpsilon ? 'OFF' : (fx.echo * 100).round().toString(),
        value: fx.echo,
        accent: fx.echo > kFxEpsilon,
        target: const MidiTarget(MidiParam.masterEcho),
        onChanged: (v) => setState(() => fx.echo = v),
      ),
      KnobSpec(
        label: 'Drive',
        display:
            fx.drive <= kFxEpsilon ? 'OFF' : (fx.drive * 100).round().toString(),
        value: fx.drive,
        accent: fx.drive > kFxEpsilon,
        target: const MidiTarget(MidiParam.masterDrive),
        onChanged: (v) => setState(() => fx.drive = v),
      ),
    ];
  }

  /// The selected pad's family bus: its own filter, its own grit, and how
  /// much of it goes to the reverb everyone shares.
  ///
  /// Filter, resonance and drive keep the position they have on the master
  /// row, so the thumb does not have to relearn the strip when it changes
  /// what it is pointing at. Only the third knob differs — echo on the
  /// master, send on a bus — and it says which it is.
  List<KnobSpec> _busKnobs(SoundFamily family) {
    final buses = c.buses;
    final bus = buses.settingsFor(family);
    final filterOpen = bus.cutoff >= 1 - kFxEpsilon;
    return [
      KnobSpec(
        label: 'Filtro',
        display: filterOpen ? 'OFF' : (bus.cutoff * 100).round().toString(),
        value: bus.cutoff,
        accent: !filterOpen,
        target: MidiTarget.bus(MidiParam.busCutoff, family),
        onChanged: (v) => setState(() => buses.setCutoff(family, v)),
      ),
      KnobSpec(
        label: 'Reso',
        display: (bus.resonance * 100).round().toString(),
        value: bus.resonance,
        accent: bus.resonance > kFxEpsilon,
        target: MidiTarget.bus(MidiParam.busResonance, family),
        onChanged: (v) => setState(() => buses.setResonance(family, v)),
      ),
      KnobSpec(
        label: 'Envío',
        display: bus.isSendResting ? 'OFF' : (bus.send * 100).round().toString(),
        value: bus.send,
        accent: !bus.isSendResting,
        target: MidiTarget.bus(MidiParam.busSend, family),
        onChanged: (v) => setState(() => buses.setSend(family, v)),
      ),
      KnobSpec(
        label: 'Drive',
        display:
            bus.isDriveResting ? 'OFF' : (bus.drive * 100).round().toString(),
        value: bus.drive,
        accent: !bus.isDriveResting,
        target: MidiTarget.bus(MidiParam.busDrive, family),
        onChanged: (v) => setState(() => buses.setDrive(family, v)),
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
      songMode: seq.songMode,
      songBars: c.song.bars,
      songBar: seq.songBar,
      onSongMode: (on) => setState(() {
        if (on != seq.songMode) c.toggleSongMode();
      }),
      onOpenSong: _openSongSheet,
      swing: c.swing,
      editingVelocity: seq.editingVelocity,
      editingProbability: seq.editingProbability,
      editingNudge: seq.editingNudge,
      editingRatchet: seq.editingRatchet,
      isCountingIn: seq.isCountingIn,
      countInBeat: seq.countInBeat,
      onSwing: (v) => setState(() => c.setSwing(v)),
      onVelocity: (v) => setState(() => c.setStepVelocity(v)),
      onProbability: (v) => setState(() => c.setStepProbability(v)),
      onNudge: (v) => setState(() => c.setStepNudge(v)),
      onRatchet: (v) => setState(() => c.setStepRatchet(v)),
      onCopyPattern: _copyPattern,
      onPlay: () => setState(c.toggleSequencerPlay),
      onRecord: () async {
        await c.toggleSequencerRecord();
        if (mounted) setState(() {});
      },
      onRest: () => setState(seq.rest),
      onClear: () {
        setState(c.clearPattern);
        _offerUndo('Patrón borrado');
      },
      onPattern: (index) => setState(() => c.selectPattern(index)),
      onChain: (bars) => setState(() => c.setChainLength(bars)),
    );
  }

  Widget _scenes() {
    return SceneStrip(
      scenes: c.scenes,
      activeScene: c.activeScene,
      pendingScene: c.pendingScene,
      armed: _editArmed,
      onLaunch: (i) => setState(() => c.launchScene(i)),
      onCapture: (i) {
        HapticFeedback.mediumImpact();
        setState(() => c.captureScene(i));
      },
      onClear: (i) {
        setState(() {
          c.clearScene(i);
          _editArmed = false;
        });
        _offerUndo('Escena ${i + 1} vaciada');
      },
    );
  }

  /// The running order, opened by holding the chain pill. Edits land on the
  /// session as they are made, like every other sheet in this app.
  Future<void> _openSongSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SongSheet(
        song: c.song,
        songMode: c.isSongMode,
        currentPattern: c.sequencer.patternIndex,
        onChanged: (song) => setState(() => c.setSong(song)),
        onModeChanged: (on) => setState(() {
          if (on != c.isSongMode) c.toggleSongMode();
        }),
      ),
    );
    if (mounted) setState(() {});
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
          onTap: () => setState(() {
            // The strip holds one thing at a time, so asking for the
            // sequencer is also asking the scenes to step aside.
            _scenesOpen = false;
            c.toggleSequencer();
          }),
        ),
        // Scenes share the strip with the sequencer, so they share its
        // neighbourhood on the transport too.
        TransportAction(
          icon: Icons.view_week_outlined,
          label: 'Escenas',
          active: _scenesOpen,
          onTap: () => setState(() => _scenesOpen = !_scenesOpen),
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

  /// Says what just happened and keeps the way back within reach for a few
  /// seconds. The button up top stays available long after this is gone —
  /// this is here so the way back gets found in the first place.
  void _offerUndo(String done) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(done),
          backgroundColor: Palette.panelHigh,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'DESHACER',
            textColor: Palette.accent,
            onPressed: _undo,
          ),
        ),
      );
  }

  Future<void> _undo() async {
    final label = await c.undo();
    if (label == null || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deshecho: $label'),
          backgroundColor: Palette.panelHigh,
          duration: const Duration(milliseconds: 1800),
        ),
      );
  }

  /// Rescues the last four bars of the master onto a free pad.
  ///
  /// Four bars rather than a fixed number of seconds: a piece cut to the grid
  /// drops back onto it in time. Whatever is held is used when less than that
  /// has gone by.
  Future<void> _resample() async {
    if (!c.canCaptureMaster) {
      _notYet('Todavía no ha sonado nada que rescatar');
      return;
    }

    final barMs = (60000 / c.bpm * kStepsPerBeat).round();
    final landed = await c.captureMaster(
      window: Duration(milliseconds: barMs * 4),
      name: 'Mezcla ${c.bpm}',
    );
    if (!mounted) return;

    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(landed == null
              ? 'No queda ningún pad libre donde ponerlo'
              : 'Cuatro compases en ${kBankIds[landed.bank]} · '
                  '${(landed.slot + 1).toString().padLeft(2, '0')}'),
          backgroundColor: Palette.panelHigh,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Copying a pad: the sheet lifts it, this arms the grid, and the next tap
  /// puts it down. The snackbar is the way out for a copy started by mistake.
  void _armPastePad() {
    setState(() => _pasteArmed = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Pad copiado · toca el pad de destino'),
          backgroundColor: Palette.panelHigh,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'CANCELAR',
            textColor: Palette.accent,
            onPressed: () {
              if (mounted) setState(() => _pasteArmed = false);
            },
          ),
        ),
      );
  }

  Future<void> _pastePadOn(int slot) async {
    await c.pastePad(slot);
    if (!mounted) return;
    setState(() {});
    _offerUndo('Pad pegado');
  }

  /// Copying a pattern: lift it here, walk to the destination with the
  /// arrows, and PEGAR drops it on whatever pattern is on screen then.
  void _copyPattern() {
    c.copyPattern();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('P${c.sequencer.patternIndex + 1} copiado · '
              've al patrón de destino'),
          backgroundColor: Palette.panelHigh,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'PEGAR',
            textColor: Palette.accent,
            onPressed: () {
              c.pastePattern();
              if (mounted) setState(() {});
              _offerUndo('Patrón pegado en P${c.sequencer.patternIndex + 1}');
            },
          ),
        ),
      );
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
