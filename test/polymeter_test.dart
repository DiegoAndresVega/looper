import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/state/sequencer.dart';

void main() {
  group('cada pista con su largo', () {
    test('sin tocar nada, todas miden un compás', () {
      final pattern = Pattern.empty().withNote(0, 'a');

      expect(pattern.lengthFor('a'), kPatternSteps);
      expect(pattern.isPolymetric, isFalse);
    });

    test('una pista de siete pasos se declara como tal', () {
      final pattern = Pattern.empty().withNote(0, 'a').withLength('a', 7);

      expect(pattern.lengthFor('a'), 7);
      expect(pattern.isPolymetric, isTrue);
    });

    test('el largo se recorta al compás', () {
      final pattern = Pattern.empty().withNote(0, 'a');

      expect(pattern.withLength('a', 0).lengthFor('a'), 1);
      expect(pattern.withLength('a', 99).lengthFor('a'), kPatternSteps);
    });

    test('volver a un compás deja de ser una excepción', () {
      final pattern =
          Pattern.empty().withNote(0, 'a').withLength('a', 5).withLength('a', 16);

      expect(pattern.isPolymetric, isFalse);
    });

    test('poner un largo no muta el patrón de partida', () {
      final pattern = Pattern.empty().withNote(0, 'a');

      pattern.withLength('a', 3);

      expect(pattern.lengthFor('a'), kPatternSteps);
    });
  });

  group('lo que suena en cada paso', () {
    test('con todo a dieciséis, es el paso de siempre', () {
      final pattern = Pattern.empty().withNote(3, 'a').withNote(3, 'b');

      expect(pattern.soundingAt(3), {'a', 'b'});
      expect(pattern.soundingAt(19), {'a', 'b'});
      expect(pattern.soundingAt(4), isEmpty);
    });

    test('una pista de siete se repite cada siete pasos', () {
      final pattern = Pattern.empty().withNote(0, 'a').withLength('a', 7);

      expect(pattern.soundingAt(0), {'a'});
      expect(pattern.soundingAt(7), {'a'});
      expect(pattern.soundingAt(14), {'a'});
      expect(pattern.soundingAt(3), isEmpty);
    });

    test('dos pistas de largos distintos se cruzan y se separan', () {
      // Un bombo de 16 contra un hat de 7: coinciden en el cero y tardan
      // 112 pasos —siete compases— en volver a coincidir. De eso va la
      // polimetría.
      final pattern = Pattern.empty()
          .withNote(0, 'bombo')
          .withNote(0, 'hat')
          .withLength('hat', 7);

      expect(pattern.soundingAt(0), {'bombo', 'hat'});
      expect(pattern.soundingAt(7), {'hat'});
      expect(pattern.soundingAt(16), {'bombo'});
      expect(pattern.soundingAt(112), {'bombo', 'hat'});
    });

    test('una nota escrita más allá del largo de su pista no suena nunca', () {
      final pattern = Pattern.empty().withNote(9, 'a').withLength('a', 4);

      for (var step = 0; step < 64; step++) {
        expect(pattern.soundingAt(step), isEmpty, reason: 'paso $step');
      }
    });

    test('un paso negativo no rompe nada', () {
      final pattern = Pattern.empty().withNote(0, 'a').withLength('a', 5);

      expect(pattern.soundingAt(-5), {'a'});
    });
  });

  group('el viaje a disco', () {
    test('los largos van y vuelven pasando por el texto', () {
      final pattern = Pattern.empty()
          .withNote(0, 'a')
          .withNote(1, 'b')
          .withLength('a', 7)
          .withLength('b', 3);

      final back = Pattern.fromJson(
        jsonDecode(jsonEncode(pattern.toJson())),
      );

      expect(back.lengthFor('a'), 7);
      expect(back.lengthFor('b'), 3);
    });

    test('un patrón de antes de la polimetría mide un compás entero', () {
      final back = Pattern.fromJson(const [
        ['a'],
        [],
      ]);

      expect(back.lengthFor('a'), kPatternSteps);
      expect(back.isPolymetric, isFalse);
    });

    test('borrar el patrón se lleva los largos con él', () {
      final pattern = Pattern.empty().withNote(0, 'a').withLength('a', 7);

      expect(pattern.cleared().isPolymetric, isFalse);
    });
  });

  group('el secuenciador, tocándolo', () {
    /// Un secuenciador con un patrón de dos pistas: el bombo a compás entero
    /// y el hat a siete pasos.
    ({Sequencer seq, List<Set<String>> fired}) build() {
      final fired = <Set<String>>[];
      final seq = Sequencer(
        onNotes: (play) => fired.add(play.notes),
        onPatternsChanged: () {},
      );
      final pattern = Pattern.empty()
          .withNote(0, 'bombo')
          .withNote(0, 'hat')
          .withLength('hat', 7);
      seq.load([pattern], 0);
      return (seq: seq, fired: fired);
    }

    test('el hat vuelve cada siete pasos y el bombo cada dieciséis', () {
      final t = build();
      t.seq.togglePlay();

      for (var i = 0; i < 17; i++) {
        t.seq.tick();
      }

      expect(t.fired[0], {'bombo', 'hat'});
      expect(t.fired[7], {'hat'});
      expect(t.fired[14], {'hat'});
      expect(t.fired[16], {'bombo'});
    });

    test('parar y volver a arrancar devuelve las dos pistas al cero', () {
      final t = build();
      t.seq.togglePlay();
      for (var i = 0; i < 9; i++) {
        t.seq.tick();
      }

      t.seq.togglePlay();
      t.seq.togglePlay();
      t.fired.clear();
      t.seq.tick();

      expect(t.fired.first, {'bombo', 'hat'});
    });
  });
}
