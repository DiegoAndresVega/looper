import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/ui/pads/pad_tile.dart';

/// Cuántas lucecitas lleva un paso.
///
/// Una sola luz solo sabía decir «aquí hay algo». Un paso puede llevar bombo y
/// palma a la vez, y saber *cuántas* voces caen en un tiempo es la mitad de
/// leer un patrón — sobre todo al escribir acordes, que es justo lo que la
/// ventana de acorde del REC en vivo existe para permitir.
void main() {
  group('lucecitas de paso', () {
    test('un paso vacío no enciende ninguna', () {
      expect(stepDotsFor(notes: 0, editing: false, head: false), 0);
    });

    test('el cabezal se ve pasar por un paso vacío', () {
      // Si no, el cabezal parpadearía apagándose en cada silencio y se
      // perdería de vista dónde va el compás.
      expect(stepDotsFor(notes: 0, editing: false, head: true), 1);
    });

    test('el paso en edición se marca aunque esté vacío', () {
      // Si no, elegir una casilla vacía no se vería en ninguna parte.
      expect(stepDotsFor(notes: 0, editing: true, head: false), 1);
    });

    test('una luz por sonido', () {
      expect(stepDotsFor(notes: 1, editing: false, head: false), 1);
      expect(stepDotsFor(notes: 2, editing: false, head: false), 2);
      expect(stepDotsFor(notes: 3, editing: false, head: false), 3);
    });

    test('cuenta igual mientras se edita', () {
      expect(stepDotsFor(notes: 2, editing: true, head: false), 2);
    });

    test('no pasa del tope que cabe en la esquina del pad', () {
      expect(stepDotsFor(notes: kMaxStepDots + 1, editing: false, head: false), kMaxStepDots);
      expect(stepDotsFor(notes: 64, editing: false, head: false), kMaxStepDots);
    });

    test('el tope deja sitio al punto de familia', () {
      // Cuatro luces de 6 px con 2,5 de separación son 31,5 px; el punto de
      // familia vive en la esquina de enfrente. Más de cuatro se tocarían.
      expect(kMaxStepDots, lessThanOrEqualTo(4));
    });
  });
}
