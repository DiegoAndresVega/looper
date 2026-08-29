import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/data/disk_space.dart';

void main() {
  group('cuándo avisar', () {
    test('con espacio de sobra, callado', () {
      expect(isSpaceLowFor(2 * kLowSpaceBytes), isFalse);
    });

    test('justo en el umbral todavía no avisa', () {
      expect(isSpaceLowFor(kLowSpaceBytes), isFalse);
    });

    test('por debajo del umbral, avisa', () {
      expect(isSpaceLowFor(kLowSpaceBytes - 1), isTrue);
    });

    test('sin saber cuánto queda, no se inventa un aviso', () {
      // La plataforma puede no contestar. Un aviso falso es peor que ninguno:
      // el jugador aprendería a ignorarlo.
      expect(isSpaceLowFor(null), isFalse);
    });
  });

  group('cómo se lee', () {
    test('los megas se cuentan en megas', () {
      expect(freeSpaceLabelFor(150 * 1024 * 1024), '150 MB');
    });

    test('a partir de un giga se cuenta en gigas, con un decimal', () {
      expect(freeSpaceLabelFor(1536 * 1024 * 1024), '1,5 GB');
    });

    test('sin dato, no hay etiqueta', () {
      expect(freeSpaceLabelFor(null), isNull);
    });
  });
}
