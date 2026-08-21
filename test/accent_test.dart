import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/domain/session.dart';
import 'package:looper/state/sequencer.dart';

/// El acento por paso: cada uno de los dieciséis pasos lleva su propia fuerza,
/// como los «16 Levels» del MPC. Un patrón donde todos los golpes pegan igual
/// suena a máquina; el acento es lo que lo devuelve a una mano.
///
/// La fuerza va por **paso**, no por nota: en esta app un pad *es* un paso, así
/// que la barra que se dibuja en el pad y el valor que se guarda son la misma
/// cosa. Un paso con bombo y hat a la vez pega con una sola fuerza, que es lo
/// que hace un baterista al dar los dos golpes con el mismo cuerpo.
void main() {
  group('el patrón guarda fuerza por paso', () {
    test('nace a tope, sin acentos', () {
      final p = Pattern.empty();

      for (var i = 0; i < kPatternSteps; i++) {
        expect(p.velocityAt(i), kVelocityMax);
      }
      expect(p.hasAccents, isFalse);
    });

    test('bajar un paso deja los demás como estaban', () {
      final p = Pattern.empty().withVelocity(4, 0.5);

      expect(p.velocityAt(4), closeTo(0.5, 0.001));
      expect(p.velocityAt(3), kVelocityMax);
      expect(p.velocityAt(5), kVelocityMax);
      expect(p.hasAccents, isTrue);
    });

    test('no muta el patrón de origen', () {
      final original = Pattern.empty();

      original.withVelocity(2, 0.3);

      expect(original.velocityAt(2), kVelocityMax);
    });

    test('recorta al rango audible', () {
      // Un paso a cero es un paso que no suena, y para eso está borrarlo.
      expect(Pattern.empty().withVelocity(0, 0).velocityAt(0), kVelocityMin);
      expect(Pattern.empty().withVelocity(0, 9).velocityAt(0), kVelocityMax);
    });

    test('un paso fuera de rango no rompe nada', () {
      final p = Pattern.empty();

      expect(p.velocityAt(-1), kVelocityMax);
      expect(p.velocityAt(kPatternSteps), kVelocityMax);
      expect(p.withVelocity(99, 0.2).hasAccents, isFalse);
    });

    test('vaciar un paso le devuelve su fuerza', () {
      final p = Pattern.empty()
          .withNote(6, '0:0')
          .withVelocity(6, 0.4)
          .clearedStep(6);

      expect(p.velocityAt(6), kVelocityMax);
      expect(p.at(6), isEmpty);
    });

    test('vaciar el patrón se lleva los acentos', () {
      final p = Pattern.empty().withVelocity(6, 0.4).cleared();

      expect(p.hasAccents, isFalse);
    });
  });

  group('el acento sobrevive al disco', () {
    test('un patrón con acentos va y vuelve entero', () {
      final original = Pattern.empty()
          .withNote(0, '0:0')
          .withNote(8, '1:3')
          .withVelocity(0, 1.0)
          .withVelocity(8, 0.45);

      final vuelta = Pattern.fromJson(original.toJson());

      expect(vuelta.at(0), {'0:0'});
      expect(vuelta.at(8), {'1:3'});
      expect(vuelta.velocityAt(8), closeTo(0.45, 0.001));
    });

    test('una sesión con acentos sobrevive al viaje real por disco', () {
      // `Session.fromJson(session.toJson())` no prueba lo que pasa de verdad:
      // en disco hay texto, y `jsonDecode` devuelve mapas y listas genéricos.
      // Saltarse ese paso fue lo que dejó pasar un cast que rompía *todas*
      // las sesiones guardadas al reabrir la app.
      final original = Session.blank(id: 's', name: 'Prueba').copyWith(
        patterns: [
          Pattern.empty().withNote(2, '0:0').withVelocity(2, 0.35),
          ...List.generate(kPatternCount - 1, (_) => Pattern.empty()),
        ],
        swing: 0.58,
      );

      final vuelta = Session.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(vuelta.patterns[0].at(2), {'0:0'});
      expect(vuelta.patterns[0].velocityAt(2), closeTo(0.35, 0.001));
      expect(vuelta.swing, closeTo(0.58, 0.001));
    });

    test('una sesión escrita antes del acento se abre entera', () {
      final viejo = {
        'id': 'v',
        'name': 'Vieja',
        'bpm': 100,
        'banks': Session.blank(id: 'v', name: 'Vieja')
            .banks
            .map((b) => b.toJson())
            .toList(),
        // El formato de patrón de antes: lista de listas, sin fuerzas.
        'patterns': [
          for (var i = 0; i < kPatternCount; i++)
            [
              for (var s = 0; s < kPatternSteps; s++)
                s == 1 && i == 0 ? ['0:0'] : <String>[],
            ],
        ],
        'activePattern': 0,
        'chainLength': 4,
        'createdAt': DateTime(2026).toIso8601String(),
        'updatedAt': DateTime(2026).toIso8601String(),
      };

      final s = Session.fromJson(
        jsonDecode(jsonEncode(viejo)) as Map<String, dynamic>,
      );

      expect(s.patterns[0].at(1), {'0:0'});
      expect(s.patterns[0].velocityAt(1), kVelocityMax);
      expect(s.chainLength, 4);
      expect(s.swing, kSwingDefault);
    });

    test('un patrón escrito antes del acento se abre a tope', () {
      // El formato viejo era una lista de listas, sin fuerzas.
      final viejo = [
        for (var i = 0; i < kPatternSteps; i++) i == 3 ? ['0:0'] : <String>[],
      ];

      final p = Pattern.fromJson(viejo);

      expect(p.at(3), {'0:0'});
      expect(p.velocityAt(3), kVelocityMax);
      expect(p.hasAccents, isFalse);
    });
  });

  group('el secuenciador toca con la fuerza del paso', () {
    test('entrega la fuerza del paso junto a sus notas', () {
      final oidos = <({Set<String> notes, double velocity})>[];
      final seq = Sequencer(
        onNotes: (notes, velocity) =>
            oidos.add((notes: notes, velocity: velocity)),
        onPatternsChanged: () {},
      );

      seq.load([
        Pattern.empty()
            .withNote(0, '0:0')
            .withNote(1, '0:1')
            .withVelocity(1, 0.3),
      ], 0);
      seq.togglePlay();

      seq.tick(); // paso 0
      seq.tick(); // paso 1

      expect(oidos[0].notes, {'0:0'});
      expect(oidos[0].velocity, kVelocityMax);
      expect(oidos[1].notes, {'0:1'});
      expect(oidos[1].velocity, closeTo(0.3, 0.001));
    });

    test('escribe el acento en el paso que se está editando', () {
      var guardado = 0;
      final seq = Sequencer(
        onNotes: (_, _) {},
        onPatternsChanged: () => guardado++,
      );
      seq.load([Pattern.empty()], 0);
      seq.toggleOn();
      seq.selectStep(5);

      seq.setStepVelocity(0.6);

      expect(seq.pattern.velocityAt(5), closeTo(0.6, 0.001));
      expect(guardado, greaterThan(0));
    });

    test('sin paso en edición no escribe nada', () {
      final seq = Sequencer(onNotes: (_, _) {}, onPatternsChanged: () {});
      seq.load([Pattern.empty()], 0);

      seq.setStepVelocity(0.2);

      expect(seq.pattern.hasAccents, isFalse);
    });
  });
}
