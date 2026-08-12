import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'dart:io';

import '../audio/audio_engine.dart';
import '../audio/master_fx.dart';
import '../audio/mixdown_recorder.dart';
import '../audio/tempo_clock.dart';
import '../core/constants.dart';
import '../data/metronome.dart';
import '../data/session_store.dart';
import '../data/sound_library.dart';
import '../data/storage.dart';
import 'sequencer.dart';
import '../domain/pad_config.dart';
import '../domain/session.dart';
import '../domain/sound.dart';

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

  /// Recording the performance — the mixer output, never the microphone — so
  /// it can run while the grid is being played.
  late final MixdownRecorder mixdown =
      MixdownRecorder(engine: _engine, storage: Storage.instance);

  Session? _session;
  int _activeBank = 0;
  int? _selectedSlot;
  bool _soloActive = false;
  final Map<String, ActiveLoop> _loops = {};

  /// The last one-shot fired by each pad, kept so the next tap can cut it.
  final Map<String, SoundHandle> _hits = {};

  Timer? _rollTimer;
  bool _metronome = false;
  Sound? _click;

  Session? get session => _session;
  int get activeBank => _activeBank;
  int? get selectedSlot => _selectedSlot;
  int get bpm => _session?.bpm ?? kDefaultBpm;
  bool get isSoloActive => _soloActive;
  Map<String, ActiveLoop> get loops => Map.unmodifiable(_loops);

  Bank get currentBank => _session!.banks[_activeBank];

  PadConfig padAt(int slot) => currentBank.pads[slot];

  Sound? soundFor(PadConfig pad) => _library.byId(pad.soundId);

  /// Every sound available to drop on a pad.
  List<Sound> get librarySounds => _library.sounds;

  /// Master volume and the performance effects, exposed for the surface.
  MasterFx get fx => _engine.fx;

  /// Plays a sound once to audition it, loading it if it never reached a pad.
  Future<void> preview(Sound sound) async {
    if (!_engine.isLoaded(sound.id)) {
      await _engine.preload(sound, _library.pathFor(sound));
    }
    _engine.fire(sound, volume: sound.volume, rate: sound.playbackRate);
  }

  bool isLooping(int bank, int slot) => _loops.containsKey(padKey(bank, slot));

  /// True when a bank other than the visible one has loops running, so its
  /// tab can light up.
  bool bankHasLoops(int bank) =>
      _loops.values.any((loop) => loop.bank == bank);

  double loopProgress(int bank, int slot) {
    final key = padKey(bank, slot);
    if (!_clock.contains(key)) return 0;
    return _clock.progressFor(key);
  }

  // ---------------------------------------------------------------- session

  Future<void> open(Session session) async {
    await stopAllLoops();
    _session = session;
    _clock.setBpm(session.bpm);
    _activeBank = 0;
    _selectedSlot = null;
    sequencer.load(
      session.patterns,
      session.activePattern,
      chainLength: session.chainLength,
    );
    await _preloadSession();
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

  void selectBank(int index) {
    if (index == _activeBank) return;
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
    _touch();
    notifyListeners();
  }

  // ------------------------------------------------------------------ pads

  /// A tap fires the pad and points the control surface at it. Tap again and
  /// it fires again, so hitting the pad in a rhythm plays that rhythm. On a
  /// pad that is already looping, the tap switches the loop off.
  void tapPad(int slot) {
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
  void _fireOnce(int bank, int slot) {
    final pad = _session!.banks[bank].pads[slot];
    final sound = _library.byId(pad.soundId);
    if (sound == null || _isSilenced(pad)) return;

    final key = padKey(bank, slot);
    final previous = _hits.remove(key);
    if (previous != null) {
      _engine.stopHandle(previous);
    }

    final handle = _engine.fire(
      sound,
      volume: pad.volume * sound.volume,
      rate: sound.playbackRate * _rateFor(pad),
    );
    if (handle != null) _hits[key] = handle;
  }

  /// Tape-style: the pad's own pitch offset stacks on the sound's.
  double _rateFor(PadConfig pad) => pad.semitones == 0
      ? 1.0
      : math.pow(2, pad.semitones / 12.0).toDouble();

  bool _isSilenced(PadConfig pad) => pad.muted;

  void _startLoop(int bank, int slot) {
    final key = padKey(bank, slot);
    if (_loops.containsKey(key)) return;
    final pad = _session!.banks[bank].pads[slot];
    final sound = _library.byId(pad.soundId);
    if (sound == null) return;

    if (pad.synced) {
      // Retriggered by the clock so it lands with the other synced layers.
      _loops[key] = ActiveLoop(bank: bank, slot: slot, synced: true);
      _clock.add(key, pad.loopSteps);
    } else {
      // Free loop: SoLoud repeats it natively at its own natural length.
      final handle = _engine.fire(
        sound,
        volume: _isSilenced(pad) ? 0 : pad.volume * sound.volume,
        rate: sound.playbackRate * _rateFor(pad),
        looping: true,
      );
      _loops[key] = ActiveLoop(bank: bank, slot: slot, handle: handle, synced: false);
    }
  }

  void _onSyncedStep(String key) {
    if (key == kMetronomeId) {
      _fireClick();
      return;
    }
    if (key == kSequencerKey) {
      sequencer.tick();
      return;
    }
    final loop = _loops[key];
    if (loop == null) return;
    _fireOnce(loop.bank, loop.slot);
  }

  // ------------------------------------------------------------ sequencer

  /// Plays every note of a step at once. A rest arrives here as an empty set
  /// and correctly does nothing.
  void _fireNotes(Set<String> notes) {
    for (final note in notes) {
      final target = parsePadKey(note);
      if (target == null) continue;
      _fireOnce(target.bank, target.slot);
    }
  }

  void _onPatternsChanged() {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(
      patterns: sequencer.patterns,
      activePattern: sequencer.patternIndex,
      chainLength: sequencer.chainLength,
    );
    _touch();
  }

  /// Bars in the chain: 1 loops the pattern on screen, N walks P1..PN.
  void setChainLength(int bars) {
    sequencer.chainLength = bars;
    _onPatternsChanged();
    notifyListeners();
  }

  void toggleSequencer() {
    sequencer.toggleOn();
    if (!sequencer.isOn) _clock.remove(kSequencerKey);
    notifyListeners();
  }

  /// Play and stop for the pattern. The clock entry is what makes it run, so
  /// it is added and removed here rather than inside the sequencer.
  void toggleSequencerPlay() {
    sequencer.togglePlay();
    if (sequencer.isPlaying) {
      _clock.add(kSequencerKey, 1);
    } else {
      _clock.remove(kSequencerKey);
    }
    notifyListeners();
  }

  void toggleSequencerRecord() {
    sequencer.toggleRecord();
    if (!sequencer.isPlaying) _clock.remove(kSequencerKey);
    notifyListeners();
  }

  void selectPattern(int index) {
    sequencer.selectPattern(index);
    _onPatternsChanged();
    notifyListeners();
  }

  // ------------------------------------------------------------------- roll

  bool _rollHeld = false;

  bool get isRolling => _rollHeld;

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
    _rollTimer?.cancel();
    _rollTimer = null;
    notifyListeners();
  }

  /// Points the roll at a pad. Touching another pad mid-roll retargets it —
  /// that is how a fill walks across the kit.
  void _rollOn(int bank, int slot) {
    _rollTimer?.cancel();
    final interval = Duration(
      microseconds: (60000000 / bpm / kStepsPerBeat).round(),
    );
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

    final click = _click ??= await ensureMetronomeSound(Storage.instance);
    if (!_engine.isLoaded(click.id)) {
      await _engine.preload(click, Storage.instance.soundFile(click.fileName).path);
    }
    _metronome = true;
    _clock.add(kMetronomeId, kStepsPerBeat);
    notifyListeners();
  }

  void _fireClick() {
    final click = _click;
    if (click == null) return;
    _engine.fire(click, volume: kMetronomeVolume, rate: 1.0);
  }

  Future<void> _stopLoop(String key) async {
    final loop = _loops.remove(key);
    if (loop == null) return;
    _clock.remove(key);
    final handle = loop.handle;
    if (handle != null) {
      await _engine.stopHandle(handle);
    }
  }

  /// The panic button: every loop off and every hit still ringing cut short.
  Future<void> stopAllLoops() async {
    stopRoll();
    for (final handle in _hits.values) {
      await _engine.stopHandle(handle);
    }
    _hits.clear();

    final keys = _loops.keys.toList();
    for (final key in keys) {
      await _stopLoop(key);
    }
    _clock.clear();
    // Stopping the music does not stop the click: it is a tool, not a layer.
    if (_metronome) _clock.add(kMetronomeId, kStepsPerBeat);
    if (sequencer.isPlaying) _clock.add(kSequencerKey, 1);
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
    notifyListeners();
    return file;
  }

  /// Long press target: replaces the pad wholesale.
  Future<void> updatePad(int bank, int slot, PadConfig pad) async {
    final session = _session;
    if (session == null) return;
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
    _touch();
    notifyListeners();
  }

  void toggleMute(int slot) {
    final pad = padAt(slot);
    final next = pad.copyWith(muted: !pad.muted);
    _applyPadLive(_activeBank, slot, next);
  }

  /// Solo: this pad keeps sounding, every other one drops to silence.
  void toggleSolo(int slot) {
    _soloActive = !_soloActive;
    final session = _session;
    if (session == null) return;
    for (var b = 0; b < session.banks.length; b++) {
      for (var s = 0; s < session.banks[b].pads.length; s++) {
        final shouldMute = _soloActive && !(b == _activeBank && s == slot);
        final pad = session.banks[b].pads[s];
        if (pad.muted != shouldMute) {
          _applyPadLive(b, s, pad.copyWith(muted: shouldMute), quiet: true);
        }
      }
    }
    notifyListeners();
  }

  /// Applies a pad change and reflects it on any handle already sounding, so a
  /// mute or a volume move is heard immediately rather than on the next hit.
  void _applyPadLive(int bank, int slot, PadConfig pad, {bool quiet = false}) {
    final session = _session;
    if (session == null) return;
    _session = session.withPad(bank, slot, pad);

    final loop = _loops[padKey(bank, slot)];
    final sound = _library.byId(pad.soundId);
    if (loop?.handle != null && sound != null) {
      _engine.setHandleVolume(
        loop!.handle!,
        _isSilenced(pad) ? 0 : pad.volume * sound.volume,
      );
    }
    _touch();
    if (!quiet) notifyListeners();
  }

  void setPadVolume(int slot, double volume) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(volume: volume));

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
    if (wasSynced) _clock.add(key, steps);
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
    _rollTimer?.cancel();
    _saveTimer?.cancel();
    final session = _session;
    if (session != null) _store.save(session);
    _clock.dispose();
    super.dispose();
  }
}
