import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';

void main() {
  group('patrón', () {
    test('nace con dieciséis pasos vacíos', () {
      final pattern = Pattern.empty();

      expect(pattern.steps.length, kPatternSteps);
      expect(pattern.isEmpty, isTrue);
      expect(pattern.filledSteps, 0);
    });

    test('poner una nota no toca el patrón original', () {
      final original = Pattern.empty();

      final updated = original.withNote(0, '0:3');

      expect(original.at(0), isEmpty);
      expect(updated.at(0), {'0:3'});
      expect(updated.isEmpty, isFalse);
    });

    test('un paso admite varias notas a la vez', () {
      final chord = Pattern.empty()
          .withNote(4, '0:0')
          .withNote(4, '0:8')
          .withNote(4, '1:2');

      expect(chord.at(4).length, 3);
      expect(chord.filledSteps, 1);
    });

    test('la misma nota dos veces no se duplica', () {
      final pattern = Pattern.empty().withNote(2, '0:1').withNote(2, '0:1');

      expect(pattern.at(2).length, 1);
    });

    test('alternar quita la nota que ya estaba', () {
      final pattern = Pattern.empty().withNote(7, '0:5');

      final toggled = pattern.toggled(7, '0:5');

      expect(toggled.at(7), isEmpty);
      expect(toggled.isEmpty, isTrue);
    });

    test('alternar pone la nota que faltaba', () {
      final toggled = Pattern.empty().toggled(9, '2:11');

      expect(toggled.at(9), {'2:11'});
    });

    test('vaciar un paso deja los demás como estaban', () {
      final pattern =
          Pattern.empty().withNote(0, '0:0').withNote(1, '0:1');

      final cleared = pattern.clearedStep(0);

      expect(cleared.at(0), isEmpty);
      expect(cleared.at(1), {'0:1'});
    });

    test('vaciar el patrón entero lo deja como recién nacido', () {
      final pattern = Pattern.empty().withNote(3, '0:3').withNote(12, '1:0');

      expect(pattern.cleared().isEmpty, isTrue);
    });

    test('un paso fuera de rango no rompe nada', () {
      final pattern = Pattern.empty();

      expect(pattern.withNote(kPatternSteps, '0:0').isEmpty, isTrue);
      expect(pattern.withNote(-1, '0:0').isEmpty, isTrue);
      expect(pattern.at(99), isEmpty);
    });

    test('quitar una nota que nunca estuvo no cambia nada', () {
      final pattern = Pattern.empty().withNote(1, '0:1');

      expect(pattern.withoutNote(1, '0:9').at(1), {'0:1'});
    });

    test('el patrón sobrevive a un viaje por JSON', () {
      final original = Pattern.empty()
          .withNote(0, '0:0')
          .withNote(0, '1:4')
          .withNote(15, '3:15');

      final restored = Pattern.fromJson(original.toJson());

      expect(restored.at(0), {'0:0', '1:4'});
      expect(restored.at(15), {'3:15'});
      expect(restored.filledSteps, 2);
    });

    test('un JSON corto se completa hasta dieciséis pasos', () {
      final restored = Pattern.fromJson([
        ['0:0'],
        <String>[],
      ]);

      expect(restored.steps.length, kPatternSteps);
      expect(restored.at(0), {'0:0'});
      expect(restored.at(15), isEmpty);
    });

    test('las notas de un paso no se pueden cambiar desde fuera', () {
      final pattern = Pattern.empty().withNote(0, '0:0');

      expect(() => pattern.at(0).add('0:1'), throwsUnsupportedError);
    });
  });
}
