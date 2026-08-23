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

// ------------------------------------------------------------------ Buses

/// What the plugin accepts on the shared send bus's reverb. Freeverb's five
/// parameters all live between zero and one, so nothing here can fall out of
/// range — it is written down anyway, so the day the reverb is swapped the
/// test is already in place.
const double kReverbMin = 0;
const double kReverbMax = 1;

/// The fixed character of the shared reverb: a medium room that does not eat
/// anyone else's space. As with the echo, the knob does not shape it — it
/// only decides how much of each family goes into it.
///
/// `wet` is one because the bus returns **reverb only**: the dry signal
/// already travels on the family's own bus. That is what makes this a send
/// and not an insert.
const double kReverbWet = 1;
const double kReverbRoomSize = 0.72;
const double kReverbDamp = 0.35;
const double kReverbWidth = 1;
const double kReverbFreeze = 0;

/// How much of a pad reaches the shared reverb. Square: the first half of the
/// throw is a halo and the second half is the whole room, which is how a
/// reverb is looked for by someone playing rather than looking.
double sendGain(double knob) {
  final position = knob.clamp(0.0, 1.0);
  return position * position;
}
