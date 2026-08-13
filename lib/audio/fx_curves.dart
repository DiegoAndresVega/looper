/// Where a knob position lands on each of the master effects.
///
/// This lives apart from [MasterFx] because it is the half that can be
/// checked without a device — and it is the half that was wrong. The plugin
/// **drops** a filter parameter written outside its accepted range: it logs a
/// warning and returns, leaving the filter on whatever it had, which for the
/// bit crusher is a factory 4 kHz. That is how a knob ends up doing nothing,
/// or everything at once. Every curve here is written to stay inside the
/// ranges below, and the tests hold them to it.
library;

import 'dart:math' as math;

/// What the SoLoud plugin accepts for the filters used on the master output.
const double kBiquadMinHz = 10;
const double kBiquadMaxHz = 16000;
const double kBiquadMinResonance = 0.1;
const double kBiquadMaxResonance = 20;
const double kCrushMinHz = 100;
const double kCrushMaxHz = 22000;
const double kCrushMinBitdepth = 0.5;
const double kCrushMaxBitdepth = 16;

/// Below this a knob counts as resting and its filter is bypassed.
const double kFxEpsilon = 0.005;

/// Low-pass sweep. The top is as high as the plugin goes, so a resting knob
/// is transparent; the bottom is where it turns to mud.
const double _sweepMinHz = 180;
const double _sweepMaxHz = kBiquadMaxHz;

/// Resonance range. It starts at 1 — flat, no ring — rather than at the
/// plugin's floor, because a resonance under 1 only makes things quieter.
const double _minResonance = 1;
const double _maxResonance = 14;

/// How far down the crusher reaches at full throw.
const double _crushFloorHz = 3500;
const double _crushFloorBits = 4;

/// The cutoff, in hertz. Exponential: half the knob is half the octaves, not
/// half the hertz, which is how a filter is expected to feel under a thumb.
double filterCutoffHz(double knob) {
  final position = knob.clamp(0.0, 1.0);
  final hz = _sweepMinHz * math.pow(_sweepMaxHz / _sweepMinHz, position);
  return hz.toDouble().clamp(kBiquadMinHz, kBiquadMaxHz);
}

/// How sharp the corner of the filter is.
double filterResonance(double knob) {
  final position = knob.clamp(0.0, 1.0);
  final resonance = _minResonance + position * (_maxResonance - _minResonance);
  return resonance.clamp(kBiquadMinResonance, kBiquadMaxResonance);
}

/// The rate the crusher throws samples away at. Full throw is gravel.
double crushRateHz(double knob) {
  final position = knob.clamp(0.0, 1.0);
  final hz = kCrushMaxHz - position * (kCrushMaxHz - _crushFloorHz);
  return hz.clamp(kCrushMinHz, kCrushMaxHz);
}

/// How many bits the crusher leaves standing.
double crushBitdepth(double knob) {
  final position = knob.clamp(0.0, 1.0);
  final bits = kCrushMaxBitdepth - position * (kCrushMaxBitdepth - _crushFloorBits);
  return bits.clamp(kCrushMinBitdepth, kCrushMaxBitdepth);
}
