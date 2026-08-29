import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/data/starter_pattern.dart';
import 'package:looper/state/session_controller.dart';

void main() {
  group('el compás que ya viene escrito', () {
    test('son dos patrones, y el segundo no es el primero', () {
      final patterns = starterPatterns();

      expect(patterns.length, 2);
      expect(patterns[0].toJson(), isNot(equals(patterns[1].toJson())));
    });

    test('el bombo cae en las cuatro negras', () {
      final beat = starterPatterns().first;

      for (final step in [0, 4, 8, 12]) {
        expect(beat.has(step, '0:0'), isTrue, reason: 'paso $step');
      }
    });

    test('la caja va en el dos y en el cuatro', () {
      final beat = starterPatterns().first;

      expect(beat.has(4, '0:1'), isTrue);
      expect(beat.has(12, '0:1'), isTrue);
      expect(beat.has(0, '0:1'), isFalse);
    });

    test('los contratiempos del hat pegan más flojo', () {
      final beat = starterPatterns().first;

      expect(beat.velocityAt(0), kVelocityMax);
      expect(beat.velocityAt(2), lessThan(kVelocityMax));
    });

    test('todas las notas apuntan a un pad que existe', () {
      for (final pattern in starterPatterns()) {
        for (var step = 0; step < kPatternSteps; step++) {
          for (final note in pattern.at(step)) {
            expect(parsePadKey(note), isNotNull, reason: note);
          }
        }
      }
    });

    test('todas las notas están en el banco A, que es el que se ve al abrir', () {
      for (final pattern in starterPatterns()) {
        for (var step = 0; step < kPatternSteps; step++) {
          for (final note in pattern.at(step)) {
            expect(parsePadKey(note)!.bank, 0);
          }
        }
      }
    });

    test('el segundo patrón trae las capas que hay que descubrir', () {
      final variation = starterPatterns()[1];

      expect(variation.probabilityAt(14), lessThan(1.0));
      expect(variation.ratchetAt(2), greaterThan(1));
    });
  });
}
