import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

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

  /// Low-pass sweep range. The top stays out of the way; the bottom mangles.
  static const double _minHz = 180;
  static const double _maxHz = 18000;
  static const double _maxResonance = 14;

  /// Fixed echo character: a dotted-ish slapback that works at most tempos.
  /// The knob only rides how much of it is heard.
  static const double _echoDelaySeconds = 0.28;
  static const double _echoDecay = 0.45;

  /// Drive floor: how far down the bit crusher reaches at full throw.
  static const double _minBitdepth = 4;
  static const double _minSampleRateHz = 3500;

  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _soloud.setGlobalVolume(_volume);
  }

  /// 1.0 is fully open — the filter is bypassed there so a resting knob costs
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

  /// Pushes every remembered value into a freshly initialised engine.
  void apply() {
    _soloud.setGlobalVolume(_volume);
    _applyBiquad();
    _applyEcho();
    _applyLofi();
  }

  void _applyBiquad() {
    final filter = _soloud.filters.biquadResonantFilter;
    final resting = _cutoff >= 0.995 && _resonance <= 0.005;
    if (resting) {
      if (filter.isActive) filter.deactivate();
      return;
    }
    if (!filter.isActive) filter.activate();

    // The sweep is exponential: half the knob is half the octaves, not half
    // the hertz, which is how a filter is expected to feel.
    final hz = _minHz * math.pow(_maxHz / _minHz, _cutoff);
    filter.type.value = 0; // low-pass
    filter.frequency.value = hz.toDouble();
    filter.resonance.value = (1 + _resonance * (_maxResonance - 1)).toDouble();
  }

  void _applyEcho() {
    final filter = _soloud.filters.echoFilter;
    if (_echo <= 0.005) {
      if (filter.isActive) filter.deactivate();
      return;
    }
    if (!filter.isActive) filter.activate();
    filter.delay.value = _echoDelaySeconds;
    filter.decay.value = _echoDecay;
    filter.wet.value = _echo;
  }

  void _applyLofi() {
    final filter = _soloud.filters.lofiFilter;
    if (_drive <= 0.005) {
      if (filter.isActive) filter.deactivate();
      return;
    }
    if (!filter.isActive) filter.activate();
    filter.bitdepth.value = 16 - _drive * (16 - _minBitdepth);
    filter.samplerate.value =
        44100 - _drive * (44100 - _minSampleRateHz);
    filter.wet.value = 1.0;
  }
}
