import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/state/undo_stack.dart';

/// Deshacer es la petición número uno de quien usa un looper, y hasta ahora
/// esta app no tenía ninguno: VACIAR PAD y BORRAR PATRÓN no se podían retirar,
/// y como la sesión se guarda sola 800 ms después, el error quedaba escrito en
/// disco antes de que diese tiempo a arrepentirse.
///
/// La pila guarda **el estado anterior**, no la acción. `Session` es inmutable,
/// así que una instantánea cuesta un puñado de referencias y no copia nada.
void main() {
  group('la pila', () {
    test('nace vacía y sin nada que deshacer', () {
      final pila = UndoStack<String>();

      expect(pila.canUndo, isFalse);
      expect(pila.depth, 0);
      expect(pila.topLabel, isNull);
    });

    test('deshacer sobre una pila vacía no revienta', () {
      expect(UndoStack<String>().undo(), isNull);
    });

    test('devuelve el último estado guardado', () {
      final pila = UndoStack<String>()..push('antes', 'vaciar pad');

      final vuelta = pila.undo();

      expect(vuelta?.state, 'antes');
      expect(vuelta?.label, 'vaciar pad');
      expect(pila.canUndo, isFalse);
    });

    test('deshace en orden inverso', () {
      final pila = UndoStack<String>()
        ..push('uno', 'a')
        ..push('dos', 'b')
        ..push('tres', 'c');

      expect(pila.undo()?.state, 'tres');
      expect(pila.undo()?.state, 'dos');
      expect(pila.undo()?.state, 'uno');
      expect(pila.canUndo, isFalse);
    });

    test('anuncia qué se va a deshacer', () {
      final pila = UndoStack<String>()
        ..push('x', 'vaciar pad')
        ..push('y', 'borrar patrón');

      expect(pila.topLabel, 'borrar patrón');
    });

    test('al llegar al tope tira la más vieja, no la más nueva', () {
      final pila = UndoStack<int>(limit: 3);

      for (var i = 1; i <= 5; i++) {
        pila.push(i, 'paso $i');
      }

      expect(pila.depth, 3);
      expect(pila.undo()?.state, 5);
      expect(pila.undo()?.state, 4);
      expect(pila.undo()?.state, 3);
      expect(pila.canUndo, isFalse, reason: '1 y 2 se cayeron por el tope');
    });

    test('vaciarla deja de ofrecer deshacer', () {
      final pila = UndoStack<String>()..push('x', 'algo');

      pila.clear();

      expect(pila.canUndo, isFalse);
      expect(pila.depth, 0);
    });

    test('el tope de fábrica da margen de sobra para una sesión', () {
      expect(kUndoLimit, greaterThanOrEqualTo(10));
    });
  });
}
