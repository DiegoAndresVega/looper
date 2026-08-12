import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../audio/audio_engine.dart';
import '../audio/tempo_clock.dart';
import '../core/constants.dart';
import '../data/sound_library.dart';
import '../domain/pad_config.dart';
import '../domain/session.dart';
import '../domain/sound.dart';

/// Identifies one pad across the whole session.
String padKey(int bank, int slot) => '$bank:$slot';

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
  SessionController({required AudioEngine engine, required SoundLibrary library})
      : _engine = engine,
        _library = library {
    _clock = TempoClock(onStep: _onSyncedStep);
  }

  final AudioEngine _engine;
  final SoundLibrary _library;
  late final TempoClock _clock;

  Session? _session;
  int _activeBank = 0;
  int? _selectedSlot;
  bool _soloActive = false;
  final Map<String, ActiveLoop> _loops = {};

  Session? get session => _session;
  int get activeBank => _activeBank;
  int? get selectedSlot => _selectedSlot;
  int get bpm => _session?.bpm ?? kDefaultBpm;
  bool get isSoloActive => _soloActive;
  Map<String, ActiveLoop> get loops => Map.unmodifiable(_loops);

  Bank get currentBank => _session!.banks[_activeBank];

  PadConfig padAt(int slot) => currentBank.pads[slot];

  Sound? soundFor(PadConfig pad) => _library.byId(pad.soundId);

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
    notifyListeners();
  }

  // ------------------------------------------------------------------ pads

  /// A tap both fires the pad and points the control surface at it. There is
  /// no separate "select" mode — the instrument has one finger.
  void tapPad(int slot) {
    _selectedSlot = slot;
    final pad = padAt(slot);
    if (pad.isEmpty) {
      notifyListeners();
      return;
    }
    if (pad.isLoop) {
      _toggleLoop(_activeBank, slot);
    } else {
      _fireOnce(_activeBank, slot);
    }
    notifyListeners();
  }

  void _fireOnce(int bank, int slot) {
    final pad = _session!.banks[bank].pads[slot];
    final sound = _library.byId(pad.soundId);
    if (sound == null || _isSilenced(pad)) return;
    _engine.fire(
      sound,
      volume: pad.volume * sound.volume,
      rate: sound.playbackRate * _rateFor(pad),
    );
  }

  /// Tape-style: the pad's own pitch offset stacks on the sound's.
  double _rateFor(PadConfig pad) => pad.semitones == 0
      ? 1.0
      : math.pow(2, pad.semitones / 12.0).toDouble();

  bool _isSilenced(PadConfig pad) => pad.muted;

  void _toggleLoop(int bank, int slot) {
    final key = padKey(bank, slot);
    if (_loops.containsKey(key)) {
      _stopLoop(key);
      return;
    }
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
    final loop = _loops[key];
    if (loop == null) return;
    _fireOnce(loop.bank, loop.slot);
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

  Future<void> stopAllLoops() async {
    final keys = _loops.keys.toList();
    for (final key in keys) {
      await _stopLoop(key);
    }
    _clock.clear();
    notifyListeners();
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
    if (!quiet) notifyListeners();
  }

  void setPadVolume(int slot, double volume) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(volume: volume));

  void setPadSemitones(int slot, int semitones) =>
      _applyPadLive(_activeBank, slot, padAt(slot).copyWith(semitones: semitones));

  void setPadMode(int slot, PadMode mode) {
    final key = padKey(_activeBank, slot);
    if (_loops.containsKey(key)) _stopLoop(key);
    _applyPadLive(_activeBank, slot, padAt(slot).copyWith(mode: mode));
  }

  void setPadSynced(int slot, bool synced) {
    final key = padKey(_activeBank, slot);
    final wasLooping = _loops.containsKey(key);
    if (wasLooping) _stopLoop(key);
    _applyPadLive(_activeBank, slot, padAt(slot).copyWith(synced: synced));
    if (wasLooping) _toggleLoop(_activeBank, slot);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}
