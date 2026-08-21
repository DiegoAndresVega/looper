import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/midi.dart';

/// Lo que llega por MIDI y qué significa aquí.
///
/// Nada de esto habla con un cable: son bytes entrando y decisiones saliendo,
/// que es la única parte que se puede probar sin tener el controlador
/// enchufado — y es donde están los errores de verdad, porque el protocolo
/// tiene dos trampas clásicas: un Note On con velocidad cero es en realidad un
/// Note Off, y un paquete puede traer varios mensajes de los que solo el
/// primero lleva cabecera.
void main() {
  Uint8List bytes(List<int> v) => Uint8List.fromList(v);

  group('mensajes sueltos', () {
    test('un Note On es una nota que empieza', () {
      final eventos = parseMidi(bytes([0x90, 60, 100]));

      expect(eventos, hasLength(1));
      final e = eventos.first as MidiNoteOn;
      expect(e.note, 60);
      expect(e.velocity, 100);
      expect(e.channel, 0);
    });

    test('el canal sale del byte de estado', () {
      final e = parseMidi(bytes([0x95, 60, 100])).first as MidiNoteOn;

      expect(e.channel, 5);
    });

    test('un Note On con velocidad cero es un Note Off', () {
      // La trampa más vieja del protocolo: media industria apaga notas así.
      final eventos = parseMidi(bytes([0x90, 60, 0]));

      expect(eventos.first, isA<MidiNoteOff>());
      expect((eventos.first as MidiNoteOff).note, 60);
    });

    test('un Note Off es un Note Off', () {
      final eventos = parseMidi(bytes([0x80, 45, 64]));

      expect((eventos.first as MidiNoteOff).note, 45);
    });

    test('un control se lee entero', () {
      final e = parseMidi(bytes([0xB0, 74, 127])).first as MidiControlChange;

      expect(e.controller, 74);
      expect(e.value, 127);
    });

    test('lo que no se entiende se ignora en vez de reventar', () {
      expect(parseMidi(bytes([0xF0, 1, 2, 3])), isEmpty);
      expect(parseMidi(bytes([])), isEmpty);
      expect(parseMidi(bytes([0x90])), isEmpty, reason: 'mensaje truncado');
      expect(parseMidi(bytes([0x90, 60])), isEmpty, reason: 'falta velocidad');
    });
  });

  group('varios mensajes en un paquete', () {
    test('los separa todos', () {
      final eventos = parseMidi(bytes([0x90, 60, 100, 0x80, 60, 0, 0xB0, 1, 5]));

      expect(eventos, hasLength(3));
      expect(eventos[0], isA<MidiNoteOn>());
      expect(eventos[1], isA<MidiNoteOff>());
      expect(eventos[2], isA<MidiControlChange>());
    });

    test('entiende el estado heredado', () {
      // Running status: el segundo mensaje se ahorra la cabecera porque es del
      // mismo tipo. Sin esto, un controlador tocando rápido pierde notas.
      final eventos = parseMidi(bytes([0x90, 60, 100, 64, 90, 67, 80]));

      expect(eventos, hasLength(3));
      expect((eventos[0] as MidiNoteOn).note, 60);
      expect((eventos[1] as MidiNoteOn).note, 64);
      expect((eventos[2] as MidiNoteOn).note, 67);
    });

    test('un mensaje de sistema no rompe el estado heredado', () {
      // El reloj se cuela entre notas todo el rato y no cambia el estado.
      final eventos = parseMidi(bytes([0x90, 60, 100, 0xF8, 64, 90]));

      expect(eventos.whereType<MidiNoteOn>(), hasLength(2));
      expect(eventos.whereType<MidiClock>(), hasLength(1));
    });

    test('reconoce arranque y parada del transporte', () {
      final eventos = parseMidi(bytes([0xFA, 0xFC]));

      expect(eventos[0], isA<MidiStart>());
      expect(eventos[1], isA<MidiStop>());
    });
  });

  group('qué pad toca cada nota', () {
    test('la nota base es el primer pad', () {
      expect(padForNote(kMidiPadBaseNote), 0);
    });

    test('sube pad a pad, semitono a semitono', () {
      expect(padForNote(kMidiPadBaseNote + 1), 1);
      expect(padForNote(kMidiPadBaseNote + 15), kPadsPerBank - 1);
    });

    test('fuera de la octava y media de pads, nada', () {
      expect(padForNote(kMidiPadBaseNote - 1), isNull);
      expect(padForNote(kMidiPadBaseNote + kPadsPerBank), isNull);
    });

    test('la nota base es el do grave que usan los controladores de pads', () {
      // 36 es C1 en la convención de Akai, Novation y el M-Vave: enchufar y
      // tocar, sin configurar nada.
      expect(kMidiPadBaseNote, 36);
    });
  });

  group('de velocidad MIDI a fuerza', () {
    test('el tope pega a tope', () {
      expect(velocityFromMidi(127), closeTo(kVelocityMax, 0.001));
    });

    test('lo más flojo se oye', () {
      expect(velocityFromMidi(1), greaterThanOrEqualTo(kVelocityMin));
    });

    test('un controlador sin sensibilidad pega a tope', () {
      // Muchos pads baratos mandan siempre 127; los que mandan 100 fijo no
      // pueden quedarse a media fuerza para siempre.
      expect(velocityFromMidi(100), greaterThan(0.7));
    });

    test('nunca se sale de rango', () {
      for (var v = 0; v <= 127; v++) {
        final f = velocityFromMidi(v);
        expect(f, greaterThanOrEqualTo(kVelocityMin));
        expect(f, lessThanOrEqualTo(kVelocityMax));
      }
    });
  });
}
