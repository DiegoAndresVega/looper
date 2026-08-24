import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/knob_scale.dart';

/// Las conversiones de posición de mando a valor, que ahora tienen dos
/// clientes: el pulgar en la pantalla y un mando físico aprendido. Si estas
/// cuentas viven en dos sitios, el día que una escala gane un grado el
/// controlador y la pantalla dejan de decir lo mismo.
void main() {
  group('mandos que son interruptores', () {
    test('el centro exacto está apagado', () {
      expect(knobAsSwitch(0.5), isFalse);
      expect(knobAsSwitch(0.51), isTrue);
    });

    test('ida y vuelta', () {
      expect(knobAsSwitch(switchAsKnob(true)), isTrue);
      expect(knobAsSwitch(switchAsKnob(false)), isFalse);
    });
  });

  group('mandos que eligen de una lista', () {
    test('los extremos son el primero y el último', () {
      expect(knobAsIndex(0, 5), 0);
      expect(knobAsIndex(1, 5), 4);
    });

    test('cada opción cae en su hueco', () {
      for (var i = 0; i < 5; i++) {
        expect(knobAsIndex(indexAsKnob(i, 5), 5), i, reason: 'opción $i');
      }
    });

    test('una sola opción no divide por cero', () {
      expect(knobAsIndex(0.7, 1), 0);
      expect(indexAsKnob(0, 1), 0);
    });

    test('fuera de rango se recorta en vez de reventar', () {
      expect(knobAsIndex(2.0, 4), 3);
      expect(knobAsIndex(-1.0, 4), 0);
      expect(indexAsKnob(9, 4), 1);
    });
  });

  group('tono', () {
    test('el centro es el sonido tal cual se grabó', () {
      expect(knobAsSemitones(0.5), 0);
    });

    test('los extremos son una octava a cada lado', () {
      expect(knobAsSemitones(0), -kPadPitchRange);
      expect(knobAsSemitones(1), kPadPitchRange);
    });

    test('cada semitono vuelve a sí mismo', () {
      for (var s = -kPadPitchRange; s <= kPadPitchRange; s++) {
        expect(knobAsSemitones(semitonesAsKnob(s)), s, reason: '$s semitonos');
      }
    });
  });

  group('panorama', () {
    test('el centro del mando es el centro del campo', () {
      expect(knobAsPan(0.5), 0);
    });

    test('hay zona muerta alrededor del centro', () {
      // Un pad al dos por ciento del centro es el centro: encontrarlo con el
      // pulgar tiene que ser posible.
      expect(knobAsPan(0.51), 0);
      expect(knobAsPan(0.49), 0);
      expect(knobAsPan(0.6), closeTo(0.2, 0.0001));
    });

    test('los extremos son izquierda del todo y derecha del todo', () {
      expect(knobAsPan(0), -1);
      expect(knobAsPan(1), 1);
      expect(panAsKnob(-1), 0);
      expect(panAsKnob(1), 1);
    });
  });

  group('tónica', () {
    test('las doce notas tienen su parada', () {
      for (var root = 0; root < 12; root++) {
        expect(knobAsRoot(rootAsKnob(root)), root, reason: 'tónica $root');
      }
    });

    test('una tónica fuera de la octava vuelve dentro', () {
      expect(rootAsKnob(14), rootAsKnob(2));
    });
  });
}
