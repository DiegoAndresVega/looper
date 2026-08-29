import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/wav_decoder.dart';
import 'package:looper/core/palette.dart';
import 'package:looper/domain/sound.dart';

/// Un sonido cualquiera de un segundo, para mirarle los recortes.
Sound build({int trimStartMs = 0, int? trimEndMs, bool reversed = false}) =>
    Sound(
      id: 's',
      name: 'Voz',
      family: SoundFamily.voice,
      fileName: 'viejo.wav',
      origin: SoundOrigin.recorded,
      durationMs: 1000,
      sizeBytes: 100,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      reversed: reversed,
    );

void main() {
  group('dar la vuelta a las muestras', () {
    test('la última muestra pasa a ser la primera', () {
      // Valores exactos en coma flotante de 32 bits: comparar 0,1 aquí
      // mediría la precisión del formato, no la vuelta de las muestras.
      final samples = Float32List.fromList([0.125, 0.25, 0.5, -1]);

      final back = reversedSamples(samples);

      expect(back, [-1, 0.5, 0.25, 0.125]);
    });

    test('el original se queda como estaba', () {
      final samples = Float32List.fromList([0.25, 0.5]);

      reversedSamples(samples);

      expect(samples, [0.25, 0.5]);
    });

    test('un sonido vacío no revienta', () {
      expect(reversedSamples(Float32List(0)), isEmpty);
    });
  });

  group('la ventana, vista desde el otro lado', () {
    test('el recorte se refleja: lo que sobraba al final ahora sobra al principio', () {
      final sound = build(trimStartMs: 200, trimEndMs: 800);

      final back = sound.reversedOnto(fileName: 'nuevo.wav', sizeBytes: 200);

      expect(back.trimStartMs, 200);
      expect(back.trimEndMs, 800);
    });

    test('un recorte pegado al final se vuelve un recorte pegado al principio', () {
      final sound = build(trimStartMs: 0, trimEndMs: 300);

      final back = sound.reversedOnto(fileName: 'nuevo.wav', sizeBytes: 200);

      expect(back.trimStartMs, 700);
      expect(back.trimEndMs, 1000);
    });

    test('lo que se oye dura lo mismo del derecho que del revés', () {
      final sound = build(trimStartMs: 120, trimEndMs: 640);

      final back = sound.reversedOnto(fileName: 'nuevo.wav', sizeBytes: 200);

      expect(back.trimmedDurationMs, sound.trimmedDurationMs);
    });

    test('sin recorte no hay nada que reflejar', () {
      final sound = build();

      final back = sound.reversedOnto(fileName: 'nuevo.wav', sizeBytes: 200);

      expect(back.trimStartMs, 0);
      expect(back.trimEndMs, isNull);
    });
  });

  group('la identidad del sonido', () {
    test('cambia de fichero pero no de identidad', () {
      final sound = build();

      final back = sound.reversedOnto(fileName: 'nuevo.wav', sizeBytes: 200);

      expect(back.id, sound.id);
      expect(back.name, sound.name);
      expect(back.family, sound.family);
      expect(back.origin, sound.origin);
      expect(back.fileName, 'nuevo.wav');
      expect(back.sizeBytes, 200);
    });

    test('la marca dice hacia dónde va, y volver a darle la vuelta la quita', () {
      final sound = build();

      final back = sound.reversedOnto(fileName: 'a.wav', sizeBytes: 1);
      final again = back.reversedOnto(fileName: 'b.wav', sizeBytes: 1);

      expect(back.reversed, isTrue);
      expect(again.reversed, isFalse);
    });

    test('conserva volumen y tono', () {
      final sound = build().copyWith(volume: 0.4, semitones: -3);

      final back = sound.reversedOnto(fileName: 'a.wav', sizeBytes: 1);

      expect(back.volume, 0.4);
      expect(back.semitones, -3);
    });
  });

  group('el formato', () {
    test('la marca de invertido sobrevive al disco', () {
      final sound = build(reversed: true);

      final back = Sound.fromJson(
        jsonDecode(jsonEncode(sound.toJson())) as Map<String, dynamic>,
      );

      expect(back.reversed, isTrue);
    });

    test('un sonido guardado con el campo muerto de fundido sigue abriendo', () {
      final json = Map<String, dynamic>.of(build().toJson())..['fadeMs'] = 40;

      final back = Sound.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );

      expect(back.name, 'Voz');
    });
  });
}
