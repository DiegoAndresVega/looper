import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/chopper.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/core/palette.dart';
import 'package:looper/domain/pad_config.dart';
import 'package:looper/domain/session.dart';
import 'package:looper/domain/sound.dart';

/// Cortar un sonido en trozos y repartirlos por la grilla.
///
/// La pieza barata: un corte **no copia audio**. `Sound` ya lleva recorte no
/// destructivo, así que los dieciséis trozos son dieciséis sonidos apuntando al
/// mismo fichero con distintos `trimStartMs`/`trimEndMs`. Eso obliga a una
/// regla nueva en la biblioteca —el fichero solo se borra cuando ya no lo usa
/// nadie— y esa regla se prueba aquí antes que nada.
void main() {
  /// Una envolvente con [hits] golpes claros repartidos: silencio, un pico y
  /// una caída, otra vez. Es lo que ve el detector.
  Float32List envelopeWithHits(int buckets, List<int> hits) {
    final env = Float32List(buckets);
    for (final at in hits) {
      for (var i = 0; i < 6 && at + i < buckets; i++) {
        env[at + i] = 1.0 - i * 0.16;
      }
    }
    return env;
  }

  group('cortes por divisiones', () {
    test('parte en trozos iguales', () {
      final trozos = sliceEvenly(durationMs: 1000, count: 4);

      expect(trozos.length, 4);
      expect(trozos[0].startMs, 0);
      expect(trozos[0].endMs, 250);
      expect(trozos[3].startMs, 750);
      expect(trozos[3].endMs, 1000);
    });

    test('el último trozo llega hasta el final aunque no divida exacto', () {
      final trozos = sliceEvenly(durationMs: 1000, count: 3);

      expect(trozos.length, 3);
      expect(trozos.first.startMs, 0);
      expect(trozos.last.endMs, 1000,
          reason: 'redondear no puede dejar audio fuera');
    });

    test('no deja trozos vacíos ni al pedir más de los que caben', () {
      final trozos = sliceEvenly(durationMs: 10, count: kPadsPerBank);

      for (final t in trozos) {
        expect(t.endMs, greaterThan(t.startMs));
      }
    });

    test('los trozos van seguidos, sin huecos ni solapes', () {
      final trozos = sliceEvenly(durationMs: 997, count: 7);

      for (var i = 1; i < trozos.length; i++) {
        expect(trozos[i].startMs, trozos[i - 1].endMs);
      }
    });
  });

  group('cortes por transitorios', () {
    test('encuentra los golpes de una envolvente', () {
      final env = envelopeWithHits(120, [0, 30, 60, 90]);

      final golpes = detectOnsets(env, maxOnsets: kPadsPerBank);

      expect(golpes, [0, 30, 60, 90]);
    });

    test('no parte un mismo golpe en varios', () {
      final env = envelopeWithHits(120, [0, 30, 60, 90]);

      final golpes = detectOnsets(env, maxOnsets: kPadsPerBank, minGap: 8);

      expect(golpes.length, 4);
    });

    test('una envolvente plana da un solo trozo', () {
      final env = Float32List.fromList(List.filled(120, 0.5));

      expect(detectOnsets(env, maxOnsets: kPadsPerBank), [0]);
    });

    test('siempre empieza en cero, aunque el primer golpe llegue tarde', () {
      final env = envelopeWithHits(120, [40, 80]);

      final golpes = detectOnsets(env, maxOnsets: kPadsPerBank);

      expect(golpes.first, 0, reason: 'lo de antes del primer golpe es un trozo');
    });

    test('no devuelve más de los que se le piden', () {
      final env = envelopeWithHits(200, [0, 20, 40, 60, 80, 100, 120, 140]);

      expect(detectOnsets(env, maxOnsets: 4).length, lessThanOrEqualTo(4));
    });

    test('los devuelve en orden de tiempo, no de fuerza', () {
      final env = Float32List(120);
      env[10] = 0.4;
      env[50] = 1.0;
      env[90] = 0.7;

      final golpes = detectOnsets(env, maxOnsets: 8);

      final ordenados = List<int>.of(golpes)..sort();
      expect(golpes, ordenados);
    });

    test('una envolvente vacía no revienta', () {
      expect(detectOnsets(Float32List(0), maxOnsets: 8), isEmpty);
    });
  });

  group('de golpes a trozos', () {
    test('cada golpe dura hasta el siguiente', () {
      final trozos = slicesFromOnsets(
        onsets: [0, 30, 60],
        buckets: 120,
        durationMs: 1200,
      );

      expect(trozos.length, 3);
      expect(trozos[0].startMs, 0);
      expect(trozos[0].endMs, 300);
      expect(trozos[1].startMs, 300);
      expect(trozos[2].endMs, 1200, reason: 'el último llega al final');
    });
  });

  group('el fichero se comparte entre los trozos', () {
    Sound sound(String id, {String file = 'a.wav'}) => Sound(
          id: id,
          name: id,
          family: SoundFamily.percussion,
          fileName: file,
          origin: SoundOrigin.imported,
          durationMs: 1000,
          sizeBytes: 100,
        );

    test('un fichero que otro sonido usa no se puede borrar', () {
      final quedan = [sound('b'), sound('c')];

      expect(isFileOrphaned('a.wav', quedan), isFalse);
    });

    test('un fichero que ya no usa nadie sí', () {
      final quedan = [sound('b', file: 'otro.wav')];

      expect(isFileOrphaned('a.wav', quedan), isTrue);
    });

    test('sin sonidos, el fichero está huérfano', () {
      expect(isFileOrphaned('a.wav', const []), isTrue);
    });
  });

  group('los trozos como sonidos', () {
    test('comparten fichero y se reparten el recorte', () {
      final origen = Sound(
        id: 'src',
        name: 'Vinilo',
        family: SoundFamily.texture,
        fileName: 'vinilo.wav',
        origin: SoundOrigin.imported,
        durationMs: 800,
        sizeBytes: 999,
      );

      final trozos = chopSound(
        source: origen,
        slices: sliceEvenly(durationMs: 800, count: 4),
        idFor: (i) => 'chop$i',
      );

      expect(trozos.length, 4);
      for (final t in trozos) {
        expect(t.fileName, 'vinilo.wav', reason: 'no se copia audio');
        expect(t.family, SoundFamily.texture);
        expect(t.durationMs, 800, reason: 'el fichero entero sigue durando eso');
      }
      expect(trozos[0].trimStartMs, 0);
      expect(trozos[0].trimEndMs, 200);
      expect(trozos[3].trimStartMs, 600);
      expect(trozos[3].trimEndMs, 800);
      expect(trozos[0].trimmedDurationMs, 200);
    });

    test('se numeran para distinguirlos en la biblioteca', () {
      final origen = Sound(
        id: 'src',
        name: 'Break',
        family: SoundFamily.percussion,
        fileName: 'b.wav',
        origin: SoundOrigin.imported,
        durationMs: 400,
        sizeBytes: 1,
      );

      final trozos = chopSound(
        source: origen,
        slices: sliceEvenly(durationMs: 400, count: 2),
        idFor: (i) => 'x$i',
      );

      expect(trozos[0].name, 'Break 1');
      expect(trozos[1].name, 'Break 2');
    });

    test('el recorte del origen acota los trozos', () {
      // Cortar un sonido ya recortado no puede sacar audio de fuera del
      // recorte: lo que se ve en la onda es lo que se parte.
      final origen = Sound(
        id: 'src',
        name: 'Trozo',
        family: SoundFamily.voice,
        fileName: 'v.wav',
        origin: SoundOrigin.recorded,
        durationMs: 1000,
        sizeBytes: 1,
        trimStartMs: 200,
        trimEndMs: 600,
      );

      final trozos = chopSound(
        source: origen,
        slices: sliceEvenly(durationMs: origen.trimmedDurationMs, count: 2),
        idFor: (i) => 'y$i',
      );

      expect(trozos[0].trimStartMs, 200);
      expect(trozos[0].trimEndMs, 400);
      expect(trozos[1].trimStartMs, 400);
      expect(trozos[1].trimEndMs, 600);
    });
  });

  group('dónde caen los trozos', () {
    Session withBankFull(Session s, int bank) {
      var next = s;
      for (var slot = 0; slot < kPadsPerBank; slot++) {
        next = next.withPad(bank, slot, const PadConfig(soundId: 'x'));
      }
      return next;
    }

    test('van al primer banco con sitio, empezando por C', () {
      // C es donde caen las cosas propias; A y B llevan el kit de fábrica.
      final sesion = Session.blank(id: 's', name: 'x');

      final hueco = findRoomFor(sesion, 16);

      expect(hueco?.bank, 2, reason: 'banco C');
      expect(hueco?.slot, 0);
    });

    test('salta a D cuando C no tiene sitio de sobra', () {
      var sesion = Session.blank(id: 's', name: 'x');
      sesion = sesion.withPad(2, 15, const PadConfig(soundId: 'algo'));

      expect(findRoomFor(sesion, 16)?.bank, 3, reason: 'banco D');
    });

    test('cabe un corte pequeño donde no cabía uno grande', () {
      var sesion = Session.blank(id: 's', name: 'x');
      sesion = sesion.withPad(2, 15, const PadConfig(soundId: 'algo'));

      expect(findRoomFor(sesion, 4)?.bank, 2);
      expect(findRoomFor(sesion, 4)?.slot, 0);
    });

    test('sin sitio en ningún banco devuelve nulo', () {
      var sesion = Session.blank(id: 's', name: 'x');
      for (var bank = 0; bank < kBankCount; bank++) {
        sesion = withBankFull(sesion, bank);
      }

      expect(findRoomFor(sesion, 2), isNull);
    });

    test('encuentra un hueco que no empieza en el primer pad', () {
      var sesion = Session.blank(id: 's', name: 'x');
      sesion = sesion.withPad(2, 0, const PadConfig(soundId: 'algo'));

      final hueco = findRoomFor(sesion, 8);

      expect(hueco?.bank, 2);
      expect(hueco?.slot, 1, reason: 'sigue habiendo quince seguidos detrás');
    });
  });

  group('de quién son los trozos', () {
    Sound factorySound() => Sound(
          id: 'f',
          name: 'Vinilo',
          family: SoundFamily.texture,
          fileName: 'vinilo.wav',
          origin: SoundOrigin.factory_,
          durationMs: 800,
          sizeBytes: 1,
        );

    test('un corte es tuyo aunque salga del kit de fábrica', () {
      // Heredar el origen dejaba los cortes sin botón de borrar y listados
      // bajo «Kit», que no es donde va algo que acabas de hacer.
      final trozos = chopSound(
        source: factorySound(),
        slices: sliceEvenly(durationMs: 800, count: 4),
        idFor: (i) => 'c$i',
      );

      for (final t in trozos) {
        expect(t.origin, SoundOrigin.recorded);
      }
    });

    test('sigue apuntando al fichero de fábrica, sin copiarlo', () {
      final trozos = chopSound(
        source: factorySound(),
        slices: sliceEvenly(durationMs: 800, count: 2),
        idFor: (i) => 'c$i',
      );

      expect(trozos.first.fileName, 'vinilo.wav');
    });

    test('borrar un corte no puede llevarse el fichero de fábrica', () {
      // El sonido de origen sigue en la biblioteca, así que el fichero no
      // está huérfano por mucho que se borre un trozo.
      final origen = factorySound();
      final trozos = chopSound(
        source: origen,
        slices: sliceEvenly(durationMs: 800, count: 2),
        idFor: (i) => 'c$i',
      );

      final quedan = [origen, trozos[1]];
      expect(isFileOrphaned('vinilo.wav', quedan), isFalse);
    });
  });
}
