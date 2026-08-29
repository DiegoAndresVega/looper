import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/scene.dart';
import 'package:looper/domain/session.dart';

void main() {
  group('capturar lo que suena', () {
    test('una escena guarda los bucles y el patrón de ese momento', () {
      final scene = Scene.capture(loops: {'0:1', '2:5'}, pattern: 3);

      expect(scene.loops, {'0:1', '2:5'});
      expect(scene.pattern, 3);
      expect(scene.isEmpty, isFalse);
    });

    test('capturar el silencio da una escena vacía', () {
      final scene = Scene.capture(loops: const {}, pattern: 0);

      expect(scene.isEmpty, isTrue);
    });

    test('una escena no se puede editar por detrás', () {
      final loops = {'0:1'};
      final scene = Scene.capture(loops: loops, pattern: 0);

      loops.add('0:2');

      expect(scene.loops, {'0:1'});
    });
  });

  group('el cambio de escena', () {
    test('arranca lo que falta y para lo que sobra', () {
      final scene = Scene.capture(loops: {'0:1', '0:2'}, pattern: 0);

      final change = sceneTransition(playing: {'0:2', '0:9'}, scene: scene);

      expect(change.start, {'0:1'});
      expect(change.stop, {'0:9'});
    });

    test('relanzar la escena que ya suena no toca nada', () {
      final scene = Scene.capture(loops: {'0:1', '0:2'}, pattern: 0);

      final change = sceneTransition(playing: {'0:1', '0:2'}, scene: scene);

      expect(change.start, isEmpty);
      expect(change.stop, isEmpty);
      expect(change.isNothing, isTrue);
    });

    test('desde el silencio solo arranca', () {
      final scene = Scene.capture(loops: {'1:0'}, pattern: 0);

      final change = sceneTransition(playing: const {}, scene: scene);

      expect(change.start, {'1:0'});
      expect(change.stop, isEmpty);
    });
  });

  group('las ocho escenas de la sesión', () {
    test('una sesión nueva las trae vacías', () {
      final session = Session.blank(id: 's', name: 'S');

      expect(session.scenes.length, kScenesPerSession);
      expect(session.scenes.every((s) => s.isEmpty), isTrue);
    });

    test('guardar una escena no toca las demás ni la sesión de partida', () {
      final session = Session.blank(id: 's', name: 'S');

      final next = session.withScene(2, Scene.capture(loops: {'0:0'}, pattern: 1));

      expect(next.scenes[2].loops, {'0:0'});
      expect(next.scenes[1].isEmpty, isTrue);
      expect(session.scenes[2].isEmpty, isTrue);
    });

    test('una escena fuera de rango no rompe la sesión', () {
      final session = Session.blank(id: 's', name: 'S');

      expect(
        session.withScene(99, Scene.capture(loops: {'0:0'}, pattern: 0)).scenes,
        session.scenes,
      );
    });
  });

  group('el viaje a disco', () {
    test('las escenas van y vuelven pasando por el texto', () {
      final session = Session.blank(id: 's', name: 'S')
          .withScene(0, Scene.capture(loops: {'0:1', '3:15'}, pattern: 4));

      final back = Session.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
      );

      expect(back.scenes[0].loops, {'0:1', '3:15'});
      expect(back.scenes[0].pattern, 4);
      expect(back.scenes.length, kScenesPerSession);
    });

    test('una sesión de antes de las escenas abre con las ocho vacías', () {
      final session = Session.blank(id: 's', name: 'S');
      final json = Map<String, dynamic>.of(session.toJson())..remove('scenes');

      final back = Session.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );

      expect(back.scenes.length, kScenesPerSession);
      expect(back.scenes.every((s) => s.isEmpty), isTrue);
    });
  });
}
