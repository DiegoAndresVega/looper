import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:uuid/uuid.dart';

import 'dart:io';

import '../audio/audio_engine.dart';
import '../audio/chopper.dart';
import '../audio/family_fx.dart';
import '../audio/master_fx.dart';
import '../audio/mixdown_recorder.dart';
import '../audio/mixer_tap.dart';
import '../audio/stretch.dart';
import '../audio/synth_voice.dart';
import '../audio/wav_decoder.dart';
import '../audio/wav_encoder.dart';
import '../audio/tempo_clock.dart';
import '../core/constants.dart';
import '../core/palette.dart';
import '../data/metronome.dart';
import '../data/disk_space.dart';
import '../data/midi_map_store.dart';
import '../data/session_store.dart';
import '../data/sound_library.dart';
import '../data/storage.dart';
import 'midi_apply.dart';
import 'pad_flashes.dart';
import 'midi_learn.dart';
import 'sequencer.dart';
import 'undo_stack.dart';
import '../domain/pad_config.dart';
import '../domain/pattern.dart';
import '../domain/midi.dart';
import '../domain/midi_out.dart';
import '../domain/save_point.dart';
import '../domain/chord.dart';
import '../domain/scale.dart';
import '../domain/scene.dart';
import '../domain/song.dart';
import '../domain/session.dart';
import '../domain/sound.dart';
import '../domain/synth_patch.dart';

const _uuid = Uuid();

/// Identifies one pad across the whole session. Patterns are written in these,
/// which is what lets one pattern pull pads from different banks.
String padKey(int bank, int slot) => '$bank:$slot';

/// Reads a pad key back, or null when it points nowhere — a pattern saved
/// before a bank was emptied can carry keys that no longer mean anything.
({int bank, int slot})? parsePadKey(String key) {
  final parts = key.split(':');
  if (parts.length != 2) return null;
  final bank = int.tryParse(parts[0]);
  final slot = int.tryParse(parts[1]);
  if (bank == null || slot == null) return null;
  if (bank < 0 || bank >= kBankCount) return null;
  if (slot < 0 || slot >= kPadsPerBank) return null;
  return (bank: bank, slot: slot);
}

/// A pad currently making noise on loop.
class ActiveLoop {
  ActiveLoop({required this.bank, required this.slot, this.handle, required this.synced});

  final int bank;
  final int slot;
  final bool synced;
  SoundHandle? handle;
}

/// Owns the live state of a session: what is loaded, what is looping, the
/// tempo and which pad the control surface points at.
class SessionController extends ChangeNotifier {
  SessionController({
    required AudioEngine engine,
    required SoundLibrary library,
    required SessionStore store,
  })  : _engine = engine,
        _library = library,
        _store = store {
    _clock = TempoClock(onStep: _onSyncedStep);
    sequencer = Sequencer(
      onNotes: _fireNotes,
      onPatternsChanged: _onPatternsChanged,
    );
  }

  /// The step sequencer. It rides the same 16th-note clock as the synced
  /// loops, so a pattern and a loop never drift apart.
  late final Sequencer sequencer;

  final AudioEngine _engine;
  final SoundLibrary _library;
  final SessionStore _store;
  late final TempoClock _clock;

  /// Edits are written to disk on their own, a moment after the last one, so
  /// dragging a knob does not hit the file on every frame.
  Timer? _saveTimer;

  /// The one listener on the mixer output. Exporting a take, resampling the
  /// master back onto a pad and rescuing what just played all read from here,
  /// because the engine only hands out one such stream.
  late final MixerTap tap = MixerTap(engine: _engine);

  /// Recording the performance — the mixer output, never the microphone — so
  /// it can run while the grid is being played.
  late final MixdownRecorder mixdown =
      MixdownRecorder(tap: tap, storage: Storage.instance);

  Session? _session;
  int _activeBank = 0;
  int? _selectedSlot;
  /// The pad currently soloed, or null. Stored as a key rather than written
  /// into every other pad's `muted`, which is what used to destroy the
  /// player's own mutes — and persist the loss, because the session
  /// autosaves. Solo is performance state: it never reaches disk.
  String? _soloKey;
  final Map<String, ActiveLoop> _loops = {};

  /// The last one-shot fired by each pad, kept so the next tap can cut it.
  final Map<String, SoundHandle> _hits = {};

  /// Which pads are mid-hit, for the grid to light. The pads could always
  /// draw this and nothing produced it.
  final PadFlashes _flashes = PadFlashes();

  /// One step back for each destructive edit. Only the session goes in here:
  /// deleting a sound from the library takes its file with it, and an undo
  /// that restored a pad pointing at a file that no longer exists would be
  /// worse than no undo at all.
  final UndoStack<Session> _undo = UndoStack<Session>();

  Timer? _rollTimer;
  bool _metronome = false;
  Sound? _click;

  Session? get session => _session;

  bool get canUndo => _undo.canUndo;

  /// What the next undo would take back, for the button to say it out loud.
  String? get undoLabel => _undo.topLabel;
  int get activeBank => _activeBank;
  int? get selectedSlot => _selectedSlot;
  int get bpm => _session?.bpm ?? kDefaultBpm;
  bool get isSoloActive => _soloKey != null;

  /// Whether this pad of the bank on screen is the one being soloed.
  bool isSoloOn(int slot) => _soloKey == padKey(_activeBank, slot);
  Map<String, ActiveLoop> get loops => Map.unmodifiable(_loops);

  Bank get currentBank => _session!.banks[_activeBank];

  PadConfig padAt(int slot) => currentBank.pads[slot];

  Sound? soundFor(PadConfig pad) => _library.byId(pad.soundId);

  /// Every sound available to drop on a pad.
  List<Sound> get librarySounds => _library.sounds;

  /// Master volume and the performance effects, exposed for the surface.
  MasterFx get fx => _engine.fx;

  /// The four family buses and the reverb they share, same deal.
  FamilyFx get buses => _engine.buses;

  /// Plays a sound once to audition it, loading it if it never reached a pad.
  Future<void> preview(Sound sound) async {
    if (!_engine.isLoaded(sound.id)) {
      await _engine.preload(sound, _library.pathFor(sound));
    }
    _engine.fire(sound, volume: sound.volume, rate: sound.playbackRate);
  }

  bool isLooping(int bank, int slot) => _loops.containsKey(padKey(bank, slot));

  /// True while this pad is mid-hit, whoever hit it: a finger, the
  /// sequencer, a scene or a controller.
  bool isFlashing(int bank, int slot) => _flashes.isLit(padKey(bank, slot));

  /// Whether any pad is still lit, so the screen knows to keep repainting.
  bool get hasFlashes => _flashes.any;

  /// True when a bank other than the visible one has loops running, so its
  /// tab can light up.
  bool bankHasLoops(int bank) =>
      _loops.values.any((loop) => loop.bank == bank);

  double loopProgress(int bank, int slot) {
    final key = padKey(bank, slot);
    if (!_clock.contains(key)) return 0;
    return _clock.progressFor(key);
  }

  /// True while a loop is armed and waiting for the downbeat to come round.
  /// The pad is already on: it just has not made a sound yet.
  bool isQueued(int bank, int slot) => _clock.isPending(padKey(bank, slot));

  // ---------------------------------------------------------------- session

  Future<void> open(Session session) async {
    await stopAllLoops();
    _session = session;
    // Steps back belong to the session they were taken in: undoing into
    // another session's pads would be worse than not undoing at all.
    _undo.clear();
    _clock.setBpm(session.bpm);
    _clock.swing = session.swing;
    _activeBank = 0;
    _selectedSlot = null;
    _activeScene = null;
    _pendingScene = null;
    _flashes.clear();
    sequencer.load(
      session.patterns,
      session.activePattern,
      chainLength: session.chainLength,
      song: session.song,
      songMode: session.songMode,
    );
    await _preloadSession();
    await refreshFreeSpace();
    notifyListeners();
  }

  Future<void> _preloadSession() async {
    final session = _session;
    if (session == null) return;
    for (final bank in session.banks) {
      for (final pad in bank.pads) {
        final sound = _library.byId(pad.soundId);
        if (sound != null && !_engine.isLoaded(sound.id)) {
          await _engine.preload(sound, _library.pathFor(sound));
        }
      }
    }
  }

  /// Files the session as it stands before something destroys part of it.
  /// Continuous controls — volume, pitch, accent — deliberately do not come
  /// through here: they are undone by moving the knob back, and a snapshot per
  /// frame of a drag would bury the edits that actually cannot be retyped.
  void _remember(String label) {
    final session = _session;
    if (session == null) return;
    _undo.push(session, label);
  }

  /// Steps back to the session as it was before the last destructive edit.
  /// Returns what was taken back, so the screen can say so.
  Future<String?> undo() async {
    final entry = _undo.undo();
    if (entry == null) return null;

    _session = entry.state;
    sequencer.load(
      entry.state.patterns,
      entry.state.activePattern,
      chainLength: entry.state.chainLength,
      song: entry.state.song,
      songMode: entry.state.songMode,
    );
    _clock.setBpm(entry.state.bpm);
    _clock.swing = entry.state.swing;
    // A pad coming back may point at a sound no pad has held for a while.
    await _preloadSession();
    _touch();
    notifyListeners();
    return entry.label;
  }

  /// Marks the session as dirty. The write lands once the edits stop, so
  /// dragging a knob does not touch the disk on every frame.
  void _touch() {
    final session = _session;
    if (session == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(kSessionSaveDelay, () => _store.save(session));
  }

  /// Writes any pending edit right now, before leaving the instrument.
  Future<void> flush() async {
    _saveTimer?.cancel();
    final session = _session;
    if (session != null) await _store.save(session);
  }

  /// Loads every sound of the session into the engine again. Needed after the
  /// engine has been released so the microphone could have the audio session.
  Future<void> reloadSounds() => _preloadSession();

  /// Puts a freshly captured sound on the first free pad — bank C first, as
  /// promised — and brings that bank forward so it is obvious where it landed.
  /// Returns null when all 64 pads are taken.
  Future<({int bank, int slot})?> placeSound(Sound sound) async {
    final session = _session;
    if (session == null) return null;
    final target = session.nextFreeSlot;
    if (target == null) return null;

    await updatePad(target.bank, target.slot, PadConfig(soundId: sound.id));
    _activeBank = target.bank;
    _selectedSlot = target.slot;
    notifyListeners();
    return target;
  }

  /// How the audio would be cut, without committing to it: the sheet draws
  /// these lines before anything is created.
  Future<List<Slice>> previewChop(Sound sound, ChopMode mode) async {
    final length = sound.trimmedDurationMs;
    if (mode != ChopMode.transients) {
      return sliceEvenly(durationMs: length, count: mode.pieces);
    }

    // About one bucket every 10 ms, capped: fine enough to separate two hits
    // of a drum break, bounded so a long import stays cheap to analyse.
    final buckets = (sound.durationMs ~/ 10).clamp(kWaveformBuckets, 2048);
    final peaks = await _library.detailedPeaksFor(sound, buckets);
    // The envelope covers the whole file; the chop only covers what the
    // sound actually plays, so the trimmed window is cut out of it first.
    final from = (peaks.length * sound.trimStartMs / sound.durationMs).floor();
    final to = (peaks.length * sound.effectiveEndMs / sound.durationMs).ceil();
    final window = peaks.sublist(
      from.clamp(0, peaks.length),
      to.clamp(from.clamp(0, peaks.length), peaks.length),
    );
    return slicesFromOnsets(
      onsets: detectOnsets(window, maxOnsets: kPadsPerBank),
      buckets: window.length,
      durationMs: length,
    );
  }

  /// Cuts [sound] into pieces and lays them across the grid in order.
  ///
  /// No audio is copied: every piece is a sound over the same file with its
  /// own trim. Returns where they landed, or null when no bank has that many
  /// free pads in a row.
  Future<({int bank, int slot, int count})?> chop(
    Sound sound,
    List<Slice> slices,
  ) async {
    final session = _session;
    if (session == null || slices.isEmpty) return null;

    final room = findRoomFor(session, slices.length);
    if (room == null) return null;

    _remember('cortar ${sound.name}');

    final pieces = chopSound(
      source: sound,
      slices: slices,
      idFor: (_) => _uuid.v4(),
    );

    await _library.addAll(pieces);

    var next = _session!;
    for (var i = 0; i < pieces.length; i++) {
      await _engine.preload(pieces[i], _library.pathFor(pieces[i]));
      next = next.withPad(
        room.bank,
        room.slot + i,
        PadConfig(soundId: pieces[i].id),
      );
    }
    _session = next;
    _activeBank = room.bank;
    _selectedSlot = room.slot;
    _touch();
    notifyListeners();
    return (bank: room.bank, slot: room.slot, count: pieces.length);
  }

  // ------------------------------------------------------- master capture

  /// Opens the tap so the last [kSkipBackSeconds] of the master are always
  /// within reach. Called when the instrument comes on screen.
  void listenToMaster() => tap.open();

  /// Closes it. The microphone needs the engine to itself, and audio from
  /// before that break must not be spliced onto audio from after it.
  Future<void> stopListeningToMaster() async {
    await tap.close();
  }

  /// True while there is enough of the master held to be worth rescuing.
  bool get canCaptureMaster =>
      tap.isOpen && tap.buffered > const Duration(milliseconds: 400);

  /// Puts the last [window] of the master on the first free pad — effects
  /// included, microphone never opened. With no window, everything held.
  ///
  /// This is both features at once: asked for right after something good,
  /// it is a rescue; asked for while a loop runs, it is a resample that folds
  /// several layers into one pad.
  Future<({int bank, int slot})?> captureMaster({
    Duration? window,
    String name = 'Mezcla',
  }) async {
    final bytes = tap.recentWav(window: window);
    if (bytes == null) return null;

    final storage = Storage.instance;
    final fileName = '${_uuid.v4()}.wav';
    final file = storage.soundFile(fileName);
    await file.writeAsBytes(bytes);

    final decoded = decodeWav(bytes);
    final sound = await _library.add(Sound(
      id: _uuid.v4(),
      name: name,
      family: SoundFamily.texture,
      fileName: fileName,
      origin: SoundOrigin.recorded,
      durationMs: (decoded.samples.length / decoded.sampleRate * 1000).round(),
      sizeBytes: bytes.length,
    ));

    return placeSound(sound);
  }

  void selectBank(int index) {
    if (index == _activeBank) return;
    // The grid is always the bank on screen: a keyboard sourced from a pad in
    // another bank would leave every pad here playing something invisible.
    _scaleSource = null;
    _activeBank = index;
    _selectedSlot = null;
    notifyListeners();
  }

  void setBpm(int value) {
    final session = _session;
    if (session == null) return;
    final clamped = value.clamp(kBpmMin, kBpmMax);
    if (clamped == session.bpm) return;
    _session = session.copyWith(bpm: clamped);
    _clock.setBpm(clamped);
    if (_clockTimer != null) _startClock();
    _touch();
    notifyListeners();
  }

  // ------------------------------------------------------------------ pads

  /// A tap fires the pad and points the control surface at it. Tap again and
  /// it fires again, so hitting the pad in a rhythm plays that rhythm. On a
  /// pad that is already looping, the tap switches the loop off.
  void tapPad(int slot) {
    // A pad played as a note does not become the selected pad: the surface
    // has to keep pointing at the sound being played, not at the last key hit.
    final source = _scaleSource;
    if (source != null && !padAt(source).isEmpty) {
      _playChord(source, slot);
      notifyListeners();
      return;
    }

    _selectedSlot = slot;
    final pad = padAt(slot);
    if (pad.isEmpty) {
      notifyListeners();
      return;
    }

    // With ROLL held, touching a pad points the roll at it.
    if (_rollHeld) {
      _rollOn(_activeBank, slot);
      notifyListeners();
      return;
    }

    // While the sequencer is being written into, a tap is a note being placed
    // — and it still sounds, so the pattern is built by ear.
    if (sequencer.isWriting) {
      sequencer.tap(padKey(_activeBank, slot));
      _fireOnce(_activeBank, slot);
      notifyListeners();
      return;
    }

    if (isLooping(_activeBank, slot)) {
      _stopLoop(padKey(_activeBank, slot));
    } else {
      _fireOnce(_activeBank, slot);
    }
    notifyListeners();
  }

  /// A long press leaves the pad looping. Holding again does nothing: the way
  /// out is a tap, the same finger that started it.
  void holdPad(int slot) {
    // As a keyboard the pads are notes, and a note held is still just a note:
    // looping one degree of a scale is a different feature, not this one.
    if (_scaleSource != null) {
      tapPad(slot);
      return;
    }
    _selectedSlot = slot;

    // With the sequencer on, the grid doubles as the sixteen steps: holding a
    // pad picks its step to write into by hand.
    if (sequencer.isOn) {
      sequencer.selectStep(slot);
      notifyListeners();
      return;
    }

    final pad = padAt(slot);
    if (pad.isEmpty || isLooping(_activeBank, slot)) {
      notifyListeners();
      return;
    }
    _startLoop(_activeBank, slot);
    notifyListeners();
  }

  /// Fires a pad once. A new hit cuts the previous one from the same pad, so
  /// fast tapping reads as a roll instead of piling voices on top of one
  /// another. Loops are untouched: they have their own handle.
  void _fireOnce(
    int bank,
    int slot, {
    double velocity = kVelocityMax,
    int transpose = 0,
  }) {
    final pad = _session!.banks[bank].pads[slot];
    final sound = _library.byId(pad.soundId);
    if (sound == null || _isSilenced(bank, slot, pad)) return;

    // The flash belongs to the pad, not to the note: playing the grid as a
    // keyboard lights the pad the sound came from, which is where the eye
    // already is.
    _flashes.fire(padKey(bank, slot));

    // The transposition is part of the voice's identity: without it, playing
    // a C and then an E on the same source sound would cut the C off, and the
    // grid-as-keyboard would come out monophonic. Repeating the *same* note
    // still follows the pad's own mode, which is what the kit does too.
    final key = transpose == 0
        ? padKey(bank, slot)
        : '${padKey(bank, slot)}@$transpose';

    // The group first: an open hat is silenced by the closed one before the
    // closed one sounds, not after.
    _chokeFor(bank, slot, pad);

    final previous = _hits[key];
    final alive = previous != null && _engine.isVoiceAlive(previous);
    switch (hitActionFor(mode: pad.playMode, isSounding: alive)) {
      case HitAction.ignore:
        return;
      case HitAction.cutPrevious:
        _hits.remove(key);
        if (previous != null) _engine.stopHandle(previous);
      case HitAction.layer:
        // The older voice keeps ringing but stops being the pad's current
        // one. It is parked so PARAR can still reach it: a voice nobody
        // holds is a voice the panic button cannot stop.
        _hits.remove(key);
        if (alive) _park(previous);
    }

    final handle = _engine.fire(
      sound,
      volume: pad.volume * sound.volume * velocity,
      rate: sound.playbackRate * _rateFor(pad) * _rateForSemitones(transpose),
      pan: pad.pan,
    );
    if (handle != null) _hits[key] = handle;

    // And out of the cable, so the same finger plays whatever else is on the
    // desk. A short gate: this is a trigger, not a held key, and a note left
    // on would hang a synth the moment the app is closed.
    if (_midiOut) {
      _send(noteOnMessage(bank: bank, slot: slot, velocity: velocity));
      Timer(kMidiGate, () => _send(noteOffMessage(bank: bank, slot: slot)));
    }
  }

  /// Tape-style: the pad's own pitch offset stacks on the sound's.
  double _rateFor(PadConfig pad) => _rateForSemitones(pad.semitones);

  double _rateForSemitones(int semitones) =>
      semitones == 0 ? 1.0 : math.pow(2, semitones / 12.0).toDouble();

  // ------------------------------------------------------------------ MIDI

  StreamSubscription<MidiEvent>? _midiSubscription;

  /// Which control of the desk moves what, and the knob waiting to find out.
  late final MidiLearn midiLearn = MidiLearn(MidiMapStore(Storage.instance));

  /// Something moved a parameter from outside the screen. Nothing in the
  /// session changed, but the strip is now lying about where its knobs are.
  void refreshSurface() => notifyListeners();

  // ------------------------------------------------------- MIDI de salida

  /// Where bytes leave for the controller, or null when nothing is attached.
  /// A function rather than the service itself: the instrument has no idea
  /// what a MIDI package is, and it is not about to learn.
  void Function(Uint8List data)? _midiSend;

  /// Whether the instrument talks back. Off by default: a clock nobody asked
  /// for will start somebody else's drum machine in the middle of a take.
  bool _midiOut = false;
  Timer? _clockTimer;

  bool get isMidiOutOn => _midiOut;

  void attachMidiOut(void Function(Uint8List data) send) => _midiSend = send;

  /// Sends the clock, the transport and every note this instrument plays.
  /// Turning it off stops the clock immediately: something out there is
  /// following it, and leaving it running would leave that thing running.
  void setMidiOut(bool value) {
    if (_midiOut == value) return;
    _midiOut = value;
    if (!value) {
      _stopClock();
      _send(stopMessage);
    } else if (sequencer.isPlaying) {
      _send(startMessage);
      _startClock();
    }
    notifyListeners();
  }

  void _send(Uint8List data) {
    if (!_midiOut) return;
    _midiSend?.call(data);
  }

  /// Twenty-four pulses a quarter note, which is the only rate anything out
  /// there reads. It runs off its own timer rather than off the step clock:
  /// six bursts on every 16th would arrive as one lump and read as swing on
  /// the receiving end.
  void _startClock() {
    _stopClock();
    final period = stepMsAt(_clock.bpm) / kMidiClockPulsesPerStep;
    _clockTimer = Timer.periodic(
      Duration(microseconds: (period * 1000).round()),
      (_) => _send(clockMessage),
    );
  }

  void _stopClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  /// The pad's LED on the desk, lit and unlit with the loop on screen. Without
  /// this the screen says one thing and the plastic says another.
  void _sendLoopState(int bank, int slot, {required bool on}) {
    _send(on
        ? noteOnMessage(bank: bank, slot: slot, velocity: 1)
        : noteOffMessage(bank: bank, slot: slot));
  }

  /// Which pads are being held down from the controller, so a released note
  /// silences the one it started rather than whatever is sounding now.
  final Set<int> _midiHeld = {};

  /// Points the instrument at a controller. Notes 36 upwards play the sixteen
  /// pads of the bank on screen — the layout every pad controller already
  /// ships with, so plugging one in works before anyone opens a settings
  /// screen.
  void listenToMidi(Stream<MidiEvent> events) {
    _midiSubscription?.cancel();
    _midiSubscription = events.listen(_onMidiEvent);
  }

  Future<void> stopListeningToMidi() async {
    await _midiSubscription?.cancel();
    _midiSubscription = null;
    _midiHeld.clear();
  }

  void _onMidiEvent(MidiEvent event) {
    switch (event) {
      case MidiNoteOn(:final note, :final velocity):
        final slot = padForNote(note);
        if (slot == null || padAt(slot).isEmpty) return;
        _midiHeld.add(slot);
        // A key played from a controller does the same as a finger: it sounds
        // the pad, writes into the pattern if the sequencer is listening, and
        // plays a degree when the grid is a keyboard.
        final source = _scaleSource;
        if (source != null && !padAt(source).isEmpty) {
          _fireOnce(_activeBank, source,
              velocity: velocityFromMidi(velocity),
              transpose: scaleSemitonesFor(slot));
        } else {
          if (sequencer.isWriting) sequencer.tap(padKey(_activeBank, slot));
          _fireOnce(_activeBank, slot, velocity: velocityFromMidi(velocity));
        }
        notifyListeners();

      case MidiNoteOff(:final note):
        final slot = padForNote(note);
        if (slot != null) _midiHeld.remove(slot);

      case MidiStart():
        if (!sequencer.isPlaying) toggleSequencerPlay();

      case MidiStop():
        if (sequencer.isPlaying) toggleSequencerPlay();

      case MidiControlChange(:final value) && final change:
        // Either this marries the control to the knob that is waiting, or it
        // moves whatever it was married to earlier. An unlearned control does
        // nothing at all, which is what keeps a controller's stray traffic —
        // modulation wheels, all-notes-off — out of the mix.
        final target = midiLearn.route(change);
        if (target != null) moveMidiTarget(target, positionFromMidi(value));

      case MidiClock():
        // Reading the clock means following someone else's tempo, which is a
        // bigger decision than this one.
        break;
    }
  }

  // ------------------------------------------------------------- scale mode

  /// The pad whose sound the grid is playing as a scale, or null when the
  /// grid is a kit again. Which pad it is belongs to the performance, not to
  /// the session: the scale and key are saved, the finger on them is not.
  int? _scaleSource;

  bool get isScaleOn => _scaleSource != null;
  int? get scaleSource => _scaleSource;

  Scale get scale => _session?.scale ?? Scale.pentatonicMinor;
  int get scaleRoot => _session?.root ?? 0;
  int get scaleOctave => _session?.octave ?? 0;

  /// Turns the grid into a keyboard playing [slot]'s sound. Passing the pad
  /// already sourcing it, or null, hands the grid back to the kit.
  void toggleScale(int? slot) {
    if (slot == null || slot == _scaleSource || padAt(slot).isEmpty) {
      _scaleSource = null;
    } else {
      _scaleSource = slot;
    }
    notifyListeners();
  }

  /// How far above the root the pad at [slot] plays right now.
  ChordVoicing get chord => _session?.chord ?? ChordVoicing.single;
  ArpMode get arp => _session?.arp ?? ArpMode.off;

  void setChord(ChordVoicing value) {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(chord: value);
    _touch();
    notifyListeners();
  }

  void setArp(ArpMode value) {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(arp: value);
    _touch();
    notifyListeners();
  }

  /// One key of the keyboard, played as however many notes the voicing asks
  /// for. The intervals are scale degrees, so the chord is in key by
  /// construction — the same promise the locked scale already makes.
  ///
  /// With the arpeggio on, the notes are spread over a beat instead of
  /// arriving together. A beat and not a step: an arpeggio you have to play
  /// in time with is a rhythm, and this one answers a single finger.
  void _playChord(int source, int slot) {
    final voicing = chord;
    final semitones = [
      for (final degree in voicing.degrees) scaleSemitonesFor(slot + degree),
    ];
    final order = arpSequence(semitones, arp);
    if (!arp.isOn || order.length < 2) {
      for (final transpose in order) {
        _fireOnce(_activeBank, source, transpose: transpose);
      }
      return;
    }
    final offsets = arpOffsets(order.length);
    for (var i = 0; i < order.length; i++) {
      _afterStepDelay(
        offsets[i] * kStepsPerBeat,
        () => _fireOnce(_activeBank, source, transpose: order[i]),
      );
    }
  }

  int scaleSemitonesFor(int slot) => semitonesForPad(
        slot,
        scale: scale,
        root: scaleRoot,
        octave: scaleOctave,
      );

  /// What that pad should be called while the grid is a keyboard.
  String scaleLabelFor(int slot) =>
      padLabel(scaleSemitonesFor(slot), root: scaleRoot);

  void setScale(Scale value) => _setKey(scale: value);

  void setScaleRoot(int value) => _setKey(root: value % 12);

  void setScaleOctave(int value) =>
      _setKey(octave: value.clamp(kScaleOctaves.first, kScaleOctaves.last));

  void _setKey({Scale? scale, int? root, int? octave}) {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(scale: scale, root: root, octave: octave);
    _touch();
    notifyListeners();
  }

  /// Whether this pad is silent right now. The rule itself lives in the
  /// domain, next to [PadConfig], because it is the half worth testing.
  bool _isSilenced(int bank, int slot, PadConfig pad) =>
      isPadSilenced(pad: pad, key: padKey(bank, slot), soloKey: _soloKey);

  /// Starts a pad looping. [fireNow] is for the one caller that is already
  /// standing on the downbeat — a scene coming in on the bar line. The clock
  /// fires the entries it had when the step began, so one added *during* that
  /// step would sit silent until the next boundary, a whole bar of nothing.
  /// Voices that have been layered over and are ringing out on their own.
  /// Only PARAR reaches them; they are not any pad's current voice any more.
  final Set<SoundHandle> _parked = {};

  void _park(SoundHandle handle) {
    // Swept rather than tracked: a layering pad can leave dozens behind in a
    // minute, and asking the engine about each one on every hit would put a
    // pile of calls across the boundary in the middle of a roll.
    if (_parked.length > kMaxVoices) {
      _parked.removeWhere((h) => !_engine.isVoiceAlive(h));
    }
    _parked.add(handle);
  }

  /// Silences the pads that cannot sound alongside this one. Loops are left
  /// alone on purpose: a loop is a decision to keep something running, and a
  /// tap on its neighbour is not a decision to undo it.
  void _chokeFor(int bank, int slot, PadConfig pad) {
    if (pad.chokeGroup == kNoChokeGroup) return;
    final victims = chokeVictims(
      firingKey: padKey(bank, slot),
      group: pad.chokeGroup,
      sounding: _soundingGroups(),
    );
    if (victims.isEmpty) return;
    for (final hitKey in _hits.keys.toList()) {
      if (!victims.contains(_padOf(hitKey))) continue;
      final handle = _hits.remove(hitKey);
      if (handle != null) _engine.stopHandle(handle);
    }
  }

  /// Which pads are ringing right now and what group each belongs to. Keyed
  /// by the pad, not by the voice: the same pad played as two notes of a
  /// scale is still one pad, and chokes as one.
  Map<String, int> _soundingGroups() {
    final session = _session;
    if (session == null) return const {};
    final out = <String, int>{};
    for (final hitKey in _hits.keys) {
      final key = _padOf(hitKey);
      final target = parsePadKey(key);
      if (target == null) continue;
      final group = session.banks[target.bank].pads[target.slot].chokeGroup;
      if (group != kNoChokeGroup) out[key] = group;
    }
    return out;
  }

  /// The pad behind a voice key: the transposed ones carry '@n' on the end.
  String _padOf(String hitKey) => hitKey.split('@').first;

  void _startLoop(int bank, int slot, {bool fireNow = false}) {
    final key = padKey(bank, slot);
    if (_loops.containsKey(key)) return;
    final pad = _session!.banks[bank].pads[slot];
    final sound = _library.byId(pad.soundId);
    if (sound == null) return;

    if (pad.synced) {
      // Retriggered by the clock so it lands with the other synced layers.
      // The clock decides when: if something is already running, this one
      // waits for the downbeat instead of starting under the finger.
      _loops[key] = ActiveLoop(bank: bank, slot: slot, synced: true);
      _clock.add(key, pad.loopSteps, alignTo: _launchOn(pad.loopSteps));
      if (fireNow) _fireOnce(bank, slot);
      _sendLoopState(bank, slot, on: true);
    } else {
      // Free loop: SoLoud repeats it natively at its own natural length.
      final handle = _engine.fire(
        sound,
        volume: _isSilenced(bank, slot, pad) ? 0 : pad.volume * sound.volume,
        rate: sound.playbackRate * _rateFor(pad),
        looping: true,
        pan: pad.pan,
      );
      _loops[key] = ActiveLoop(bank: bank, slot: slot, handle: handle, synced: false);
      _sendLoopState(bank, slot, on: true);
    }
  }

  /// The boundary a loop waits for before coming in: its own length, but never
  /// more than a bar. Waiting two whole bars for a pad to answer reads as
  /// broken, and a bar line is a boundary every other length shares anyway.
  int _launchOn(int steps) => math.min(steps, kStepsPerBar);

  void _onSyncedStep(String key) {
    if (key == kMetronomeId) {
      _fireClick(accent: isDownbeat(_clock.stepIndex));
      return;
    }
    if (key == kExportKey) {
      _clock.remove(kExportKey);
      _barLine?.complete();
      _barLine = null;
      return;
    }
    if (key == kSceneKey) {
      _applyScene();
      return;
    }
    if (key == kSequencerKey) {
      // The courtesy bar is audible whether or not the metronome is on: a
      // count you cannot hear is not a count. Only on the beats, so it reads
      // as four clicks and not as sixteen.
      // Skipped when the metronome is already running: it is clicking these
      // same beats, and two clicks on one beat read as a stutter.
      if (sequencer.isCountingIn &&
          !_metronome &&
          _clock.stepIndex % kStepsPerBeat == 0) {
        _fireClick(accent: isDownbeat(_clock.stepIndex));
      }
      sequencer.tick();
      // Writing by hand does not ride the clock; only the count-in and
      // playback do, so the entry goes as soon as neither is running.
      if (!sequencer.isPlaying && !sequencer.isCountingIn) {
        _clock.remove(kSequencerKey);
      }
      return;
    }
    final loop = _loops[key];
    if (loop == null) return;
    _fireOnce(loop.bank, loop.slot);
  }

  // ------------------------------------------------------------ sequencer

  /// Timers holding back nudged notes and the tail of a ratchet. Cancelled
  /// whenever the transport stops, so nothing straggles into the silence.
  final Set<Timer> _stepTimers = {};

  void _cancelStepTimers() {
    for (final timer in _stepTimers) {
      timer.cancel();
    }
    _stepTimers.clear();
  }

  void _afterStepDelay(double offsetSteps, void Function() fire) {
    if (offsetSteps <= 0) {
      fire();
      return;
    }
    late final Timer timer;
    timer = Timer(
      Duration(microseconds: (offsetSteps * _clock.stepMs * 1000).round()),
      () {
        _stepTimers.remove(timer);
        fire();
      },
    );
    _stepTimers.add(timer);
  }

  /// Plays one step as the sequencer wrote it: after its nudge, at its
  /// strength, subdivided into its ratchet. A rest arrives here as an empty
  /// set and correctly does nothing.
  void _fireNotes(StepPlay play) {
    if (play.notes.isEmpty) return;

    void fire(String note) {
      final target = parsePadKey(note);
      if (target == null) return;
      _fireOnce(target.bank, target.slot, velocity: play.velocity);
    }

    // With the arpeggio on, a step holding several pads stops being a chord
    // and becomes a figure: the notes are dealt out across the step in the
    // chosen order. It is the same set of notes the sequencer already knew
    // how to stack — the chord window of the live REC is what puts them
    // there — read the other way round.
    if (arp.isOn && play.notes.length > 1) {
      final order = arpSequence(play.notes.toList()..sort(), arp);
      final offsets = arpOffsets(order.length);
      for (var i = 0; i < order.length; i++) {
        _afterStepDelay(play.offsetSteps + offsets[i], () => fire(order[i]));
      }
      return;
    }

    void fireAll() {
      for (final note in play.notes) {
        fire(note);
      }
    }

    _afterStepDelay(play.offsetSteps, fireAll);
    // The extra hits of a ratchet split the step evenly: two hits are
    // thirty-seconds, four are sixty-fourths of a bar.
    for (var hit = 1; hit < play.ratchet; hit++) {
      _afterStepDelay(play.offsetSteps + hit / play.ratchet, fireAll);
    }
  }

  void _onPatternsChanged() {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(
      patterns: sequencer.patterns,
      activePattern: sequencer.patternIndex,
      chainLength: sequencer.chainLength,
      song: sequencer.song,
      songMode: sequencer.songMode,
    );
    _touch();
  }

  /// Wipes the pattern on screen, with a step back first: it is sixteen steps
  /// of work and there is no other way to get them again.
  void clearPattern() {
    _remember('borrar el patrón');
    sequencer.clearPattern();
    notifyListeners();
  }

  /// Bars in the chain: 1 loops the pattern on screen, N walks P1..PN.
  void setChainLength(int bars) {
    sequencer.chainLength = bars;
    _onPatternsChanged();
    notifyListeners();
  }

  void toggleSequencer() {
    _cancelStepTimers();
    sequencer.toggleOn();
    if (!sequencer.isOn) _clock.remove(kSequencerKey);
    notifyListeners();
  }

  /// Play and stop for the pattern. The clock entry is what makes it run, so
  /// it is added and removed here rather than inside the sequencer.
  void toggleSequencerPlay() {
    _cancelStepTimers();
    sequencer.togglePlay();
    if (sequencer.isPlaying) {
      _send(startMessage);
      _startClock();
    } else {
      _send(stopMessage);
      _stopClock();
    }
    if (sequencer.isPlaying) {
      // It ticks every step, but its first step waits for a bar line: that is
      // what keeps the pattern and the running loops on the same downbeat.
      _clock.add(kSequencerKey, 1, alignTo: kPatternSteps);
    } else {
      _clock.remove(kSequencerKey);
    }
    notifyListeners();
  }

  /// Arms writing behind a bar of count-in. The clock has to be running for
  /// that bar to go by, so the entry is added here and dropped again the
  /// moment the count is over.
  Future<void> toggleSequencerRecord() async {
    final arming = !sequencer.isRecording && !sequencer.isCountingIn;
    if (arming) await _ensureClick();
    sequencer.toggleRecord();
    if (sequencer.isCountingIn) {
      _clock.add(kSequencerKey, 1, alignTo: kPatternSteps);
    } else if (!sequencer.isPlaying) {
      _clock.remove(kSequencerKey);
    }
    notifyListeners();
  }

  /// How hard the step being edited hits, and how to change it.
  double get editingVelocity => sequencer.editingVelocity;

  void setStepVelocity(double velocity) {
    sequencer.setStepVelocity(velocity);
    notifyListeners();
  }

  void setStepProbability(double value) {
    sequencer.setStepProbability(value);
    notifyListeners();
  }

  void setStepNudge(double value) {
    sequencer.setStepNudge(value);
    notifyListeners();
  }

  void setStepRatchet(int value) {
    sequencer.setStepRatchet(value);
    notifyListeners();
  }

  /// Puts a snapshot's contents back on the session that is open, and brings
  /// the instrument with them: the sequencer reloads its patterns, the clock
  /// takes the restored tempo and swing.
  ///
  /// It goes through undo like any other destructive edit, so restoring the
  /// wrong point is one tap away from being undone.
  Future<void> restore(SavePoint point) async {
    final session = _session;
    if (session == null) return;

    _remember('restaurar «${point.name}»');
    await stopAllLoops();
    _session = point.restoreOnto(session);
    sequencer.load(
      _session!.patterns,
      _session!.activePattern,
      chainLength: _session!.chainLength,
      song: _session!.song,
      songMode: _session!.songMode,
    );
    _clock.setBpm(_session!.bpm);
    _clock.swing = _session!.swing;
    _scaleSource = null;
    await _preloadSession();
    _touch();
    notifyListeners();
  }


  // ---------------------------------------------------------------- scenes

  /// The scene that is up, and the one waiting for the bar line. A scene
  /// never lands under the finger: it comes in on the downbeat like every
  /// other synced thing in this instrument, which is what lets it be fired
  /// mid-bar without breaking the groove.
  int? _activeScene;
  int? _pendingScene;

  int? get activeScene => _activeScene;
  int? get pendingScene => _pendingScene;

  List<Scene> get scenes => _session?.scenes ?? emptyScenes();

  Scene sceneAt(int index) => scenes[index];

  /// Remembers what is looping right now, and which pattern went with it.
  /// Overwrites without asking: the strip shows how full each scene is, so
  /// there is no such thing as capturing over something you could not see.
  void captureScene(int index) {
    final session = _session;
    if (session == null) return;
    _remember('guardar la escena ${index + 1}');
    _session = session.withScene(
      index,
      Scene.capture(loops: _loops.keys.toSet(), pattern: sequencer.patternIndex),
    );
    // A captured scene is the one that is playing, by definition.
    _activeScene = index;
    _touch();
    notifyListeners();
  }

  void clearScene(int index) {
    final session = _session;
    if (session == null) return;
    if (session.scenes[index].isEmpty) return;
    _remember('vaciar la escena ${index + 1}');
    _session = session.withScene(index, const Scene.empty());
    if (_activeScene == index) _activeScene = null;
    if (_pendingScene == index) _pendingScene = null;
    _touch();
    notifyListeners();
  }

  /// Queues a scene. It goes in on the next bar line — or at once when
  /// nothing is running, because then this launch *is* the downbeat.
  ///
  /// It rides the clock like a loop does rather than a timer of its own: one
  /// grid decides when things happen in this app, and a scene that came in on
  /// its own schedule would arrive between two beats of the one that matters.
  void launchScene(int index) {
    if (_session == null) return;
    if (sceneAt(index).isEmpty) return;
    _pendingScene = index;
    // Already queued: the last press wins, so a change of mind costs one tap
    // instead of a wait.
    if (!_clock.contains(kSceneKey)) {
      _clock.add(kSceneKey, kStepsPerBar, alignTo: kStepsPerBar);
    }
    notifyListeners();
  }

  /// The bar line arrived. What starts, what stops and what is left alone is
  /// worked out in the domain; this is only the wiring.
  void _applyScene() {
    final index = _pendingScene;
    _pendingScene = null;
    if (index == null) {
      _clock.remove(kSceneKey);
      return;
    }
    final scene = sceneAt(index);
    final change = sceneTransition(playing: _loops.keys.toSet(), scene: scene);

    // Starting before stopping, always: emptying the clock would stop it, and
    // the loops coming in would then define a new downbeat of their own
    // instead of landing on the one the music is already on.
    for (final key in change.start) {
      final target = parsePadKey(key);
      if (target != null) _startLoop(target.bank, target.slot, fireNow: true);
    }
    for (final key in change.stop) {
      _stopLoop(key);
    }

    // The pattern travels with the scene only when nobody else owns the
    // running order. With a chain or a song up, they do — and a scene that
    // yanked the pattern out from under a song would be two things fighting
    // over the same bar.
    if (!sequencer.isFollowingSong && sequencer.chainLength == 1) {
      sequencer.selectPattern(scene.pattern);
    }

    _activeScene = index;
    _clock.remove(kSceneKey);
    notifyListeners();
  }

  // ------------------------------------------------------------------ song

  /// The running order, and whether it is the one in charge.
  Song get song => sequencer.song;
  bool get isSongMode => sequencer.songMode;

  void setSong(Song value) {
    sequencer.setSong(value);
    notifyListeners();
  }

  /// Adds the pattern on screen to the end of the song — the way a song gets
  /// written, one bar at a time, from the bar you are looking at.
  void appendToSong({int repeats = 1}) {
    setSong(song.appended(
      SongStep(pattern: sequencer.patternIndex, repeats: repeats),
    ));
  }

  void toggleSongMode() {
    sequencer.songMode = !sequencer.songMode;
    notifyListeners();
  }

  // ------------------------------------------------------------- clipboard

  /// One pad and one pattern, held to be put down somewhere else. They are
  /// performance state: copying is for building the next bar, not something a
  /// session needs to remember overnight.
  PadConfig? _padClipboard;
  Pattern? _patternClipboard;

  bool get hasPadCopied => _padClipboard != null;
  bool get hasPatternCopied => _patternClipboard != null;

  /// Lifts the pad — sound and settings both — without arming anything.
  /// Where it lands is the screen's business.
  void copyPad(int slot) {
    final pad = padAt(slot);
    if (pad.isEmpty) return;
    _padClipboard = pad;
    notifyListeners();
  }

  Future<void> pastePad(int slot) async {
    final pad = _padClipboard;
    if (pad == null) return;
    _remember('pegar un pad');
    await updatePad(_activeBank, slot, pad, remember: false);
  }

  void copyPattern() {
    _patternClipboard = sequencer.pattern;
    notifyListeners();
  }

  /// Drops the copied pattern onto whichever one is on screen now. The
  /// clipboard survives, so one bar can seed several.
  void pastePattern() {
    final copied = _patternClipboard;
    if (copied == null) return;
    _remember('pegar el patrón');
    sequencer.replacePattern(copied);
    notifyListeners();
  }

  // --------------------------------------------------------------- swing

  double get swing => _session?.swing ?? kSwingDefault;

  /// Swing belongs to the session, like the tempo: it is part of how the
  /// pattern is meant to be felt, not a knob position that resets.
  void setSwing(double value) {
    final session = _session;
    if (session == null) return;
    final next = value.clamp(kSwingMin, kSwingMax);
    _clock.swing = next;
    _session = session.copyWith(swing: next);
    _touch();
    notifyListeners();
  }

  void selectPattern(int index) {
    sequencer.selectPattern(index);
    _onPatternsChanged();
    notifyListeners();
  }

  // ------------------------------------------------------------------- roll

  bool _rollHeld = false;

  /// Which of [kRollDivisions] the roll repeats at. Sixteenths by default —
  /// the fill everyone reaches for first — with eighths one tap away.
  int _rollDivisionIndex = kRollDivisions.indexOf(1);

  bool get isRolling => _rollHeld;

  /// The roll's division in 16th notes per hit.
  int get rollSteps => kRollDivisions[_rollDivisionIndex];

  /// How it reads on the button: '1/8' or '1/16'.
  String get rollLabel => rollDivisionLabel(rollSteps);

  /// Steps through the divisions. Changing it mid-roll retimes the fill on the
  /// spot, which is the whole point of having two.
  void cycleRollDivision() {
    _rollDivisionIndex = (_rollDivisionIndex + 1) % kRollDivisions.length;
    if (_rollHeld && _rollTarget != null) {
      _rollOn(_rollTarget!.bank, _rollTarget!.slot);
    }
    notifyListeners();
  }

  /// The pad the roll is pointing at, so a division change can retime it
  /// without waiting for the finger to move.
  ({int bank, int slot})? _rollTarget;

  /// Hold ROLL and touch pads: each pad touched repeats in 16th notes until
  /// the button is let go. Holding it with a pad already selected rolls that
  /// pad straight away, so the one-handed habit keeps working too.
  void startRoll() {
    if (_rollHeld) return;
    _rollHeld = true;
    final slot = _selectedSlot;
    if (slot != null && !padAt(slot).isEmpty) {
      _rollOn(_activeBank, slot);
    }
    notifyListeners();
  }

  void stopRoll() {
    if (!_rollHeld) return;
    _rollHeld = false;
    _rollTarget = null;
    _midiSubscription?.cancel();
    _cancelStepTimers();
    _rollTimer?.cancel();
    _rollTimer = null;
    notifyListeners();
  }

  /// Points the roll at a pad. Touching another pad mid-roll retargets it —
  /// that is how a fill walks across the kit.
  void _rollOn(int bank, int slot) {
    _rollTimer?.cancel();
    _rollTarget = (bank: bank, slot: slot);
    final interval = rollIntervalFor(bpm: bpm, steps: rollSteps);
    _fireOnce(bank, slot);
    _rollTimer = Timer.periodic(interval, (_) => _fireOnce(bank, slot));
  }

  // -------------------------------------------------------------- metronome

  bool get isMetronomeOn => _metronome;

  /// The click runs on the same clock as the synced loops, so it never drifts
  /// away from them.
  Future<void> toggleMetronome() async {
    if (_metronome) {
      _metronome = false;
      _clock.remove(kMetronomeId);
      notifyListeners();
      return;
    }

    await _ensureClick();
    _metronome = true;
    _clock.add(kMetronomeId, kStepsPerBeat);
    notifyListeners();
  }

  /// Loads the click if it has never been needed. Both the metronome and the
  /// count-in go through here.
  Future<void> _ensureClick() async {
    final click = _click ??= await ensureMetronomeSound(Storage.instance);
    if (!_engine.isLoaded(click.id)) {
      await _engine.preload(
          click, Storage.instance.soundFile(click.fileName).path);
    }
  }

  /// The one of the bar comes a fifth higher and a little louder. One sound
  /// file, two pitches — the click is a 50 ms sine, and playing it faster is
  /// exactly how a drum machine has always made its accent.
  void _fireClick({bool accent = false}) {
    final click = _click;
    if (click == null) return;
    // Dry: the click is not music. It would otherwise ride the percussion
    // bus, which means filtering the drums would filter the metronome you
    // are using to hear whether the drums are in time.
    _engine.fire(
      click,
      volume: accent ? kMetronomeAccentVolume : kMetronomeVolume,
      rate: accent ? kMetronomeAccentRate : 1.0,
      dry: true,
    );
  }

  Future<void> _stopLoop(String key) async {
    final loop = _loops.remove(key);
    if (loop == null) return;
    _sendLoopState(loop.bank, loop.slot, on: false);
    _clock.remove(key);
    final handle = loop.handle;
    if (handle != null) {
      await _engine.stopHandle(handle);
    }
  }

  /// The panic button: every loop off and every hit still ringing cut short.
  Future<void> stopAllLoops() async {
    stopRoll();
    // Silence is not a scene. Leaving one lit would say something is playing
    // when the instrument has just been emptied.
    _activeScene = null;
    _pendingScene = null;
    for (final handle in _hits.values) {
      await _engine.stopHandle(handle);
    }
    _hits.clear();
    for (final handle in _parked) {
      await _engine.stopHandle(handle);
    }
    _parked.clear();

    final keys = _loops.keys.toList();
    for (final key in keys) {
      await _stopLoop(key);
    }
    _clock.clear();
    // Stopping the music does not stop the click: it is a tool, not a layer.
    // The sequencer goes back first so it lands on the new downbeat instead
    // of sitting out the bar waiting for one.
    if (sequencer.isPlaying) {
      _clock.add(kSequencerKey, 1, alignTo: kPatternSteps);
    }
    if (_metronome) _clock.add(kMetronomeId, kStepsPerBeat);
    notifyListeners();
  }

  // ------------------------------------------------------------------- take

  Future<void> startMixdown() async {
    await mixdown.start();
    notifyListeners();
  }

  /// Stops the performance capture and returns the finished file, or null
  /// when nothing was written.
  Future<File?> stopMixdown() async {
    final file = await mixdown.stop();
    // A take that just landed is the moment the number moved most.
    await refreshFreeSpace();
    notifyListeners();
    return file;
  }

  /// Long press target: replaces the pad wholesale.
  Future<void> updatePad(int bank, int slot, PadConfig pad,
      {bool remember = true}) async {
    final session = _session;
    if (session == null) return;

    // Only when the sound itself changes hands. Volume and pitch arrive here
    // too and are not worth a step back.
    final before = session.padAt(bank, slot);
    if (remember && before.soundId != pad.soundId) {
      _remember(pad.isEmpty ? 'vaciar el pad' : 'cambiar el sonido del pad');
    }

    final wasLooping = isLooping(bank, slot);
    if (wasLooping) await _stopLoop(padKey(bank, slot));

    _session = session.withPad(bank, slot, pad);
    final sound = _library.byId(pad.soundId);
    if (sound != null && !_engine.isLoaded(sound.id)) {
      await _engine.preload(sound, _library.pathFor(sound));
    }
    _touch();
    notifyListeners();
  }

  /// Empties every pad holding [soundId]. Called when a sound is deleted from
  /// the library, so no pad is left pointing at a file that no longer exists.
  Future<void> clearPadsUsing(String soundId) async {
    final session = _session;
    if (session == null) return;

    for (var bank = 0; bank < session.banks.length; bank++) {
      final pads = session.banks[bank].pads;
      for (var slot = 0; slot < pads.length; slot++) {
        if (pads[slot].soundId != soundId) continue;
        await _stopLoop(padKey(bank, slot));
        _session = _session!
            .withPad(bank, slot, pads[slot].copyWith(clearSound: true));
      }
    }
    await _engine.unload(soundId);
    // The file is gone. Any snapshot taken before this could put a pad back
    // on a sound that no longer exists, so the history goes with it.
    _undo.clear();
    _touch();
    notifyListeners();
  }

  /// Turns a sound around: a new file written backwards, and every pad
  /// holding it now playing that one.
  /// Transposes a sound for real — the pitch moves, the length does not —
  /// and puts every pad holding it on the new file.
  Future<Sound?> pitchSound(Sound sound, int semitones) =>
      _rerender(sound, () => _library.pitchedCopy(sound, semitones));

  /// Stretches a sound to the session's tempo: the length moves, the pitch
  /// does not. [fromBpm] is what the sound is running at now.
  Future<Sound?> stretchSound(Sound sound, double fromBpm) => _rerender(
        sound,
        () => _library.stretchedCopy(
          sound,
          stretchRatioFor(fromBpm: fromBpm, toBpm: bpm.toDouble()),
        ),
      );

  Future<Sound?> reverseSound(Sound sound) =>
      _rerender(sound, () => _library.reversedCopy(sound));

  /// The shared half of every rendering that rewrites a sound's file: stop
  /// what is playing it, run the rendering, and load the new file underneath.
  ///
  /// The loops go first. The source is disposed and loaded again below them,
  /// and a voice still running on the old one would be playing memory that
  /// has just been handed back.
  Future<Sound?> _rerender(
    Sound sound,
    Future<Sound?> Function() render,
  ) async {
    final session = _session;
    if (session == null) return null;

    for (var bank = 0; bank < session.banks.length; bank++) {
      final pads = session.banks[bank].pads;
      for (var slot = 0; slot < pads.length; slot++) {
        if (pads[slot].soundId == sound.id) {
          await _stopLoop(padKey(bank, slot));
        }
      }
    }

    final next = await render();
    if (next == null) return null;

    await _engine.unload(next.id);
    await _engine.preload(next, _library.pathFor(next));
    await refreshFreeSpace();
    notifyListeners();
    return next;
  }

  // -------------------------------------------------------- espacio libre

  final DiskSpace _disk = DiskSpace();
  int? _freeBytes;

  /// True when the device is down to its last few hundred megabytes and a
  /// long take could fail halfway. Never true when the platform did not
  /// answer: an invented warning is one that gets ignored.
  bool get isSpaceLow => isSpaceLowFor(_freeBytes);

  /// What is left, written the way a person reads it, or null when unknown.
  String? get freeSpaceLabel => freeSpaceLabelFor(_freeBytes);

  /// Asks the platform how much room is left. Called when a session opens and
  /// after anything that writes audio, which is often enough to be honest and
  /// rare enough to cost nothing.
  Future<void> refreshFreeSpace() async {
    final free = await _disk.freeBytes();
    if (free == _freeBytes) return;
    _freeBytes = free;
    notifyListeners();
  }

  // -------------------------------------------------------------- stems

  /// How far along a stem export is: which family is being recorded and how
  /// many are left. Null when nothing is being exported.
  ({SoundFamily family, int done, int total})? _stemProgress;

  ({SoundFamily family, int done, int total})? get stemProgress =>
      _stemProgress;

  /// Records one file per family, one after the other.
  ///
  /// The engine hands out a single tap of the mixer — that is why exporting,
  /// resampling and the rescue all share one — so four tracks cannot be
  /// recorded at once. They are recorded in four passes with the other
  /// families turned down, and every pass starts on a bar line so the four
  /// files line up when they are dropped into anything else.
  ///
  /// Whatever is looping keeps looping throughout: this records the
  /// performance as it stands, it does not render it offline.
  Future<List<File>> exportStems({int bars = 4}) async {
    if (_stemProgress != null || mixdown.isRecording) return const [];
    final families = SoundFamily.values;
    final files = <File>[];

    for (var i = 0; i < families.length; i++) {
      final family = families[i];
      _stemProgress = (family: family, done: i, total: families.length);
      notifyListeners();

      _engine.buses.soloFamily(family);
      await _awaitBarLine();
      await mixdown.start(name: _stemName(family));
      await Future<void>.delayed(_barsDuration(bars));
      final file = await mixdown.stop();
      if (file != null) files.add(file);
    }

    _engine.buses.soloFamily(null);
    _stemProgress = null;
    notifyListeners();
    return files;
  }

  Duration _barsDuration(int bars) => Duration(
        microseconds:
            (_clock.stepMs * kStepsPerBar * bars * 1000).round(),
      );

  String _stemName(SoundFamily family) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'pista_${family.name}_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.wav';
  }

  /// Waits for the next downbeat of the shared grid, or returns at once when
  /// nothing is running — then this moment *is* the downbeat.
  Future<void> _awaitBarLine() {
    if (!_clock.isRunning) return Future<void>.value();
    final waiting = Completer<void>();
    _barLine = waiting;
    _clock.add(kExportKey, kStepsPerBar, alignTo: kStepsPerBar);
    return waiting.future;
  }

  Completer<void>? _barLine;

  // ------------------------------------------------------------- synth

  /// The id the auditioned patch always uses. One preview at a time: the
  /// previous is unloaded before the next is rendered, so turning a knob
  /// cannot leave a pile of one-off sources behind in the engine.
  static const String _patchPreviewId = '_patch';

  /// Renders a patch and plays it, keeping nothing. Dry on purpose — the
  /// family buses colour sounds that belong to a family, and this one does
  /// not belong to anything yet.
  Future<void> previewPatch(SynthPatch patch) async {
    final sound = _patchSound(patch, id: _patchPreviewId, fileName: 'synth.wav');
    final file = Storage.instance.synthScratch;
    await file.writeAsBytes(_renderPatchBytes(patch));
    await _engine.unload(_patchPreviewId);
    await _engine.preload(sound, file.path);
    _engine.fire(sound, volume: 1, rate: 1, dry: true);
  }

  /// Keeps it: the patch is rendered to a file of its own and registered in
  /// the library, where it becomes an ordinary sound — it can be trimmed,
  /// chopped, reversed and put on a pad like anything else.
  Future<Sound> createFromPatch(SynthPatch patch, {required String name}) async {
    final bytes = _renderPatchBytes(patch);
    final fileName = '${_uuid.v4()}.wav';
    await Storage.instance.soundFile(fileName).writeAsBytes(bytes);

    final sound = _patchSound(
      patch,
      id: _uuid.v4(),
      fileName: fileName,
      name: name,
      sizeBytes: bytes.length,
    );
    await _library.add(sound);
    await _engine.preload(sound, _library.pathFor(sound));
    notifyListeners();
    return sound;
  }

  List<int> _renderPatchBytes(SynthPatch patch) =>
      encodeWav(renderPatch(patch, kSampleRate), sampleRate: kSampleRate);

  Sound _patchSound(
    SynthPatch patch, {
    required String id,
    required String fileName,
    String name = 'Sintetizado',
    int sizeBytes = 0,
  }) =>
      Sound(
        id: id,
        name: name,
        // Tone by default: what comes out of an oscillator is pitched, and
        // the family can be changed in the sheet like any other sound's.
        family: SoundFamily.tone,
        fileName: fileName,
        origin: SoundOrigin.recorded,
        durationMs: (patch.seconds * 1000).round(),
        sizeBytes: sizeBytes,
      );

  void toggleMute(int slot) {
    final pad = padAt(slot);
    final next = pad.copyWith(muted: !pad.muted);
    _applyPadLive(_activeBank, slot, next);
  }

  /// Solo: this pad keeps sounding, every other one drops to silence.
  ///
  /// Nothing is written to any pad. Soloing the pad that is already soloed
  /// lifts it, and every mute the player set by hand is exactly where they
  /// left it — which was not true when solo was implemented by muting the
  /// other sixty-three pads.
  void toggleSolo(int slot) {
    final key = padKey(_activeBank, slot);
    _soloKey = _soloKey == key ? null : key;
    _refreshLoopVolumes();
    notifyListeners();
  }

  /// Lifts the solo whichever pad holds it, including one in a bank that is
  /// not on screen. Every mute comes back exactly as it was.
  void clearSolo() {
    if (_soloKey == null) return;
    _soloKey = null;
    _refreshLoopVolumes();
    notifyListeners();
  }

  /// Re-levels every loop already sounding. Called when something outside the
  /// pads changes what should be heard — today only solo.
  void _refreshLoopVolumes() {
    final session = _session;
    if (session == null) return;
    for (final loop in _loops.values) {
      final handle = loop.handle;
      if (handle == null) continue;
      final pad = session.banks[loop.bank].pads[loop.slot];
      final sound = _library.byId(pad.soundId);
      if (sound == null) continue;
      _engine.setHandleVolume(
        handle,
        _isSilenced(loop.bank, loop.slot, pad) ? 0 : pad.volume * sound.volume,
      );
    }
  }

  /// Applies a pad change and reflects it on any handle already sounding, so a
  /// mute or a volume move is heard immediately rather than on the next hit.
  void _applyPadLive(int bank, int slot, PadConfig pad) {
    final session = _session;
    if (session == null) return;
    _session = session.withPad(bank, slot, pad);

    final loop = _loops[padKey(bank, slot)];
    final sound = _library.byId(pad.soundId);
    if (loop?.handle != null && sound != null) {
      _engine.setHandleVolume(
        loop!.handle!,
        _isSilenced(bank, slot, pad) ? 0 : pad.volume * sound.volume,
      );
      // Moving a running loop across the field is the point of the knob.
      _engine.setHandlePan(loop.handle!, pad.pan);
    }
    _touch();
    notifyListeners();
  }

  void setPadVolume(int slot, double volume) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(volume: volume));

  void setPadPan(int slot, double pan) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(pan: pan));

  void setPadSemitones(int slot, int semitones) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(semitones: semitones));

  /// Switches a pad's loop on or off from a control other than the pad
  /// itself — the surface knob, so the finger playing the grid is not the
  /// only way to stop a layer.
  void setPadLooping(int slot, bool looping) {
    if (looping) {
      _startLoop(_activeBank, slot);
    } else {
      _stopLoop(padKey(_activeBank, slot));
    }
    notifyListeners();
  }

  /// Loop length in 16th notes. A running synced loop picks it up on its next
  /// pass rather than jumping, so the change is never heard as a stumble.
  void setPadLoopSteps(int slot, int steps) {
    final key = padKey(_activeBank, slot);
    final wasSynced = _loops[key]?.synced ?? false;
    if (wasSynced) _clock.remove(key);
    _applyPadLive(_activeBank, slot, padAt(slot).copyWith(loopSteps: steps));
    if (wasSynced) _clock.add(key, steps, alignTo: _launchOn(steps));
  }

  /// Changing the sync of a running loop restarts it, this time on (or off)
  /// the grid. Everything else about the pad stays as it was.
  void setPadSynced(int slot, bool synced) {
    final key = padKey(_activeBank, slot);
    final wasLooping = _loops.containsKey(key);
    if (wasLooping) _stopLoop(key);
    _applyPadLive(_activeBank, slot, padAt(slot).copyWith(synced: synced));
    if (wasLooping) _startLoop(_activeBank, slot);
  }

  @override
  void dispose() {
    _stopClock();
    _rollTimer?.cancel();
    _saveTimer?.cancel();
    final session = _session;
    if (session != null) _store.save(session);
    _clock.dispose();
    super.dispose();
  }
}
