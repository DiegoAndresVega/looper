import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/state/sequencer.dart';

/// Builds a sequencer with a chord window short enough to await in a test.
({Sequencer seq, List<Set<String>> fired, List<int> saves}) build() {
  final fired = <Set<String>>[];
  final saves = <int>[];
  final seq = Sequencer(
    onNotes: fired.add,
    onPatternsChanged: () => saves.add(1),
    chordWindow: const Duration(milliseconds: 20),
  );
  return (seq: seq, fired: fired, saves: saves);
}

Future<void> afterChord() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('encender y apagar', () {
    test('arranca apagado y con dieciséis patrones vacíos', () {
      final t = build();

      expect(t.seq.isOn, isFalse);
      expect(t.seq.patterns.length, kPatternCount);
      expect(t.seq.pattern.isEmpty, isTrue);
    });

    test('apagar el secuenciador para la reproducción y la grabación', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.toggleOn();

      expect(t.seq.isOn, isFalse);
      expect(t.seq.isRecording, isFalse);
      expect(t.seq.isPlaying, isFalse);
    });

    test('grabar y reproducir no conviven', () {
      final t = build();
      t.seq.toggleOn();

      t.seq.toggleRecord();
      expect(t.seq.isRecording, isTrue);

      t.seq.togglePlay();
      expect(t.seq.isPlaying, isTrue);
      expect(t.seq.isRecording, isFalse);
    });
  });

  group('grabación en vivo', () {
    test('una nota cae en el paso actual y el paso avanza solo', () async {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.tap('0:5');
      expect(t.seq.pattern.at(0), {'0:5'});
      expect(t.seq.currentStep, 0, reason: 'aún no ha pasado la ventana');

      await afterChord();
      expect(t.seq.currentStep, 1);
    });

    test('varias notas seguidas caen en el mismo paso', () async {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.tap('0:0');
      t.seq.tap('0:4');
      t.seq.tap('1:2');
      await afterChord();

      expect(t.seq.pattern.at(0), {'0:0', '0:4', '1:2'});
      expect(t.seq.currentStep, 1);
    });

    test('el silencio avanza dejando el paso vacío', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.rest();

      expect(t.seq.pattern.at(0), isEmpty);
      expect(t.seq.currentStep, 1);
    });

    test('al llegar al final vuelve al primer paso', () async {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      for (var i = 0; i < kPatternSteps; i++) {
        t.seq.rest();
      }

      expect(t.seq.currentStep, 0);
    });

    test('sin grabar, tocar un pad no escribe nada', () {
      final t = build();
      t.seq.toggleOn();

      t.seq.tap('0:1');

      expect(t.seq.pattern.isEmpty, isTrue);
    });

    test('grabar avisa de que hay que guardar la sesión', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.tap('0:1');

      expect(t.saves, isNotEmpty);
    });
  });

  group('edición dirigida', () {
    test('elegir un paso y tocar un pad pone la nota ahí', () {
      final t = build();
      t.seq.toggleOn();

      t.seq.selectStep(9);
      t.seq.tap('2:3');

      expect(t.seq.pattern.at(9), {'2:3'});
      expect(t.seq.currentStep, 0, reason: 'la edición dirigida no avanza');
    });

    test('tocar el mismo pad otra vez quita la nota', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(4);

      t.seq.tap('0:2');
      t.seq.tap('0:2');

      expect(t.seq.pattern.at(4), isEmpty);
    });

    test('elegir el mismo paso dos veces sale de la edición', () {
      final t = build();
      t.seq.toggleOn();

      t.seq.selectStep(3);
      t.seq.selectStep(3);

      expect(t.seq.editingStep, isNull);
    });

    test('elegir un paso apaga la grabación en vivo', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.toggleRecord();

      t.seq.selectStep(2);

      expect(t.seq.isRecording, isFalse);
      expect(t.seq.editingStep, 2);
    });
  });

  group('reproducción', () {
    test('cada pulso dispara las notas de su paso', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0');
      t.seq.selectStep(1);
      t.seq.tap('0:7');
      t.seq.selectStep(null);
      t.seq.togglePlay();

      t.seq.tick();
      t.seq.tick();

      expect(t.fired.length, 2);
      expect(t.fired[0], {'0:0'});
      expect(t.fired[1], {'0:7'});
    });

    test('un paso vacío dispara silencio, no la nota anterior', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0');
      t.seq.selectStep(null);
      t.seq.togglePlay();

      t.seq.tick();
      t.seq.tick();

      expect(t.fired[1], isEmpty);
    });

    test('el paso da la vuelta al llegar al dieciséis', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.togglePlay();

      for (var i = 0; i < kPatternSteps; i++) {
        t.seq.tick();
      }

      expect(t.seq.currentStep, kPatternSteps - 1);
      t.seq.tick();
      expect(t.seq.currentStep, 0);
    });

    test('parar deja el cabezal en el primer paso', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.togglePlay();
      t.seq.tick();
      t.seq.tick();

      t.seq.togglePlay();

      expect(t.seq.isPlaying, isFalse);
      expect(t.seq.currentStep, 0);
    });

    test('sin reproducir, un pulso no dispara nada', () {
      final t = build();
      t.seq.toggleOn();

      t.seq.tick();

      expect(t.fired, isEmpty);
    });
  });

  group('patrones', () {
    test('cambiar de patrón cambia lo que se toca', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0');

      t.seq.selectPattern(1);

      expect(t.seq.patternIndex, 1);
      expect(t.seq.pattern.isEmpty, isTrue);

      t.seq.selectPattern(0);
      expect(t.seq.pattern.at(0), {'0:0'});
    });

    test('un índice de patrón imposible se ignora', () {
      final t = build();

      t.seq.selectPattern(kPatternCount);

      expect(t.seq.patternIndex, 0);
    });

    test('limpiar vacía solo el patrón activo', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0');
      t.seq.selectPattern(1);
      t.seq.selectStep(0);
      t.seq.tap('1:1');

      t.seq.clearPattern();

      expect(t.seq.pattern.isEmpty, isTrue);
      t.seq.selectPattern(0);
      expect(t.seq.pattern.at(0), {'0:0'});
    });

    test('con cadena, el compás siguiente pasa al patrón siguiente', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0'); // P1 marca el paso 1
      t.seq.selectPattern(1);
      t.seq.tap('1:1'); // el paso 0 sigue en edición al cambiar de patrón
      t.seq.selectStep(null);
      t.seq.chainLength = 2;
      t.seq.togglePlay();

      t.seq.tick();
      expect(t.seq.patternIndex, 0);
      expect(t.fired.last, {'0:0'});

      for (var i = 0; i < kPatternSteps; i++) {
        t.seq.tick();
      }
      expect(t.seq.patternIndex, 1);
      expect(t.fired.last, {'1:1'});
    });

    test('la cadena da la vuelta al acabar el último patrón', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.chainLength = 2;
      t.seq.togglePlay();

      for (var i = 0; i < kPatternSteps * 2; i++) {
        t.seq.tick();
      }
      t.seq.tick();

      expect(t.seq.patternIndex, 0);
    });

    test('darle al play con cadena empieza por el primer patrón', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectPattern(5);
      t.seq.chainLength = 4;

      t.seq.togglePlay();

      expect(t.seq.patternIndex, 0);
    });

    test('acortar la cadena en marcha recoloca el patrón dentro de ella', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.chainLength = 8;
      t.seq.togglePlay();
      for (var i = 0; i < kPatternSteps * 5; i++) {
        t.seq.tick();
      }
      expect(t.seq.patternIndex, 4);

      t.seq.chainLength = 2;

      expect(t.seq.patternIndex, lessThan(2));
    });

    test('sin cadena nada cambia de patrón al dar la vuelta', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectPattern(3);
      t.seq.togglePlay();

      for (var i = 0; i < kPatternSteps + 2; i++) {
        t.seq.tick();
      }

      expect(t.seq.patternIndex, 3);
    });

    test('cargar los patrones de una sesión reemplaza los que había', () {
      final t = build();
      t.seq.toggleOn();
      t.seq.selectStep(0);
      t.seq.tap('0:0');

      t.seq.load(t.seq.patterns.map((p) => p.cleared()).toList(), 2);

      expect(t.seq.pattern.isEmpty, isTrue);
      expect(t.seq.patternIndex, 2);
    });
  });
}
