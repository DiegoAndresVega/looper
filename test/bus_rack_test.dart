import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/bus_rack.dart';
import 'package:looper/audio/fx_curves.dart';
import 'package:looper/core/palette.dart';

/// Las cuatro familias son buses de verdad: cada una con su filtro, su drive
/// y su envío a la única reverb que hay. Aquí se prueba la mitad que no
/// necesita motor —las posiciones de los mandos— igual que [fx_curves] es la
/// mitad del maestro que se puede comprobar sin dispositivo.
void main() {
  group('un bus recién abierto', () {
    test('nace transparente', () {
      final rack = BusRack();

      for (final family in SoundFamily.values) {
        final bus = rack.settingsFor(family);
        expect(bus.isFlat, isTrue, reason: '${family.label} no nació limpia');
        expect(bus.cutoff, 1, reason: 'el filtro nace abierto del todo');
        expect(bus.send, 0);
      }
    });

    test('con el filtro abierto no está en el camino', () {
      // El bypass de verdad es wet a cero, no quitar el filtro: volver a
      // meterlo en marcha suelta sus ajustes de fábrica en un bus vivo.
      expect(BusSettings.flat.isFilterResting, isTrue);
      expect(BusSettings.flat.isDriveResting, isTrue);
      expect(BusSettings.flat.isSendResting, isTrue);
    });
  });

  group('cada familia va por su cuenta', () {
    test('mover una no mueve a las demás', () {
      final rack = BusRack()..setCutoff(SoundFamily.percussion, 0.3);

      expect(rack.settingsFor(SoundFamily.percussion).cutoff, 0.3);
      for (final other in [
        SoundFamily.voice,
        SoundFamily.tone,
        SoundFamily.texture,
      ]) {
        expect(rack.settingsFor(other), BusSettings.flat,
            reason: '${other.label} se movió sola');
      }
    });

    test('el rack deja de estar limpio en cuanto una familia se toca', () {
      final rack = BusRack();
      expect(rack.isFlat, isTrue);

      rack.setSend(SoundFamily.texture, 0.4);

      expect(rack.isFlat, isFalse);
    });

    test('reset devuelve las cuatro al principio', () {
      final rack = BusRack()
        ..setCutoff(SoundFamily.voice, 0.2)
        ..setDrive(SoundFamily.tone, 0.9)
        ..reset();

      expect(rack.isFlat, isTrue);
    });
  });

  group('los ajustes no se modifican, se sustituyen', () {
    test('quien tenía el ajuste viejo lo sigue teniendo', () {
      // Es la regla de la casa: el motor y la pantalla pueden sostener la
      // misma instancia sin que ninguno se la cambie al otro por detrás.
      final rack = BusRack();
      final before = rack.settingsFor(SoundFamily.voice);

      rack.setDrive(SoundFamily.voice, 0.7);

      expect(before.drive, 0);
      expect(rack.settingsFor(SoundFamily.voice).drive, 0.7);
    });

    test('dos ajustes iguales son el mismo ajuste', () {
      expect(const BusSettings(cutoff: 0.5, send: 0.25),
          const BusSettings(cutoff: 0.5, send: 0.25));
      expect(const BusSettings(cutoff: 0.5), isNot(const BusSettings()));
    });
  });

  group('un mando pasado de tope', () {
    // El complemento **descarta** un parámetro fuera de rango: avisa y se
    // queda con lo que tenía. Recortar aquí es lo que evita que un mando deje
    // de hacer nada sin decirlo.
    test('se recoge en vez de colarse', () {
      final rack = BusRack()
        ..setCutoff(SoundFamily.tone, 4)
        ..setResonance(SoundFamily.tone, -2)
        ..setDrive(SoundFamily.tone, 9)
        ..setSend(SoundFamily.tone, -1);

      final bus = rack.settingsFor(SoundFamily.tone);
      expect(bus.cutoff, 1);
      expect(bus.resonance, 0);
      expect(bus.drive, 1);
      expect(bus.send, 0);
    });
  });

  group('el envío a la reverb', () {
    test('nunca pide más de lo que hay', () {
      for (var i = 0; i <= 20; i++) {
        final gain = sendGain(i / 20);
        expect(gain, inInclusiveRange(0, 1), reason: 'el mando en ${i / 20}');
      }
    });

    test('no baja al subir', () {
      var previous = -1.0;
      for (var i = 0; i <= 20; i++) {
        final gain = sendGain(i / 20);
        expect(gain, greaterThanOrEqualTo(previous));
        previous = gain;
      }
    });

    test('la primera mitad del recorrido es un halo, no la sala', () {
      // Cuadrática: a medio camino se manda una cuarta parte. Una reverb que
      // llega entera a mitad de mando no se puede dosificar tocando.
      expect(sendGain(0.5), closeTo(0.25, 1e-9));
      expect(sendGain(1), 1);
      expect(sendGain(0), 0);
    });

    test('un envío en reposo manda cero', () {
      expect(const BusSettings(send: 0).sendVolume, 0);
      expect(const BusSettings(send: kFxEpsilon / 2).isSendResting, isTrue);
    });
  });

  group('la reverb compartida', () {
    test('su carácter fijo cabe en lo que freeverb acepta', () {
      for (final value in [
        kReverbWet,
        kReverbRoomSize,
        kReverbDamp,
        kReverbWidth,
        kReverbFreeze,
      ]) {
        expect(value, inInclusiveRange(kReverbMin, kReverbMax));
      }
    });

    test('devuelve solo reverb, que es lo que la hace un envío', () {
      // Si el wet no fuera uno, el bus devolvería también lo seco y el sonido
      // se oiría dos veces: una por su familia y otra por aquí.
      expect(kReverbWet, 1);
    });
  });
}
