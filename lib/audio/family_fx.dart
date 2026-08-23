import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/palette.dart';
import 'bus_rack.dart';
import 'fx_curves.dart';

/// The four families, wired as real mixing buses, plus one shared reverb they
/// all send to.
///
/// ```
///                    ┌── percusión ──┐
///   a pad's voice ──►│  voz          │──► master (the global effects) ──► out
///                    │  tono         │
///                    └── textura ────┘
///   its send twin ──► reverb ─────────────► master
/// ```
///
/// **Why buses and not per-sound filters.** A sound belongs to exactly one
/// family, so filtering every source of that family would sound the same —
/// until two pads share a source, or a chop puts eight pads on one file. The
/// bus filters the *mix* of the family, once, which is both cheaper and the
/// only version that stays right.
///
/// **Why the send is a second voice.** SoLoud buses are parents, not sends: a
/// voice plays through one bus and that is the end of it. So a pad with its
/// send up is played twice — dry through its family, and again into the
/// reverb bus at the send's gain. One reverb serves all four families, which
/// is the whole point: four freeverbs on a mid-range phone is the thing this
/// design exists to avoid.
///
/// The twin is pre-effects: it hears the pad, not the pad through the
/// family's filter. Turning a family's filter down therefore leaves its
/// reverb bright. That is a real difference from a desk, and it is the price
/// of one reverb instead of four.
///
/// Everything here is torn down and rebuilt around [AudioEngine.release],
/// because the buses live inside the engine the sampler takes away.
class FamilyFx {
  /// Knob positions. They survive the engine being torn down, which is why
  /// they live in their own object with no audio in it.
  final BusRack rack = BusRack();

  final Map<SoundFamily, Bus> _buses = {};
  Bus? _reverb;

  /// Whether the buses are up. While they are not, a voice plays straight on
  /// the engine — no family colouring, but never silence.
  bool get isReady => _reverb != null && _buses.length == SoundFamily.values.length;

  Bus? busFor(SoundFamily family) => _buses[family];
  Bus? get reverbBus => _reverb;

  /// Builds the five buses and starts them. Called on every engine init, not
  /// just the first: the C++ side loses them with the engine.
  void attach() {
    if (_buses.isNotEmpty) detach();
    try {
      for (final family in SoundFamily.values) {
        _buses[family] = SoLoud.instance.createMixingBus(name: family.name);
      }
      _reverb = SoLoud.instance.createMixingBus(name: 'reverb');
    } on Exception catch (e) {
      debugPrint('No se pudieron crear los buses: $e');
      detach();
      return;
    }
    _activate();
    rearm();
    applyAll();
  }

  /// Puts the bus voices back on the engine. Every bus is a voice like any
  /// other, so anything that stops all voices — `disposeAllSources` does —
  /// takes the buses off the air with them, and the grid goes silent until
  /// they are played again.
  void rearm() {
    if (_buses.isEmpty) return;
    try {
      for (final bus in [..._buses.values, ?_reverb]) {
        bus.playOnEngine();
      }
    } on Exception catch (e) {
      debugPrint('No se pudieron arrancar los buses: $e');
    }
  }

  /// Frees the buses. Must run *before* the engine is deinited: destroying a
  /// bus reaches into the engine it belongs to.
  void detach() {
    for (final bus in [..._buses.values, ?_reverb]) {
      try {
        bus.dispose();
      } on Exception catch (e) {
        debugPrint('No se pudo soltar el bus ${bus.name}: $e');
      }
    }
    _buses.clear();
    _reverb = null;
  }

  // --------------------------------------------------------------- The knobs

  void setCutoff(SoundFamily family, double value) {
    rack.setCutoff(family, value);
    _applyFilter(family);
  }

  void setResonance(SoundFamily family, double value) {
    rack.setResonance(family, value);
    _applyFilter(family);
  }

  void setDrive(SoundFamily family, double value) {
    rack.setDrive(family, value);
    _applyDrive(family);
  }

  /// The send needs nothing pushed anywhere: it is read when a pad fires.
  void setSend(SoundFamily family, double value) => rack.setSend(family, value);

  BusSettings settingsFor(SoundFamily family) => rack.settingsFor(family);

  /// Pushes every remembered knob into freshly built buses.
  void applyAll() {
    for (final family in SoundFamily.values) {
      _applyFilter(family);
      _applyDrive(family);
    }
    _applyReverb();
  }

  // ------------------------------------------------------------- The filters

  /// Filters are switched on once and left on. Adding one back mid-set drops
  /// its factory settings on a live bus for a buffer, and the lofi's factory
  /// setting is a brutal 4 kHz crush. Zero wet is the real bypass.
  void _activate() {
    for (final bus in _buses.values) {
      _turnOn(
        bus.name,
        () => bus.filters.biquadFilter.isActive,
        () => bus.filters.biquadFilter.activate(),
      );
      _turnOn(
        bus.name,
        () => bus.filters.lofiFilter.isActive,
        () => bus.filters.lofiFilter.activate(),
      );
    }
    final reverb = _reverb;
    if (reverb != null) {
      _turnOn(
        reverb.name,
        () => reverb.filters.freeverbFilter.isActive,
        () => reverb.filters.freeverbFilter.activate(),
      );
    }
  }

  /// The filter arrives as two closures rather than as itself: the plugin
  /// exports the concrete filters but not the base class they share, so there
  /// is no name to give the parameter.
  void _turnOn(String where, bool Function() isActive, void Function() activate) {
    try {
      if (!isActive()) activate();
    } on Exception catch (e) {
      debugPrint('No se pudo activar un filtro en $where: $e');
    }
  }

  void _applyFilter(SoundFamily family) {
    final bus = _buses[family];
    if (bus == null) return;
    final filter = bus.filters.biquadFilter;
    if (!filter.isActive) return;
    final settings = rack.settingsFor(family);

    // Shape first, wet last — the other way round lets a buffer through with
    // the new mix and the old cutoff, which is heard as a blip.
    final resting = settings.isFilterResting;
    if (!resting) {
      filter.type().value = 0; // low-pass
      filter.frequency().value = filterCutoffHz(settings.cutoff);
      filter.resonance().value = filterResonance(settings.resonance);
    }
    filter.wet().value = resting ? 0 : 1;
  }

  void _applyDrive(SoundFamily family) {
    final bus = _buses[family];
    if (bus == null) return;
    final filter = bus.filters.lofiFilter;
    if (!filter.isActive) return;
    final settings = rack.settingsFor(family);

    final resting = settings.isDriveResting;
    if (!resting) {
      filter.samplerate().value = crushRateHz(settings.drive);
      filter.bitdepth().value = crushBitdepth(settings.drive);
    }
    filter.wet().value = resting ? 0 : settings.drive;
  }

  /// The reverb never changes: it is the amount sent that moves. Its wet stays
  /// at one because the bus carries nothing but reverb.
  void _applyReverb() {
    final bus = _reverb;
    if (bus == null) return;
    final filter = bus.filters.freeverbFilter;
    if (!filter.isActive) return;

    filter.roomSize().value = kReverbRoomSize;
    filter.damp().value = kReverbDamp;
    filter.width().value = kReverbWidth;
    filter.freeze().value = kReverbFreeze;
    filter.wet().value = kReverbWet;
  }
}
