import 'dart:typed_data';

import '../domain/synth_patch.dart';
import 'dsp.dart';

/// Renders a [SynthPatch] to mono float samples.
///
/// The same path the factory kit takes — oscillator, AD envelope, a filtered
/// noise layer, saturation, normalise — with the numbers coming from knobs
/// instead of from the twenty hand-written voices. Deterministic on purpose:
/// the noise runs off a fixed seed, so the same patch renders the same bytes
/// on every device, which is what lets a sound be rebuilt rather than stored.
Float32List renderPatch(SynthPatch patch, int sampleRate) {
  final length = (patch.seconds * sampleRate).round();
  final out = Float64List(length);

  final decay = patch.decaySeconds;
  final start = patch.startHz;
  final end = patch.endHz;
  // The pitch falls over the first third of the note. Any longer and a kick
  // stops reading as a hit and starts reading as a slide.
  final glideTime = decay / 3;

  final level = 1 - patch.noise * 0.6;
  var phase = 0.0;
  for (var i = 0; i < length; i++) {
    final t = i / sampleRate;
    final freq = patch.hasBend ? glide(t, start, end, glideTime) : start;
    phase += freq / sampleRate;
    final v = waveSample(patch.wave, phase) * adEnvelope(t, 0.004, decay, level);
    out[i] = patch.drive > 0 ? saturate(v, patch.drive * 6) : v;
  }

  if (patch.noise > 0) {
    final noise = NoiseSource(7);
    final filter = Biquad()..bandpass(patch.toneHz, 1.2, sampleRate);
    for (var i = 0; i < length; i++) {
      final t = i / sampleRate;
      out[i] += filter.process(noise.next()) *
          adEnvelope(t, 0.002, decay, patch.noise);
    }
  }

  return finalise(out);
}
