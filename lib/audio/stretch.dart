import 'dart:math' as math;
import 'dart:typed_data';

/// Time and pitch, pulled apart.
///
/// Everything pitched in this app has been tape until now: `setRelativePlaySpeed`
/// moves the tone and the tempo together, so an octave up is also twice as
/// fast. That is the ceiling the whole melodic half of the instrument sits
/// under, and this file is the way out of it — stretch the time without the
/// pitch, resample the pitch without the time, and do both to get one without
/// the other.
///
/// It is WSOLA: cut the sound into overlapping windows and lay them back down
/// closer together or further apart, sliding each one to where it lines up
/// best with what is already down. That last part is what keeps it from
/// sounding like a flanger — a plain overlap-add fights its own phase.
Float32List timeStretch(
  Float32List input,
  double ratio, {
  int frame = 1024,
  int search = 192,
}) {
  if (input.isEmpty) return Float32List(0);
  if ((ratio - 1).abs() < 1e-6) return Float32List.fromList(input);
  if (input.length < frame * 2) return Float32List.fromList(input);

  final hopOut = frame ~/ 2;
  final hopIn = math.max(1, (hopOut / ratio).round());
  final length = math.max(frame, (input.length * ratio).round());
  final out = Float64List(length + frame);
  final window = _hann(frame);

  var nominal = 0;
  var writePos = 0;

  while (writePos + frame <= out.length && nominal + frame < input.length) {
    // Slide the window to where it agrees with what has already been written.
    // A quarter of the overlap is enough to compare, and stepping by four
    // keeps the search cheap on a phone.
    var read = nominal;
    if (writePos > 0) {
      var bestScore = -double.maxFinite;
      for (var offset = -search; offset <= search; offset += 2) {
        final candidate = nominal + offset;
        if (candidate < 0 || candidate + hopOut >= input.length) continue;
        var score = 0.0;
        for (var i = 0; i < hopOut; i += 4) {
          score += input[candidate + i] * out[writePos + i];
        }
        if (score > bestScore) {
          bestScore = score;
          read = candidate;
        }
      }
    }

    final available = math.min(frame, input.length - read);
    for (var i = 0; i < available; i++) {
      out[writePos + i] += input[read + i] * window[i];
    }

    writePos += hopOut;
    nominal += hopIn;
  }

  return _toFloat32(out, length);
}

/// Reads the same samples at a different speed: [factor] of 2 makes it half
/// as long and an octave up, which is exactly what tape does.
///
/// Linear interpolation. A phone plays these back through a sample-rate
/// converter of its own anyway, and the difference at the ratios a musical
/// interval asks for is below what the material survives.
Float32List resample(Float32List input, double factor) {
  if (input.isEmpty || (factor - 1).abs() < 1e-9) {
    return Float32List.fromList(input);
  }
  final length = math.max(1, (input.length / factor).round());
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    final position = i * factor;
    final index = position.floor();
    if (index + 1 >= input.length) {
      out[i] = input[input.length - 1];
      continue;
    }
    final fraction = position - index;
    out[i] = input[index] * (1 - fraction) + input[index + 1] * fraction;
  }
  return out;
}

/// Moves the pitch and leaves the length alone: stretch it out by the
/// interval, then read it back faster by the same interval. The two errors
/// cancel in time and add in pitch, which is the whole trick.
Float32List pitchShift(Float32List input, int semitones) {
  if (semitones == 0 || input.isEmpty) return Float32List.fromList(input);
  final ratio = math.pow(2, semitones / 12).toDouble();
  return resample(timeStretch(input, ratio), ratio);
}

/// How much longer or shorter a sound has to get to run at [toBpm] when it
/// was played at [fromBpm].
double stretchRatioFor({required double fromBpm, required double toBpm}) =>
    fromBpm <= 0 || toBpm <= 0 ? 1 : fromBpm / toBpm;

Float64List _hann(int length) {
  final window = Float64List(length);
  for (var i = 0; i < length; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (length - 1));
  }
  return window;
}

Float32List _toFloat32(Float64List buffer, int length) {
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    out[i] = buffer[i].clamp(-1.0, 1.0);
  }
  return out;
}
