import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/wav_decoder.dart';
import 'package:looper/audio/wav_encoder.dart';
import 'package:looper/core/constants.dart';

/// Builds a 32-bit float WAV by hand — the shape flutter_recorder writes when
/// the capture device is opened in f32le.
Uint8List encodeFloatWav(Float32List samples, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 32;
  final dataBytes = samples.length * 4;
  final bytes = BytesBuilder();
  final header = ByteData(44);

  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      header.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 3, Endian.little); // IEEE float
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 4, Endian.little);
  header.setUint16(32, 4, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  bytes.add(header.buffer.asUint8List());

  final pcm = ByteData(dataBytes);
  for (var i = 0; i < samples.length; i++) {
    pcm.setFloat32(i * 4, samples[i], Endian.little);
  }
  bytes.add(pcm.buffer.asUint8List());
  return bytes.toBytes();
}

Float32List sine(int count, {double freq = 220, int sampleRate = kSampleRate}) {
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = 0.5 * math.sin(2 * math.pi * freq * i / sampleRate);
  }
  return out;
}

void main() {
  group('decodificar WAV', () {
    test('un WAV de 16 bits vuelve con las mismas muestras', () {
      final original = sine(1000);

      final decoded = decodeWav(encodeWav(original, sampleRate: kSampleRate));

      expect(decoded.sampleRate, kSampleRate);
      expect(decoded.channels, 1);
      expect(decoded.samples.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(decoded.samples[i], closeTo(original[i], 1 / 32767));
      }
    });

    test('un WAV de 32 bits float se lee igual de bien', () {
      final original = sine(500);

      final decoded =
          decodeWav(encodeFloatWav(original, sampleRate: kSampleRate));

      expect(decoded.samples.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(decoded.samples[i], closeTo(original[i], 1e-6));
      }
    });

    test('la duración sale del número de muestras', () {
      final decoded = decodeWav(
        encodeWav(Float32List(kSampleRate ~/ 2), sampleRate: kSampleRate),
      );

      expect(decoded.durationMs, 500);
    });

    test('un estéreo se mezcla a mono promediando los canales', () {
      final interleaved = Float32List.fromList([1.0, 0.0, 0.5, -0.5, 1.0, 1.0]);
      final stereo =
          encodeWav(interleaved, sampleRate: kSampleRate, channels: 2);

      final decoded = decodeWav(stereo);

      expect(decoded.channels, 2);
      expect(decoded.samples.length, 3);
      expect(decoded.samples[0], closeTo(0.5, 1e-3));
      expect(decoded.samples[1], closeTo(0.0, 1e-3));
      expect(decoded.samples[2], closeTo(1.0, 1e-3));
    });

    test('unos bytes que no son WAV dan un error con nombre', () {
      final garbage = Uint8List.fromList(List<int>.filled(100, 7));

      expect(() => decodeWav(garbage), throwsA(isA<WavFormatException>()));
    });

    test('un archivo cortado a medias no revienta con un error genérico', () {
      final truncated =
          encodeWav(sine(1000), sampleRate: kSampleRate).sublist(0, 30);

      expect(() => decodeWav(truncated), throwsA(isA<WavFormatException>()));
    });
  });

  group('forma de onda', () {
    test('la envolvente tiene tantos valores como se piden', () {
      final peaks = peakEnvelope(sine(10000), 40);

      expect(peaks.length, 40);
      for (final p in peaks) {
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });

    test('un tramo en silencio se dibuja plano', () {
      final samples = Float32List(2000);
      for (var i = 1000; i < 2000; i++) {
        samples[i] = 0.8;
      }

      final peaks = peakEnvelope(samples, 4);

      expect(peaks[0], 0.0);
      expect(peaks[3], closeTo(0.8, 1e-6));
    });

    test('con menos muestras que cubos no se sale de rango', () {
      final peaks = peakEnvelope(Float32List.fromList([0.5, -0.9]), 16);

      expect(peaks.length, 16);
      expect(peaks.reduce(math.max), closeTo(0.9, 1e-6));
    });

    test('sin muestras devuelve una línea a cero', () {
      final peaks = peakEnvelope(Float32List(0), 8);

      expect(peaks.length, 8);
      expect(peaks.every((p) => p == 0.0), isTrue);
    });
  });

  group('normalizar', () {
    test('una toma floja sube hasta el pico pedido', () {
      final quiet = Float32List.fromList([0.1, -0.05, 0.02]);

      final loud = normalized(quiet, peak: 0.9);

      expect(loud.reduce((a, b) => math.max(a.abs(), b.abs())), closeTo(0.9, 1e-6));
      expect(loud[1] / loud[0], closeTo(quiet[1] / quiet[0], 1e-6));
    });

    test('el silencio se queda en silencio en vez de dividir por cero', () {
      final silence = Float32List(64);

      final result = normalized(silence, peak: 0.9);

      expect(result.every((s) => s == 0.0), isTrue);
    });

    test('una toma que ya llega al tope no se toca', () {
      final hot = Float32List.fromList([0.9, -0.9, 0.45]);

      final result = normalized(hot, peak: 0.9);

      for (var i = 0; i < hot.length; i++) {
        expect(result[i], closeTo(hot[i], 1e-6));
      }
    });
  });

  group('límite de diez segundos', () {
    test('una toma más larga se corta y el resto se descarta', () {
      final long = Float32List(kSampleRate * 12);
      for (var i = 0; i < long.length; i++) {
        long[i] = 0.4;
      }

      final capped = capToMaxDuration(long, sampleRate: kSampleRate);

      expect(capped.length, kSampleRate * kMaxRecordDuration.inSeconds);
    });

    test('una toma corta pasa entera', () {
      final short = Float32List(kSampleRate * 3);

      final capped = capToMaxDuration(short, sampleRate: kSampleRate);

      expect(capped.length, short.length);
    });
  });
}
