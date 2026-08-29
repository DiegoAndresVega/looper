import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/midi.dart';
import 'package:looper/domain/midi_out.dart';

void main() {
  group('las notas que salen', () {
    test('el primer pad del banco A es la nota 36 del canal 1', () {
      final message = noteOnMessage(bank: 0, slot: 0, velocity: 1.0);

      expect(message[0], 0x90);
      expect(message[1], kMidiPadBaseNote);
      expect(message[2], 127);
    });

    test('cada banco tiene su canal, así que 64 pads caben sin chocar', () {
      // El banco decide el canal y el pad la nota: si los cuatro bancos
      // usaran el canal 1, el pad 3 del A y el del B serían la misma nota.
      expect(noteOnMessage(bank: 1, slot: 0, velocity: 1)[0], 0x91);
      expect(noteOnMessage(bank: 3, slot: 0, velocity: 1)[0], 0x93);
      expect(noteOnMessage(bank: 3, slot: 5, velocity: 1)[1],
          kMidiPadBaseNote + 5);
    });

    test('la fuerza va de cero a 127', () {
      expect(noteOnMessage(bank: 0, slot: 0, velocity: 0)[2], 0);
      expect(noteOnMessage(bank: 0, slot: 0, velocity: 0.5)[2], 64);
      expect(noteOnMessage(bank: 0, slot: 0, velocity: 9)[2], 127);
    });

    test('apagar la nota es la misma nota con velocidad cero', () {
      final off = noteOffMessage(bank: 2, slot: 4);

      expect(off[0], 0x82);
      expect(off[1], kMidiPadBaseNote + 4);
      expect(off[2], 0);
    });

    test('un banco o un pad imposibles no producen un mensaje roto', () {
      final message = noteOnMessage(bank: 99, slot: 99, velocity: 1);

      expect(message[0] & 0x0F, lessThan(kBankCount));
      expect(message[1], lessThanOrEqualTo(127));
    });
  });

  group('los mandos que salen', () {
    test('un control lleva su número y su valor', () {
      final message = controlMessage(channel: 0, controller: 21, value: 1.0);

      expect(message, [0xB0, 21, 127]);
    });

    test('el centro del mando es 64, no 63', () {
      expect(controlMessage(channel: 0, controller: 1, value: 0.5)[2], 64);
    });
  });

  group('el reloj', () {
    test('arrancar, parar y cada pulso son un solo byte', () {
      expect(startMessage, [0xFA]);
      expect(stopMessage, [0xFC]);
      expect(clockMessage, [0xF8]);
    });

    test('lo que sale se lee igual que lo que entra', () {
      // El mismo parser que usa la entrada tiene que entender la salida:
      // si no, dos Loopers no podrían sincronizarse entre ellos.
      final events = parseMidi(bytes([
        ...startMessage,
        ...clockMessage,
        ...noteOnMessage(bank: 0, slot: 2, velocity: 1),
        ...stopMessage,
      ]));

      expect(events.length, 4);
      expect(events[0], isA<MidiStart>());
      expect(events[1], isA<MidiClock>());
      expect(events[2], isA<MidiNoteOn>());
      expect((events[2] as MidiNoteOn).note, kMidiPadBaseNote + 2);
      expect(events[3], isA<MidiStop>());
    });

    test('veinticuatro pulsos por negra es lo que espera todo el mundo', () {
      expect(kMidiClockPulsesPerStep * kStepsPerBeat, 24);
    });
  });
}
