import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/domain/set_list.dart';

void main() {
  group('el orden de la actuación', () {
    test('empieza vacía', () {
      const list = SetList.empty();

      expect(list.isEmpty, isTrue);
      expect(list.sessionIds, isEmpty);
    });

    test('añadir pone al final', () {
      final list = const SetList.empty().appended('a').appended('b');

      expect(list.sessionIds, ['a', 'b']);
    });

    test('una sesión no puede estar dos veces en la lista', () {
      final list = const SetList.empty().appended('a').appended('a');

      expect(list.sessionIds, ['a']);
    });

    test('quitar deja el resto en su orden', () {
      final list =
          const SetList.empty().appended('a').appended('b').appended('c');

      expect(list.removed('b').sessionIds, ['a', 'c']);
    });

    test('mover intercambia con el vecino', () {
      final list = const SetList.empty().appended('a').appended('b');

      expect(list.movedAt(0, 1).sessionIds, ['b', 'a']);
      expect(list.movedAt(0, -1).sessionIds, ['a', 'b']);
    });

    test('editar no muta la lista de partida', () {
      final list = const SetList.empty().appended('a');

      list.appended('b');

      expect(list.sessionIds, ['a']);
    });
  });

  group('qué toca ahora y qué toca después', () {
    test('el número de orden empieza en uno, como en el papel', () {
      final list = const SetList.empty().appended('a').appended('b');

      expect(list.positionOf('a'), 1);
      expect(list.positionOf('b'), 2);
      expect(list.positionOf('z'), isNull);
    });

    test('el siguiente es el de al lado', () {
      final list =
          const SetList.empty().appended('a').appended('b').appended('c');

      expect(list.nextAfter('a'), 'b');
    });

    test('el último no tiene siguiente: el bis se decide en el momento', () {
      final list = const SetList.empty().appended('a').appended('b');

      expect(list.nextAfter('b'), isNull);
    });

    test('una sesión fuera de la lista no tiene siguiente', () {
      final list = const SetList.empty().appended('a');

      expect(list.nextAfter('z'), isNull);
    });
  });

  group('sesiones que ya no están', () {
    test('borrar una sesión la saca de la actuación', () {
      final list =
          const SetList.empty().appended('a').appended('b').appended('c');

      expect(list.prunedTo({'a', 'c'}).sessionIds, ['a', 'c']);
    });

    test('si no falta ninguna, devuelve la misma lista', () {
      final list = const SetList.empty().appended('a');

      expect(list.prunedTo({'a', 'b'}).sessionIds, ['a']);
    });
  });

  group('el viaje a disco', () {
    test('la lista va y vuelve pasando por el texto', () {
      final list = const SetList.empty().appended('a').appended('b');

      final back = SetList.fromJson(
        jsonDecode(jsonEncode(list.toJson())) as List<dynamic>,
      );

      expect(back.sessionIds, ['a', 'b']);
    });

    test('un fichero corrupto vuelve vacío en vez de romper el arranque', () {
      expect(SetList.fromJson(null).isEmpty, isTrue);
      expect(SetList.fromJson('nada').isEmpty, isTrue);
      expect(SetList.fromJson([1, 2]).isEmpty, isTrue);
    });
  });
}
