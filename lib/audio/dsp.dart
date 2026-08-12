/// Small offline DSP kit used to render the factory sounds on first launch.
/// Nothing here runs during playback — SoLoud handles that. These helpers only
/// exist so the app ships without a single binary sample.
library;

import 'dart:math' as math;
import 'dart:typed_data';

enum Wave { sine, saw, square, triangle }

double waveSample(Wave wave, double phase) {
  final p = phase % 1.0;
  switch (wave) {
    case Wave.sine:
      return math.sin(2 * math.pi * p);
    case Wave.saw:
      return 2 * p - 1;
    case Wave.square:
      return p < 0.5 ? 1.0 : -1.0;
    case Wave.triangle:
      return p < 0.5 ? (4 * p - 1) : (3 - 4 * p);
  }
}

const double _floor = 0.0001;

/// Attack-decay envelope shaped like an exponential ramp, matching the curve
/// the design prototype used so the rendered kit sounds the same.
double adEnvelope(double t, double attack, double decay, double peak) {
  if (t < 0) return 0;
  if (attack > 0 && t < attack) {
    return _floor * math.pow(peak / _floor, t / attack).toDouble();
  }
  final d = t - attack;
  if (d >= decay) return 0;
  return peak * math.pow(_floor / peak, d / decay).toDouble();
}

/// Exponential glide between two frequencies, the shape of a pitch sweep.
double glide(double t, double from, double to, double time) {
  if (time <= 0 || t >= time) return to;
  return from * math.pow(to / from, t / time).toDouble();
}

/// Direct-form-1 biquad. Coefficients can be recomputed per sample, which is
/// what makes filter sweeps possible.
class Biquad {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  void _set(double b0, double b1, double b2, double a0, double a1, double a2) {
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  void lowpass(double freq, double q, int sampleRate) {
    final w = 2 * math.pi * freq.clamp(20.0, sampleRate / 2.2) / sampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    _set((1 - cw) / 2, 1 - cw, (1 - cw) / 2, 1 + alpha, -2 * cw, 1 - alpha);
  }

  void highpass(double freq, double q, int sampleRate) {
    final w = 2 * math.pi * freq.clamp(20.0, sampleRate / 2.2) / sampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    _set((1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha);
  }

  void bandpass(double freq, double q, int sampleRate) {
    final w = 2 * math.pi * freq.clamp(20.0, sampleRate / 2.2) / sampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    _set(alpha, 0, -alpha, 1 + alpha, -2 * cw, 1 - alpha);
  }

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// Soft saturation. [drive] of 0 leaves the signal alone; higher values push it
/// towards a square — this is what makes the hardtechno kicks bite.
double saturate(double x, double drive) {
  if (drive <= 0) return x;
  return (1 + drive) * x / (1 + drive * x.abs());
}

/// Deterministic noise so every device renders an identical kit.
class NoiseSource {
  NoiseSource([int seed = 12345]) : _rng = math.Random(seed);

  final math.Random _rng;

  double next() => _rng.nextDouble() * 2 - 1;
}

/// Adds [source] into [target] starting at [offsetSamples].
void mixInto(Float64List target, Float64List source, int offsetSamples) {
  final end = math.min(target.length, offsetSamples + source.length);
  for (var i = offsetSamples; i < end; i++) {
    target[i] += source[i - offsetSamples];
  }
}

/// Normalises to [peak] and applies a short fade-out so no clip ends on a click.
Float32List finalise(Float64List buffer, {double peak = 0.89}) {
  var max = 0.0;
  for (final v in buffer) {
    final a = v.abs();
    if (a > max) max = a;
  }
  final gain = max > 0 ? peak / max : 1.0;

  final out = Float32List(buffer.length);
  final fade = math.min(220, buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    var v = buffer[i] * gain;
    final fromEnd = buffer.length - i;
    if (fromEnd < fade) v *= fromEnd / fade;
    out[i] = v.clamp(-1.0, 1.0);
  }
  return out;
}
