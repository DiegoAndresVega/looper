import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/state/sequencer.dart';

/// Las tres capas que le faltaban al paso: probabilidad, micro-timing y
/// ratchet. Siguen el molde exacto del acento — una lista de dieciséis valores
/// que siempre existe, un valor por defecto que suena como sonaba antes, y una
/// migración que abre lo viejo sin tocarlo.
///
/// La probabilidad decide si el paso suena esta vuelta. El micro-timing lo
/// adelanta o atrasa una fracción de paso sin mover el resto. El ratchet lo
/// subdivide en 2, 3 o 4 golpes. Juntas son lo que separa un patrón que se
/// repite idéntico de uno que respira.
void main() {
  group('el patrón guarda las tres capas', () {
    test('nacen neutras: siempre suena, a tiempo, un solo golpe', () {
      final p = Pattern.empty();

      for (var i = 0; i < kPatternSteps; i++) {
        expect(p.probabilityAt(i), 1.0);
        expect(p.nudgeAt(i), 0.0);
        expect(p.ratchetAt(i), 1);
      }
    });

    test('cada capa se escribe sin tocar a las demás', () {
      final p = Pattern.empty()
          .withProbability(3, 0.5)
          .withNudge(4, 0.25)
          .withRatchet(5, 3);

      expect(p.probabilityAt(3), closeTo(0.5, 0.001));
      expect(p.nudgeAt(3), 0.0);
      expect(p.ratchetAt(3), 1);
      expect(p.nudgeAt(4), closeTo(0.25, 0.001));
      expect(p.ratchetAt(5), 3);
    });

    test('se recortan a sus rangos', () {
      expect(Pattern.empty().withProbability(0, 0).probabilityAt(0),
          kProbabilityMin);
      expect(Pattern.empty().withProbability(0, 9).probabilityAt(0), 1.0);
      expect(Pattern.empty().withNudge(0, -2).nudgeAt(0), -kNudgeMax);
      expect(Pattern.empty().withNudge(0, 2).nudgeAt(0), kNudgeMax);
      expect(Pattern.empty().withRatchet(0, 0).ratchetAt(0), 1);
      expect(Pattern.empty().withRatchet(0, 99).ratchetAt(0), kRatchetMax);
    });

    test('vaciar un paso devuelve sus capas a neutro', () {
      final p = Pattern.empty()
          .withNote(6, '0:0')
          .withProbability(6, 0.3)
          .withNudge(6, -0.2)
          .withRatchet(6, 4)
          .clearedStep(6);

      expect(p.probabilityAt(6), 1.0);
      expect(p.nudgeAt(6), 0.0);
      expect(p.ratchetAt(6), 1);
    });

    test('escribir una nota no arrastra las capas de otro paso', () {
      final p = Pattern.empty().withRatchet(2, 4).withNote(9, '0:1');

      expect(p.ratchetAt(2), 4);
      expect(p.at(9), {'0:1'});
    });

    test('las capas sobreviven al disco', () {
      final original = Pattern.empty()
          .withNote(0, '0:0')
          .withProbability(0, 0.75)
          .withNudge(0, -0.25)
          .withRatchet(0, 2);

      final vuelta = Pattern.fromJson(original.toJson());

      expect(vuelta.probabilityAt(0), closeTo(0.75, 0.001));
      expect(vuelta.nudgeAt(0), closeTo(-0.25, 0.001));
      expect(vuelta.ratchetAt(0), 2);
    });

    test('un patrón guardado antes de las capas se abre neutro', () {
      final viejo = {
        'steps': [
          for (var i = 0; i < kPatternSteps; i++) i == 3 ? ['0:0'] : <String>[],
        ],
        'velocities': List.filled(kPatternSteps, 1.0),
      };

      final p = Pattern.fromJson(viejo);

      expect(p.at(3), {'0:0'});
      expect(p.probabilityAt(3), 1.0);
      expect(p.ratchetAt(3), 1);
    });
  });

  group('el secuenciador toca las capas', () {
    /// Un secuenciador con dado cargado: [rolls] se consumen en orden.
    ({Sequencer seq, List<StepPlay> heard}) build({List<double>? rolls}) {
      final heard = <StepPlay>[];
      var at = 0;
      final seq = Sequencer(
        onNotes: heard.add,
        onPatternsChanged: () {},
        random: rolls == null ? null : () => rolls[at++ % rolls.length],
      );
      return (seq: seq, heard: heard);
    }

    test('un paso normal sale sin retraso y con un golpe', () {
      final t = build();
      t.seq.load([Pattern.empty().withNote(0, '0:0')], 0);
      t.seq.togglePlay();

      t.seq.tick();

      expect(t.heard.single.notes, {'0:0'});
      expect(t.heard.single.offsetSteps, 0.0);
      expect(t.heard.single.ratchet, 1);
    });

    test('la probabilidad deja pasar o calla según el dado', () {
      final t = build(rolls: [0.9, 0.1]);
      t.seq.load([
        Pattern.empty().withNote(0, '0:0').withProbability(0, 0.5),
      ], 0);
      t.seq.togglePlay();

      t.seq.tick(); // dado 0.9 > 0.5 → calla
      for (var i = 0; i < kPatternSteps; i++) {
        t.seq.tick();
      }
      // segunda vuelta al paso 0: dado 0.1 <= 0.5 → suena

      expect(t.heard.first.notes, isEmpty, reason: 'la primera vuelta calla');
      expect(t.heard.last.notes, {'0:0'}, reason: 'la segunda suena');
    });

    test('un paso seguro no gasta dado', () {
      // Con probabilidad 1 no se tira: un patrón sin capas suena idéntico
      // pase lo que pase con el azar.
      final t = build(rolls: [0.99999]);
      t.seq.load([Pattern.empty().withNote(0, '0:0')], 0);
      t.seq.togglePlay();

      t.seq.tick();

      expect(t.heard.single.notes, {'0:0'});
    });

    test('el ratchet viaja con la emisión', () {
      final t = build();
      t.seq.load([Pattern.empty().withNote(0, '0:0').withRatchet(0, 3)], 0);
      t.seq.togglePlay();

      t.seq.tick();

      expect(t.heard.single.ratchet, 3);
    });

    test('el retraso positivo viaja como fracción de paso', () {
      final t = build();
      t.seq.load([Pattern.empty().withNote(0, '0:0').withNudge(0, 0.25)], 0);
      t.seq.togglePlay();

      t.seq.tick();

      expect(t.heard.single.offsetSteps, closeTo(0.25, 0.001));
    });

    test('el adelanto sale un pulso antes y no se repite', () {
      final t = build();
      t.seq.load([
        Pattern.empty()
            .withNote(0, '0:0')
            .withNote(1, '0:1')
            .withNudge(1, -0.25),
      ], 0);
      t.seq.togglePlay();

      t.seq.tick(); // paso 0: suena 0:0 y se adelanta 0:1 con offset 0.75
      t.seq.tick(); // paso 1: ya sonó, no se repite

      final withNotes = t.heard.where((p) => p.notes.isNotEmpty).toList();
      expect(withNotes, hasLength(2));
      expect(withNotes[1].notes, {'0:1'});
      expect(withNotes[1].offsetSteps, closeTo(0.75, 0.001));
    });

    test('un adelanto en el paso uno al arrancar suena a tiempo', () {
      // No hay pulso anterior desde el que adelantarlo: mejor a tiempo que
      // nunca.
      final t = build();
      t.seq.load([Pattern.empty().withNote(0, '0:0').withNudge(0, -0.3)], 0);
      t.seq.togglePlay();

      t.seq.tick();

      final sounded = t.heard.where((p) => p.notes.isNotEmpty);
      expect(sounded.single.notes, {'0:0'});
      expect(sounded.single.offsetSteps, 0.0);
    });

    test('el adelanto cruza el compás con la cadena puesta', () {
      // El paso 1 del patrón dos, adelantado, tiene que salir en el paso 16
      // del patrón uno.
      final t = build();
      final p1 = Pattern.empty();
      final p2 = Pattern.empty().withNote(0, '1:0').withNudge(0, -0.5);
      t.seq.load([p1, p2], 0);
      t.seq.chainLength = 2;
      t.seq.togglePlay();

      for (var i = 0; i < kPatternSteps; i++) {
        t.seq.tick();
      }

      final sounded = t.heard.where((p) => p.notes.isNotEmpty).toList();
      expect(sounded, hasLength(1));
      expect(sounded.single.notes, {'1:0'});
      expect(sounded.single.offsetSteps, closeTo(0.5, 0.001));
    });

    test('parar y arrancar olvida los adelantos pendientes', () {
      final t = build();
      t.seq.load([
        Pattern.empty().withNote(1, '0:1').withNudge(1, -0.25),
      ], 0);
      t.seq.togglePlay();
      t.seq.tick(); // adelanta el paso 1

      t.seq.togglePlay(); // parar
      t.seq.togglePlay(); // arrancar de cero
      t.seq.tick();
      t.seq.tick();

      // El paso 1 tiene que volver a adelantarse en la nueva pasada, no
      // quedarse mudo por un apunte viejo.
      final sounded = t.heard.where((p) => p.notes.isNotEmpty).toList();
      expect(sounded, hasLength(2));
    });
  });
}
