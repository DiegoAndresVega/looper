import 'package:flutter_test/flutter_test.dart';
import 'package:looper/domain/chord.dart';
import 'package:looper/domain/scale.dart';

void main() {
  group('los grados de un acorde', () {
    test('sola es una nota y nada más', () {
      expect(ChordVoicing.single.degrees, [0]);
    });

    test('la tríada salta grados de la escala, no semitonos', () {
      // Terceras de la escala: el grado, dos más arriba y cuatro más arriba.
      // Sobre una escala, eso ya da mayor o menor solo, sin decidirlo nadie.
      expect(ChordVoicing.triad.degrees, [0, 2, 4]);
      expect(ChordVoicing.seventh.degrees, [0, 2, 4, 6]);
    });

    test('sobre una menor natural, la tríada del primer grado es menor', () {
      int noteAt(int degree) => semitonesForPad(
            degree,
            scale: Scale.minor,
            root: 0,
            octave: 0,
          );

      final triad = ChordVoicing.triad.degrees.map(noteAt).toList();

      // 0, 3, 7 desde la tónica: tercera menor y quinta justa.
      expect(triad, [0, 3, 7]);
    });

    test('sobre una mayor, la del primer grado es mayor', () {
      int noteAt(int degree) => semitonesForPad(
            degree,
            scale: Scale.major,
            root: 0,
            octave: 0,
          );

      expect(ChordVoicing.triad.degrees.map(noteAt).toList(), [0, 4, 7]);
    });
  });

  group('el orden del arpegio', () {
    test('apagado no reordena nada', () {
      expect(arpSequence([1, 2, 3], ArpMode.off), [1, 2, 3]);
    });

    test('sube', () {
      expect(arpSequence([1, 2, 3], ArpMode.up), [1, 2, 3]);
    });

    test('baja', () {
      expect(arpSequence([1, 2, 3], ArpMode.down), [3, 2, 1]);
    });

    test('sube y baja sin repetir los extremos', () {
      expect(arpSequence([1, 2, 3], ArpMode.upDown), [1, 2, 3, 2]);
    });

    test('con dos notas, subir y bajar son dos golpes, no cuatro', () {
      expect(arpSequence([1, 2], ArpMode.upDown), [1, 2]);
    });

    test('una sola nota no se arpegia', () {
      expect(arpSequence([7], ArpMode.upDown), [7]);
      expect(arpSequence([7], ArpMode.down), [7]);
    });

    test('sin notas no revienta', () {
      expect(arpSequence(<int>[], ArpMode.up), isEmpty);
    });

    test('el original se queda como estaba', () {
      final notes = [1, 2, 3];

      arpSequence(notes, ArpMode.down);

      expect(notes, [1, 2, 3]);
    });
  });

  group('cuándo sale cada nota del arpegio', () {
    test('reparten el paso a partes iguales', () {
      expect(arpOffsets(4), [0, 0.25, 0.5, 0.75]);
    });

    test('una sola nota sale a tiempo', () {
      expect(arpOffsets(1), [0]);
    });

    test('ninguna nota, ningún golpe', () {
      expect(arpOffsets(0), isEmpty);
    });
  });
}
