import 'package:flutter_test/flutter_test.dart';
import 'package:looper/domain/midi.dart';
import 'package:looper/domain/midi_target.dart';
import 'package:looper/state/midi_learn.dart';

/// El gesto entero: mantienes pulsado un mando de la pantalla, mueves uno del
/// controlador, y quedan casados. Sin menús y sin listas de CC.
void main() {
  const filtro = MidiTarget(MidiParam.masterCutoff);
  const volumen = MidiTarget(MidiParam.masterVolume);

  MidiControlChange cc(int controller, int value) =>
      MidiControlChange(0, controller, value);

  group('el gesto', () {
    test('sin nada armado, un mando desconocido no mueve nada', () {
      final learn = MidiLearn();

      expect(learn.route(cc(21, 64)), isNull);
    });

    test('lo que se mueve estando armado se queda casado', () {
      final learn = MidiLearn();

      learn.arm(filtro);
      learn.route(cc(21, 64));

      expect(learn.armed, isNull, reason: 'el modo dura un solo movimiento');
      expect(learn.controllerFor(filtro), 21);
      expect(learn.route(cc(21, 100)), filtro);
    });

    test('el movimiento que casa también mueve el parámetro', () {
      // Si no, el mando se queda donde estaba y el valor donde estaba, y hay
      // que darle un segundo meneo para que se junten.
      final learn = MidiLearn();

      learn.arm(filtro);

      expect(learn.route(cc(21, 64)), filtro);
    });

    test('armar otro mando suelta el primero', () {
      final learn = MidiLearn();

      learn.arm(filtro);
      learn.arm(volumen);
      learn.route(cc(21, 64));

      expect(learn.controllerFor(filtro), isNull);
      expect(learn.controllerFor(volumen), 21);
    });

    test('cancelar deja el mando sin aprender', () {
      final learn = MidiLearn();

      learn.arm(filtro);
      learn.cancel();

      expect(learn.armed, isNull);
      expect(learn.route(cc(21, 64)), isNull);
    });

    test('olvidar devuelve el mando físico a no hacer nada', () {
      final learn = MidiLearn();
      learn.arm(filtro);
      learn.route(cc(21, 64));

      learn.forget(filtro);

      expect(learn.controllerFor(filtro), isNull);
      expect(learn.route(cc(21, 90)), isNull);
    });

    test('un canal distinto mueve lo mismo', () {
      // El canal se ignora a propósito: un mando es ese mando, grite por donde
      // grite. Los pads ya funcionan igual.
      final learn = MidiLearn();
      learn.arm(filtro);
      learn.route(cc(21, 64));

      expect(learn.route(const MidiControlChange(9, 21, 30)), filtro);
    });
  });

  group('lo que ve la pantalla', () {
    test('avisa al armar, al casar y al olvidar', () {
      final learn = MidiLearn();
      var avisos = 0;
      learn.addListener(() => avisos++);

      learn.arm(filtro);
      learn.route(cc(21, 64));
      learn.forget(filtro);

      expect(avisos, 3);
    });

    test('no avisa por un mando que no mueve nada', () {
      final learn = MidiLearn();
      var avisos = 0;
      learn.addListener(() => avisos++);

      learn.route(cc(21, 64));

      expect(avisos, 0);
    });

    test('sabe qué mando está esperando', () {
      final learn = MidiLearn();

      learn.arm(filtro);

      expect(learn.isArmed(filtro), isTrue);
      expect(learn.isArmed(volumen), isFalse);
    });
  });

  group('de valor MIDI a posición de mando', () {
    test('los extremos son el mínimo y el máximo', () {
      expect(positionFromMidi(0), 0);
      expect(positionFromMidi(127), 1);
    });

    test('el centro cae en el centro', () {
      expect(positionFromMidi(64), closeTo(0.5, 0.01));
    });
  });
}
