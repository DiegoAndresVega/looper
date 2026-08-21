import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pad_config.dart';
import 'package:looper/domain/save_point.dart';
import 'package:looper/domain/session.dart';

/// Puntos de guardado: instantáneas con nombre dentro de una sesión.
///
/// Deshacer camina hacia atrás paso a paso; esto es lo otro que hace falta —
/// «así sonaba antes de ponerme a cambiarlo todo». La sesión se guarda sola
/// 800 ms después de cada edición, así que sin esto no hay ninguna forma de
/// volver a un estado que valía la pena.
///
/// La regla que sostiene todo lo demás: **restaurar no cambia la identidad de
/// la sesión**. Vuelve el contenido; el id y el nombre siguen siendo los de
/// la sesión abierta, o la lista de sesiones se quedaría apuntando a un
/// fantasma.
void main() {
  Session sessionWith(String id, {int bpm = 92, String? soundOnPad}) {
    var s = Session.blank(id: id, name: 'Prueba');
    s = s.copyWith(bpm: bpm);
    if (soundOnPad != null) {
      s = s.withPad(0, 0, PadConfig(soundId: soundOnPad));
    }
    return s;
  }

  group('capturar', () {
    test('guarda el estado tal y como estaba', () {
      final antes = sessionWith('s', bpm: 100, soundOnPad: 'bombo');

      final punto = SavePoint.capture(antes, name: 'Base');

      expect(punto.session.bpm, 100);
      expect(punto.session.padAt(0, 0).soundId, 'bombo');
      expect(punto.name, 'Base');
      expect(punto.sessionId, 's');
    });

    test('la instantánea no se entera de lo que pase después', () {
      final antes = sessionWith('s', bpm: 100);
      final punto = SavePoint.capture(antes, name: 'Base');

      antes.copyWith(bpm: 180).withPad(0, 0, const PadConfig(soundId: 'x'));

      expect(punto.session.bpm, 100);
      expect(punto.session.padAt(0, 0).isEmpty, isTrue);
    });

    test('cada punto estrena identidad', () {
      final s = sessionWith('s');

      final a = SavePoint.capture(s, name: 'Uno');
      final b = SavePoint.capture(s, name: 'Dos');

      expect(a.id, isNot(b.id));
    });
  });

  group('restaurar', () {
    test('devuelve el contenido de la instantánea', () {
      final punto = SavePoint.capture(
        sessionWith('s', bpm: 100, soundOnPad: 'bombo'),
        name: 'Base',
      );
      final ahora = sessionWith('s', bpm: 180);

      final vuelta = punto.restoreOnto(ahora);

      expect(vuelta.bpm, 100);
      expect(vuelta.padAt(0, 0).soundId, 'bombo');
    });

    test('no cambia la identidad de la sesión abierta', () {
      // Lo que impide que la lista de sesiones se quede apuntando a un
      // fantasma, y que restaurar duplique una sesión sin querer.
      final punto = SavePoint.capture(sessionWith('viejo'), name: 'Base');
      final ahora = Session.blank(id: 'actual', name: 'Como se llama ahora');

      final vuelta = punto.restoreOnto(ahora);

      expect(vuelta.id, 'actual');
      expect(vuelta.name, 'Como se llama ahora');
      expect(vuelta.createdAt, ahora.createdAt);
    });

    test('marca la sesión como tocada, para que se escriba a disco', () {
      final punto = SavePoint.capture(sessionWith('s'), name: 'Base');
      final ahora = sessionWith('s');

      final vuelta = punto.restoreOnto(ahora);

      expect(vuelta.updatedAt.isAfter(ahora.updatedAt) ||
          vuelta.updatedAt.isAtSameMomentAs(ahora.updatedAt), isTrue);
    });
  });

  group('la lista, acotada y por sesión', () {
    test('los más nuevos primero', () {
      final s = sessionWith('s');
      final lista = [
        SavePoint.capture(s, name: 'Uno'),
        SavePoint.capture(s, name: 'Dos'),
      ];

      final ordenada = sortedSavePoints(lista);

      expect(ordenada.first.name, 'Dos');
    });

    test('al pasarse del tope cae el más viejo', () {
      final s = sessionWith('s');
      var lista = <SavePoint>[];
      for (var i = 1; i <= kSavePointsPerSession + 2; i++) {
        lista = withSavePoint(lista, SavePoint.capture(s, name: 'P$i'));
      }

      expect(lista.where((p) => p.sessionId == 's'), hasLength(kSavePointsPerSession));
      expect(lista.any((p) => p.name == 'P1'), isFalse);
      expect(lista.any((p) => p.name == 'P${kSavePointsPerSession + 2}'), isTrue);
    });

    test('el tope es por sesión, no en total', () {
      // Llenar una sesión de puntos no puede borrar los de otra.
      var lista = <SavePoint>[];
      for (var i = 0; i < kSavePointsPerSession + 3; i++) {
        lista = withSavePoint(lista, SavePoint.capture(sessionWith('a'), name: 'a$i'));
      }
      lista = withSavePoint(lista, SavePoint.capture(sessionWith('b'), name: 'b'));

      expect(lista.where((p) => p.sessionId == 'b'), hasLength(1));
      expect(lista.where((p) => p.sessionId == 'a'),
          hasLength(kSavePointsPerSession));
    });

    test('el tope de fábrica deja margen para una tarde', () {
      expect(kSavePointsPerSession, greaterThanOrEqualTo(5));
    });
  });

  group('el viaje a disco', () {
    test('un punto va y vuelve entero', () {
      final punto = SavePoint.capture(
        sessionWith('s', bpm: 137, soundOnPad: 'acid'),
        name: 'Antes del puente',
      );

      final vuelta = SavePoint.fromJson(
        jsonDecode(jsonEncode(punto.toJson())) as Map<String, dynamic>,
      );

      expect(vuelta.id, punto.id);
      expect(vuelta.name, 'Antes del puente');
      expect(vuelta.sessionId, 's');
      expect(vuelta.session.bpm, 137);
      expect(vuelta.session.padAt(0, 0).soundId, 'acid');
    });

    test('la sesión de dentro conserva sus patrones', () {
      var s = sessionWith('s');
      final patterns = List.of(s.patterns);
      patterns[0] = patterns[0].withNote(3, '0:0').withRatchet(3, 4);
      s = s.copyWith(patterns: patterns);

      final vuelta = SavePoint.fromJson(
        jsonDecode(jsonEncode(SavePoint.capture(s, name: 'x').toJson()))
            as Map<String, dynamic>,
      );

      expect(vuelta.session.patterns[0].at(3), {'0:0'});
      expect(vuelta.session.patterns[0].ratchetAt(3), 4);
    });
  });
}
