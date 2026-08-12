import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

/// Renders one factory sound as mono float samples.
typedef VoiceRenderer = Float32List Function(int sampleRate);

/// Builds a buffer of [seconds] and hands it to [fill] sample by sample.
Float64List _buffer(int sampleRate, double seconds) =>
    Float64List((sampleRate * seconds).round());

/// A pitched layer: oscillator + amplitude envelope, optional pitch glide,
/// optional saturation.
Float64List _osc(
  int sampleRate,
  double seconds, {
  required Wave wave,
  required double freq,
  double? toFreq,
  double glideTime = 0.1,
  double attack = 0.004,
  required double decay,
  double peak = 1.0,
  double drive = 0,
}) {
  final out = _buffer(sampleRate, seconds);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = toFreq == null ? freq : glide(t, freq, toFreq, glideTime);
    phase += f / sampleRate;
    final v = waveSample(wave, phase) * adEnvelope(t, attack, decay, peak);
    out[i] = drive > 0 ? saturate(v, drive) : v;
  }
  return out;
}

/// A noise layer through one filter.
Float64List _noise(
  int sampleRate,
  double seconds, {
  required String filter,
  required double freq,
  double q = 1.0,
  double attack = 0.002,
  required double decay,
  double peak = 1.0,
  int seed = 7,
}) {
  final out = _buffer(sampleRate, seconds);
  final noise = NoiseSource(seed);
  final bq = Biquad();
  switch (filter) {
    case 'low':
      bq.lowpass(freq, q, sampleRate);
    case 'high':
      bq.highpass(freq, q, sampleRate);
    default:
      bq.bandpass(freq, q, sampleRate);
  }
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    out[i] = bq.process(noise.next()) * adEnvelope(t, attack, decay, peak);
  }
  return out;
}

/// 303-style line: a saw through a resonant lowpass whose cutoff falls over the
/// life of the note. This is what gives the acid row its squelch.
Float64List _acid(
  int sampleRate, {
  required double freq,
  double? slideTo,
  required double cutoff,
  required double resonance,
  required double decay,
}) {
  final seconds = decay + 0.12;
  final out = _buffer(sampleRate, seconds);
  final bq = Biquad();
  var phase = 0.0;
  final target = math.max(freq * 1.4, 90.0);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = slideTo == null ? freq : glide(t, freq, slideTo, decay * 0.55);
    phase += f / sampleRate;
    final cut = glide(t, cutoff, target, decay);
    bq.lowpass(cut, resonance, sampleRate);
    final v = bq.process(waveSample(Wave.saw, phase));
    out[i] = saturate(v * adEnvelope(t, 0.005, decay, 0.9), 4);
  }
  return out;
}

/// A distorted sine kick: the backbone of both kits.
Float64List _kick(
  int sampleRate, {
  required double from,
  required double to,
  required double decay,
  double drive = 0,
  double peak = 1.0,
}) {
  return _osc(sampleRate, decay + 0.08,
      wave: Wave.sine,
      freq: from,
      toFreq: to,
      glideTime: decay * 0.35,
      attack: 0.003,
      decay: decay,
      peak: peak,
      drive: drive);
}

Float64List _mix(int sampleRate, double seconds, List<Float64List> parts) {
  final out = _buffer(sampleRate, seconds);
  for (final p in parts) {
    mixInto(out, p, 0);
  }
  return out;
}

/// Every factory voice, keyed by the id used in the kit definitions.
final Map<String, VoiceRenderer> kVoices = {
  // ---------- Bank A · acoustic-ish kit ----------
  'kick': (sr) => finalise(_mix(sr, 0.42, [
        _kick(sr, from: 130, to: 42, decay: 0.34),
        _noise(sr, 0.05, filter: 'low', freq: 700, decay: 0.03, peak: 0.17),
      ])),
  'snare': (sr) => finalise(_mix(sr, 0.24, [
        _noise(sr, 0.2, filter: 'high', freq: 1500, q: 0.8, decay: 0.16, peak: 0.85),
        _osc(sr, 0.16, wave: Wave.triangle, freq: 210, toFreq: 150, glideTime: 0.08, decay: 0.11, peak: 0.5),
      ])),
  'hat': (sr) => finalise(_noise(sr, 0.08, filter: 'high', freq: 8200, q: 1.2, attack: 0.001, decay: 0.045)),
  'clap': (sr) {
    final out = _buffer(sr, 0.22);
    for (var i = 0; i < 3; i++) {
      mixInto(out, _noise(sr, 0.13, filter: 'band', freq: 1650, q: 3.5, decay: 0.1, seed: 11 + i),
          (sr * 0.012 * i).round());
    }
    return finalise(out);
  },
  'snap': (sr) => finalise(_noise(sr, 0.09, filter: 'band', freq: 2600, q: 6, attack: 0.001, decay: 0.055)),
  'tom': (sr) => finalise(_osc(sr, 0.34, wave: Wave.sine, freq: 190, toFreq: 92, glideTime: 0.15, decay: 0.26)),
  'rim': (sr) => finalise(_mix(sr, 0.07, [
        _noise(sr, 0.05, filter: 'band', freq: 3100, q: 9, attack: 0.001, decay: 0.035),
        _osc(sr, 0.05, wave: Wave.square, freq: 800, attack: 0.001, decay: 0.03, peak: 0.4),
      ])),
  'shaker': (sr) => finalise(_noise(sr, 0.1, filter: 'high', freq: 6200, q: 0.9, attack: 0.004, decay: 0.06)),
  'bass': (sr) {
    final out = _buffer(sr, 0.45);
    final bq = Biquad();
    var phase = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sr;
      phase += 58 / sr;
      bq.lowpass(glide(t, 220, 70, 0.30), 7, sr);
      out[i] = bq.process(waveSample(Wave.saw, phase)) * adEnvelope(t, 0.008, 0.34, 1.0);
    }
    return finalise(out);
  },
  'chord': (sr) => finalise(_mix(sr, 0.95, [
        for (final f in [220.0, 261.6, 329.6])
          _osc(sr, 0.9, wave: Wave.triangle, freq: f, attack: 0.02, decay: 0.85, peak: 0.4),
      ])),
  'bell': (sr) {
    final out = _buffer(sr, 1.25);
    var cp = 0.0, mp = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sr;
      mp += 1810 / sr;
      cp += (880 + 620 * waveSample(Wave.sine, mp)) / sr;
      out[i] = waveSample(Wave.sine, cp) * adEnvelope(t, 0.003, 1.1, 1.0);
    }
    return finalise(out);
  },
  'pad': (sr) => finalise(_mix(sr, 2.0, [
        _osc(sr, 1.9, wave: Wave.saw, freq: 110, attack: 0.3, decay: 1.5, peak: 0.5),
        _osc(sr, 1.9, wave: Wave.saw, freq: 110.7, attack: 0.3, decay: 1.5, peak: 0.5),
      ])),
  'voxA': (sr) => _formant(sr, 0.6, 196, [730, 1090], decay: 0.42),
  'voxB': (sr) => _formant(sr, 0.85, 147, [500, 1700], decay: 0.62, slideTo: 165),
  'bottle': (sr) => finalise(_mix(sr, 0.4, [
        _osc(sr, 0.36, wave: Wave.sine, freq: 620, attack: 0.006, decay: 0.30),
        _noise(sr, 0.09, filter: 'band', freq: 1900, q: 4, decay: 0.06, peak: 0.4),
      ])),
  'vinyl': (sr) => finalise(_noise(sr, 0.6, filter: 'band', freq: 3400, q: 0.6, attack: 0.02, decay: 0.55)),

  // ---------- Bank B · hardtechno & acid ----------
  'kickHT': (sr) => finalise(_mix(sr, 0.4, [
        _kick(sr, from: 190, to: 46, decay: 0.30, drive: 14),
        _noise(sr, 0.03, filter: 'high', freq: 2600, attack: 0.001, decay: 0.015, peak: 0.35),
      ])),
  'kickDst': (sr) => finalise(_mix(sr, 0.46, [
        _kick(sr, from: 240, to: 44, decay: 0.36, drive: 45),
        _noise(sr, 0.04, filter: 'band', freq: 1400, attack: 0.001, decay: 0.02, peak: 0.4),
      ])),
  'rumble': (sr) => finalise(_mix(sr, 0.95, [
        _kick(sr, from: 180, to: 40, decay: 0.22, drive: 10),
        _osc(sr, 0.9, wave: Wave.sine, freq: 44, toFreq: 32, glideTime: 0.5, attack: 0.05, decay: 0.8, peak: 0.55),
      ])),
  'kickPnch': (sr) => finalise(_mix(sr, 0.26, [
        _kick(sr, from: 160, to: 50, decay: 0.16, drive: 8),
        _noise(sr, 0.02, filter: 'high', freq: 4200, attack: 0.001, decay: 0.008, peak: 0.45),
      ])),
  'clapInd': (sr) {
    final out = _buffer(sr, 0.42);
    for (var i = 0; i < 4; i++) {
      mixInto(out, _noise(sr, 0.09, filter: 'band', freq: 1250, q: 4, decay: 0.07, seed: 21 + i),
          (sr * 0.009 * i).round());
    }
    mixInto(out, _noise(sr, 0.36, filter: 'band', freq: 900, q: 1.4, attack: 0.01, decay: 0.34, peak: 0.45),
        (sr * 0.02).round());
    return finalise(out);
  },
  'hatOff': (sr) => finalise(_noise(sr, 0.06, filter: 'high', freq: 9400, q: 1.5, attack: 0.001, decay: 0.032)),
  'hatOpen': (sr) => finalise(_noise(sr, 0.3, filter: 'high', freq: 7600, q: 1, decay: 0.26)),
  'zap': (sr) => finalise(_osc(sr, 0.2, wave: Wave.saw, freq: 1900, toFreq: 120, glideTime: 0.09, attack: 0.002, decay: 0.1, drive: 12)),
  'acid1': (sr) => finalise(_acid(sr, freq: 110, cutoff: 2100, resonance: 9, decay: 0.20)),
  'acid2': (sr) => finalise(_acid(sr, freq: 110, cutoff: 3400, resonance: 12, decay: 0.26)),
  'acid3': (sr) => finalise(_acid(sr, freq: 82, slideTo: 164, cutoff: 2600, resonance: 11, decay: 0.34)),
  'squelch': (sr) => finalise(_acid(sr, freq: 55, slideTo: 110, cutoff: 4200, resonance: 15, decay: 0.46)),
  'siren': (sr) {
    final out = _buffer(sr, 1.35);
    final bq = Biquad();
    bq.bandpass(900, 4, sr);
    var phase = 0.0, lfo = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sr;
      lfo += 3.1 / sr;
      phase += (520 + 190 * waveSample(Wave.sine, lfo)) / sr;
      out[i] = bq.process(waveSample(Wave.saw, phase)) * adEnvelope(t, 0.06, 1.1, 1.0);
    }
    return finalise(out);
  },
  'riser': (sr) {
    final out = _buffer(sr, 1.6);
    final noise = NoiseSource(33);
    final bq = Biquad();
    for (var i = 0; i < out.length; i++) {
      final t = i / sr;
      bq.highpass(glide(t, 260, 9000, 1.4), 3, sr);
      final env = t < 1.35 ? math.pow(t / 1.35, 2).toDouble() : math.max(0.0, (1.55 - t) / 0.2);
      out[i] = bq.process(noise.next()) * env;
    }
    return finalise(out);
  },
  'impact': (sr) => finalise(_mix(sr, 0.9, [
        _kick(sr, from: 90, to: 28, decay: 0.75, drive: 20),
        _noise(sr, 0.5, filter: 'low', freq: 420, decay: 0.42, peak: 0.5),
      ])),
  'noiseWash': (sr) => finalise(_noise(sr, 1.4, filter: 'band', freq: 2200, q: 0.5, attack: 0.25, decay: 1.1)),

  // Not on any pad: the metronome click. Short and high so it cuts through a
  // busy grid without ever being mistaken for part of the music.
  'metro': (sr) => finalise(_osc(sr, 0.05, wave: Wave.sine, freq: 1760,
      attack: 0.001, decay: 0.035)),
};

/// Two stacked bandpass filters over a saw: a crude but recognisable vowel.
Float32List _formant(
  int sampleRate,
  double seconds,
  double freq,
  List<double> formants, {
  required double decay,
  double? slideTo,
}) {
  final out = _buffer(sampleRate, seconds);
  final f1 = Biquad()..bandpass(formants[0], 9, sampleRate);
  final f2 = Biquad()..bandpass(formants[1], 9, sampleRate);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = slideTo == null ? freq : freq + (slideTo - freq) * math.min(1.0, t / 0.4);
    phase += f / sampleRate;
    final v = f2.process(f1.process(waveSample(Wave.saw, phase)));
    out[i] = v * adEnvelope(t, 0.03, decay, 1.0);
  }
  return finalise(out);
}
