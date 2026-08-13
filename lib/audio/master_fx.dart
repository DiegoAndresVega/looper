import 'package:flutter_soloud/flutter_soloud.dart';

import 'fx_curves.dart';

/// The performance effects, sitting on the master output: one low-pass filter
/// with resonance, an echo and a bit-crush drive. They colour everything at
/// once — per-pad effects are a different feature, deliberately not this one.
///
/// Values are remembered here and pushed to SoLoud, because the engine is torn
/// down every time the sampler borrows the audio session and the filters go
/// with it. [apply] puts them back after each init.
///
/// Knob positions are performance state, like where a DJ left the filter —
/// they reset when the app restarts, on purpose.
///
/// The filters are switched on once and left on: bypassing is `wet` at zero,
/// never removing the filter. Adding one back mid-performance drops its
/// factory settings on the master output for a buffer, and the lofi's factory
/// setting is a brutal 4 kHz crush. Zero wet really is a bypass — every SoLoud
/// filter mixes as `out += (effect - out) * wet`.
///
/// Where each knob position lands lives in [fx_curves], which is also where
/// the plugin's accepted ranges are written down.
class MasterFx {
  final SoLoud _soloud = SoLoud.instance;

  double _volume = 1.0;
  double _cutoff = 1.0;
  double _resonance = 0.0;
  double _echo = 0.0;
  double _drive = 0.0;

  double get volume => _volume;
  double get cutoff => _cutoff;
  double get resonance => _resonance;
  double get echo => _echo;
  double get drive => _drive;

  /// Fixed echo character: a slapback that works at most tempos. The knob only
  /// rides how much of it is heard.
  ///
  /// It has to stay under the 0.3 s the echo filter allocates for itself the
  /// first time it runs — that buffer is sized once and never grows, so asking
  /// for a longer delay later would simply be clamped back.
  static const double _echoDelaySeconds = 0.28;
  static const double _echoDecay = 0.45;

  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    if (!_soloud.isInitialized) return;
    _soloud.setGlobalVolume(_volume);
  }

  /// 1.0 is fully open — the filter is bypassed there, so a resting knob costs
  /// nothing and colours nothing.
  set cutoff(double value) {
    _cutoff = value.clamp(0.0, 1.0);
    _applyBiquad();
  }

  set resonance(double value) {
    _resonance = value.clamp(0.0, 1.0);
    _applyBiquad();
  }

  set echo(double value) {
    _echo = value.clamp(0.0, 1.0);
    _applyEcho();
  }

  set drive(double value) {
    _drive = value.clamp(0.0, 1.0);
    _applyLofi();
  }

  /// Pushes every remembered value into a freshly initialised engine, filters
  /// included. Called on every [AudioEngine.init], not just the first.
  void apply() {
    if (!_soloud.isInitialized) return;
    _soloud.setGlobalVolume(_volume);
    _activate();
    _applyBiquad();
    _applyEcho();
    _applyLofi();
  }

  void _activate() {
    for (final filter in [
      _soloud.filters.biquadResonantFilter,
      _soloud.filters.echoFilter,
      _soloud.filters.lofiFilter,
    ]) {
      if (!filter.isActive) filter.activate();
    }
  }

  void _applyBiquad() {
    if (!_soloud.isInitialized) return;
    final filter = _soloud.filters.biquadResonantFilter;
    if (!filter.isActive) return;

    // Shape first, wet last: the other way round lets a buffer through with
    // the new mix and the old cutoff, which is heard as a blip.
    final resting = _cutoff >= 1 - kFxEpsilon && _resonance <= kFxEpsilon;
    if (!resting) {
      filter.type.value = 0; // low-pass
      filter.frequency.value = filterCutoffHz(_cutoff);
      filter.resonance.value = filterResonance(_resonance);
    }
    filter.wet.value = resting ? 0 : 1;
  }

  void _applyEcho() {
    if (!_soloud.isInitialized) return;
    final filter = _soloud.filters.echoFilter;
    if (!filter.isActive) return;

    filter.delay.value = _echoDelaySeconds;
    filter.decay.value = _echoDecay;
    filter.wet.value = _echo <= kFxEpsilon ? 0 : _echo;
  }

  void _applyLofi() {
    if (!_soloud.isInitialized) return;
    final filter = _soloud.filters.lofiFilter;
    if (!filter.isActive) return;

    // Wet rides the knob alongside the crush, so the first sliver of travel
    // is a hint of grit instead of a cliff. It goes last, once the crush it
    // is mixing in is already the right one.
    final resting = _drive <= kFxEpsilon;
    if (!resting) {
      filter.samplerate.value = crushRateHz(_drive);
      filter.bitdepth.value = crushBitdepth(_drive);
    }
    filter.wet.value = resting ? 0 : _drive;
  }
}
