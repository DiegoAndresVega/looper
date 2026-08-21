import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/scale.dart';

/// La rejilla como escala.
///
/// Es la vía más corta para que Looper deje de ser solo percusión: los mismos
/// dieciséis pads pasan a ser dieciséis grados de una escala, y el sonido
/// elegido se toca a esas alturas. Bloquear la escala es lo que permite que
/// alguien sin oído no toque una nota falsa — la promesa del README, «hacer
/// música sin saber producción», aplicada a la melodía.
///
/// Todo lo de aquí son semitonos respecto a la tónica. Quién los suena y cómo
/// es cosa del motor.
void main() {
  group('las escalas', () {
    test('todas empiezan en la tónica', () {
      for (final scale in Scale.values) {
        expect(scale.steps.first, 0, reason: '${scale.label} no empieza en 0');
      }
    });

    test('ninguna se sale de la octava ni retrocede', () {
      for (final scale in Scale.values) {
        for (var i = 1; i < scale.steps.length; i++) {
          expect(scale.steps[i], greaterThan(scale.steps[i - 1]),
              reason: '${scale.label} tiene grados desordenados');
        }
        expect(scale.steps.last, lessThan(12),
            reason: '${scale.label} se pasa de la octava');
      }
    });

    test('la mayor y la menor son las de toda la vida', () {
      expect(Scale.major.steps, [0, 2, 4, 5, 7, 9, 11]);
      expect(Scale.minor.steps, [0, 2, 3, 5, 7, 8, 10]);
    });

    test('las pentatónicas tienen cinco grados', () {
      expect(Scale.pentatonicMajor.steps.length, 5);
      expect(Scale.pentatonicMinor.steps.length, 5);
    });

    test('la cromática las tiene todas', () {
      expect(Scale.chromatic.steps.length, 12);
    });
  });

  group('la rejilla como grados', () {
    test('el primer pad es la tónica', () {
      expect(semitonesForPad(0, scale: Scale.major, root: 0, octave: 0), 0);
    });

    test('sube por los grados de la escala', () {
      // Do mayor: do, re, mi, fa...
      expect(semitonesForPad(1, scale: Scale.major, root: 0, octave: 0), 2);
      expect(semitonesForPad(2, scale: Scale.major, root: 0, octave: 0), 4);
      expect(semitonesForPad(3, scale: Scale.major, root: 0, octave: 0), 5);
    });

    test('al acabar la escala sigue una octava más arriba', () {
      // La mayor tiene siete grados: el octavo pad es la tónica +12.
      expect(semitonesForPad(7, scale: Scale.major, root: 0, octave: 0), 12);
      expect(semitonesForPad(8, scale: Scale.major, root: 0, octave: 0), 14);
    });

    test('la tónica desplaza la escala entera', () {
      // La menor empieza en la, tres semitonos por encima de fa#... o dicho
      // simple: mover la tónica mueve todo por igual.
      final enDo = semitonesForPad(3, scale: Scale.minor, root: 0, octave: 0);
      final enRe = semitonesForPad(3, scale: Scale.minor, root: 2, octave: 0);

      expect(enRe - enDo, 2);
    });

    test('la octava mueve doce semitonos', () {
      final base = semitonesForPad(5, scale: Scale.major, root: 0, octave: 0);
      final arriba = semitonesForPad(5, scale: Scale.major, root: 0, octave: 1);

      expect(arriba - base, 12);
    });

    test('la pentatónica menor cubre más de dos octavas en la rejilla', () {
      // Cinco grados por octava y dieciséis pads: tres octavas y pico. Es lo
      // que hace que una pentatónica en la grilla suene a solo y no a escala.
      final ultimo = semitonesForPad(kPadsPerBank - 1,
          scale: Scale.pentatonicMinor, root: 0, octave: 0);

      expect(ultimo, greaterThan(24));
    });

    test('un pad imposible no revienta', () {
      expect(semitonesForPad(-1, scale: Scale.major, root: 0, octave: 0), 0);
    });
  });

  group('cómo se llama cada pad', () {
    test('la tónica lleva el nombre de su nota', () {
      expect(noteName(0), 'Do');
      expect(noteName(2), 'Re');
      expect(noteName(4), 'Mi');
    });

    test('las alteraciones se escriben con sostenido', () {
      expect(noteName(1), 'Do#');
      expect(noteName(6), 'Fa#');
    });

    test('da la vuelta a la octava', () {
      expect(noteName(12), 'Do');
      expect(noteName(14), 'Re');
    });

    test('las notas graves no llevan tilde y las agudas sí', () {
      // Una comilla por octava por encima de la primera: se lee de un vistazo
      // en un pad de un centímetro.
      expect(padLabel(0, root: 0), 'Do');
      expect(padLabel(12, root: 0), "Do′");
      expect(padLabel(24, root: 0), "Do″");
    });
  });
}
