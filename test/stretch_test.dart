import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/bpm_detect.dart';
import 'package:looper/audio/stretch.dart';
import 'package:looper/core/constants.dart';

/// Un seno de [hz] durante [seconds], que es lo más fácil de mirar por dentro.
Float32List sine(double hz, double seconds, {int rate = kSampleRate}) {
  final out = Float32List((rate * seconds).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = math.sin(2 * math.pi * hz * i / rate) * 0.8;
  }
  return out;
}

/// Cuenta por dónde cruza el cero hacia arriba: en un tono puro, eso son sus
/// ciclos, y de ahí sale la frecuencia sin escribir una FFT.
double dominantHz(Float32List samples, int rate) {
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    if (samples[i - 1] <= 0 && samples[i] > 0) crossings++;
  }
  return crossings * rate / samples.length;
}

/// Un tren de golpes secos a [bpm].
Float32List clicks(double bpm, double seconds, {int rate = kSampleRate}) {
  final out = Float32List((rate * seconds).round());
  final period = (60 / bpm * rate).round();
  for (var start = 0; start < out.length; start += period) {
    for (var i = 0; i < 200 && start + i < out.length; i++) {
      out[start + i] = (1 - i / 200) * (i.isEven ? 0.9 : -0.9);
    }
  }
  return out;
}

void main() {
  group('estirar el tiempo', () {
    test('el doble de largo dura el doble', () {
      final input = sine(220, 0.5);

      final out = timeStretch(input, 2.0);

      expect(out.length, closeTo(input.length * 2, input.length * 0.02));
    });

    test('la mitad de largo dura la mitad', () {
      final input = sine(220, 0.5);

      final out = timeStretch(input, 0.5);

      expect(out.length, closeTo(input.length * 0.5, input.length * 0.02));
    });

    test('estirar no cambia el tono, que es para lo que existe', () {
      final input = sine(220, 0.5);

      final out = timeStretch(input, 1.6);

      expect(dominantHz(out, kSampleRate), closeTo(220, 12));
    });

    test('no estirar devuelve exactamente lo mismo', () {
      final input = sine(220, 0.2);

      expect(timeStretch(input, 1.0), input);
    });

    test('nada dentro, nada fuera', () {
      expect(timeStretch(Float32List(0), 2), isEmpty);
    });

    test('nunca se pasa de uno', () {
      final input = sine(220, 0.4);

      expect(timeStretch(input, 1.7).every((v) => v.abs() <= 1.0), isTrue);
    });
  });

  group('leerlo más deprisa', () {
    test('al doble de velocidad dura la mitad y suena una octava arriba', () {
      final input = sine(220, 0.4);

      final out = resample(input, 2.0);

      expect(out.length, closeTo(input.length / 2, 2));
      expect(dominantHz(out, kSampleRate), closeTo(440, 10));
    });
  });

  group('tono real', () {
    test('una octava arriba, y dura lo mismo', () {
      final input = sine(220, 0.5);

      final out = pitchShift(input, 12);

      expect(dominantHz(out, kSampleRate), closeTo(440, 25));
      expect(out.length, closeTo(input.length, input.length * 0.05));
    });

    test('una octava abajo, y dura lo mismo', () {
      final input = sine(440, 0.5);

      final out = pitchShift(input, -12);

      expect(dominantHz(out, kSampleRate), closeTo(220, 15));
      expect(out.length, closeTo(input.length, input.length * 0.05));
    });

    test('sin transponer, no toca el audio', () {
      final input = sine(220, 0.2);

      expect(pitchShift(input, 0), input);
    });
  });

  group('a qué tempo estirar', () {
    test('de cien a doscientos, la mitad de largo', () {
      expect(stretchRatioFor(fromBpm: 100, toBpm: 200), closeTo(0.5, 1e-9));
    });

    test('un tempo imposible no cambia nada', () {
      expect(stretchRatioFor(fromBpm: 0, toBpm: 120), 1);
    });
  });

  group('adivinar el tempo', () {
    test('un tren de golpes a 120 se lee como 120', () {
      expect(detectBpm(clicks(120, 4), kSampleRate), closeTo(120, 3));
    });

    test('y uno a 90, como 90', () {
      expect(detectBpm(clicks(90, 5), kSampleRate), closeTo(90, 3));
    });

    test('el silencio no tiene tempo', () {
      expect(detectBpm(Float32List(kSampleRate * 2), kSampleRate), isNull);
    });

    test('un sonido demasiado corto tampoco', () {
      expect(detectBpm(clicks(120, 0.2), kSampleRate), isNull);
    });
  });
}
