import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/data/factory_kit.dart';
import 'package:looper/domain/loop_length.dart';
import 'package:looper/domain/pad_config.dart';

void main() {
  group('largo de loop', () {
    test('las opciones fijas salen siempre', () {
      final choices = loopLengthChoices(kStepsPerBar);

      for (final option in kLoopLengthChoices) {
        expect(choices, contains(option));
      }
    });

    test('el largo que ya tiene el pad entra en la lista', () {
      final choices = loopLengthChoices(3);

      expect(choices, contains(3));
      expect(choices.length, kLoopLengthChoices.length + 1);
    });

    test('un largo que ya estaba no se duplica', () {
      final choices = loopLengthChoices(kLoopLengthChoices.first);

      expect(choices.length, kLoopLengthChoices.length);
    });

    test('las opciones salen ordenadas de menos a más', () {
      final choices = loopLengthChoices(7);

      final sorted = List<int>.of(choices)..sort();
      expect(choices, sorted);
    });

    test('todo pad de fábrica encuentra su largo entre las opciones', () {
      for (final pad in kAllFactoryPads) {
        expect(loopLengthChoices(pad.loopSteps).indexOf(pad.loopSteps),
            greaterThanOrEqualTo(0),
            reason: '${pad.name} se quedaría sin opción marcada');
      }
    });

    test('el largo por defecto de un pad vacío tiene opción', () {
      const pad = PadConfig();

      expect(loopLengthChoices(pad.loopSteps), contains(pad.loopSteps));
    });
  });

  group('etiqueta del largo', () {
    test('los tiempos enteros se escriben como número', () {
      expect(loopLengthLabel(4), '1');
      expect(loopLengthLabel(16), '4');
      expect(loopLengthLabel(32), '8');
    });

    test('medio tiempo se escribe con fracción', () {
      expect(loopLengthLabel(2), '½');
      expect(loopLengthLabel(6), '1½');
    });

    test('un valor raro cae en decimales en vez de romperse', () {
      expect(loopLengthLabel(3), '0.75');
    });
  });
}
