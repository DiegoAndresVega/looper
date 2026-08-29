import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/dsp.dart';
import 'package:looper/audio/synth_voice.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/synth_patch.dart';

void main() {
  group('los mandos, recortados', () {
    test('una posición fuera de rango se queda en el borde', () {
      const low = SynthPatch(pitch: -3, decay: -1, drive: -0.5);
      const high = SynthPatch(pitch: 9, decay: 4, drive: 2);

      expect(low.pitch, 0);
      expect(low.decay, 0);
      expect(low.drive, 0);
      expect(high.pitch, 1);
      expect(high.decay, 1);
      expect(high.drive, 1);
    });
  });

  group('de posición de mando a unidades reales', () {
    test('el tono recorre de cuarenta hercios a dos mil', () {
      expect(const SynthPatch(pitch: 0).startHz, closeTo(40, 0.01));
      expect(const SynthPatch(pitch: 1).startHz, closeTo(2000, 0.01));
    });

    test('el tono sube en proporciones, no en saltos iguales', () {
      // La mitad del recorrido cae en la media geométrica, no en la
      // aritmética: es lo que hace que la mitad de arriba del mando no sea
      // toda la misma octava.
      final medio = const SynthPatch(pitch: 0.5).startHz;

      expect(medio, closeTo(283, 1));
      expect(medio, lessThan((40 + 2000) / 2));
    });

    test('el centro del mando de caída no dobla el tono', () {
      const patch = SynthPatch(bend: 0.5);

      expect(patch.endHz, closeTo(patch.startHz, 0.01));
      expect(patch.hasBend, isFalse);
    });

    test('abajo del todo cae dos octavas; arriba, sube dos', () {
      expect(const SynthPatch(bend: 0).endHz,
          closeTo(const SynthPatch(bend: 0).startHz * 0.25, 0.01));
      expect(const SynthPatch(bend: 1).endHz,
          closeTo(const SynthPatch(bend: 1).startHz * 4, 0.01));
    });

    test('la caída va de treinta milisegundos a dos segundos', () {
      expect(const SynthPatch(decay: 0).decaySeconds, closeTo(0.03, 0.001));
      expect(const SynthPatch(decay: 1).decaySeconds, closeTo(2.0, 0.001));
    });
  });

  group('lo que sale por el altavoz', () {
    test('el buffer dura lo que dice el patch', () {
      const patch = SynthPatch(decay: 0.5);

      final samples = renderPatch(patch, kSampleRate);

      expect(
        samples.length,
        (patch.seconds * kSampleRate).round(),
      );
    });

    test('suena: no es un buffer de silencio', () {
      final samples = renderPatch(const SynthPatch(), kSampleRate);

      expect(samples.any((v) => v.abs() > 0.1), isTrue);
    });

    test('nunca se pasa de uno, que es donde empieza el recorte', () {
      final samples = renderPatch(
        const SynthPatch(drive: 1, noise: 1, wave: Wave.square),
        kSampleRate,
      );

      expect(samples.every((v) => v.abs() <= 1.0), isTrue);
    });

    test('empieza y acaba en silencio, así que no chasquea', () {
      final samples = renderPatch(const SynthPatch(), kSampleRate);

      expect(samples.first.abs(), lessThan(0.05));
      expect(samples.last.abs(), lessThan(0.05));
    });

    test('el ruido cambia el sonido, no solo el número', () {
      final seco = renderPatch(const SynthPatch(noise: 0), kSampleRate);
      final sucio = renderPatch(const SynthPatch(noise: 1), kSampleRate);

      expect(seco, isNot(equals(sucio)));
    });

    test('dos veces el mismo patch dan el mismo audio', () {
      // El kit de fábrica depende de esto: el ruido va con semilla fija para
      // que dos móviles rendericen bytes idénticos.
      const patch = SynthPatch(noise: 0.6);

      expect(renderPatch(patch, kSampleRate), renderPatch(patch, kSampleRate));
    });
  });

  group('el viaje a disco', () {
    test('un patch va y vuelve pasando por el texto', () {
      const patch = SynthPatch(
        wave: Wave.saw,
        pitch: 0.2,
        bend: 0.1,
        decay: 0.8,
        drive: 0.4,
        noise: 0.3,
        tone: 0.7,
      );

      final back = SynthPatch.fromJson(
        jsonDecode(jsonEncode(patch.toJson())) as Map<String, dynamic>,
      );

      expect(back.wave, Wave.saw);
      expect(back.pitch, closeTo(0.2, 1e-9));
      expect(back.decay, closeTo(0.8, 1e-9));
      expect(back.tone, closeTo(0.7, 1e-9));
    });

    test('un patch con basura dentro abre en el de fábrica', () {
      final back = SynthPatch.fromJson(const {'wave': 'loquesea'});

      expect(back.wave, Wave.sine);
      expect(back.pitch, closeTo(0.35, 1e-9));
    });
  });
}
