/// What arrives over MIDI, and what it means here.
///
/// Nothing in this file talks to a cable: bytes in, decisions out. That is the
/// part worth testing without a controller plugged in, and it is where the
/// mistakes live — the protocol has two classic traps. A Note On with velocity
/// zero is really a Note Off, and one packet can carry several messages of
/// which only the first wears a header.
library;

import 'dart:typed_data';

import '../core/constants.dart';

/// Something that came down the wire.
sealed class MidiEvent {
  const MidiEvent();
}

class MidiNoteOn extends MidiEvent {
  const MidiNoteOn(this.channel, this.note, this.velocity);
  final int channel;
  final int note;
  final int velocity;
}

class MidiNoteOff extends MidiEvent {
  const MidiNoteOff(this.channel, this.note);
  final int channel;
  final int note;
}

class MidiControlChange extends MidiEvent {
  const MidiControlChange(this.channel, this.controller, this.value);
  final int channel;
  final int controller;
  final int value;
}

class MidiClock extends MidiEvent {
  const MidiClock();
}

class MidiStart extends MidiEvent {
  const MidiStart();
}

class MidiStop extends MidiEvent {
  const MidiStop();
}

const int _noteOff = 0x80;
const int _noteOn = 0x90;
const int _controlChange = 0xB0;

/// Reads a packet into the events it carries.
///
/// Handles running status — a message that repeats the previous type omits its
/// header — because BLE controllers lean on it, and without it a fast roll
/// arrives as one note and a pile of garbage. Real-time bytes (clock,
/// start, stop) are passed through without disturbing that state, which is
/// exactly what the spec requires: the clock interleaves with everything.
List<MidiEvent> parseMidi(Uint8List packet) {
  final events = <MidiEvent>[];
  var status = 0;
  var i = 0;

  while (i < packet.length) {
    final byte = packet[i];

    // Real-time messages can appear anywhere, even mid-message, and never
    // become the running status.
    if (byte >= 0xF8) {
      switch (byte) {
        case 0xF8:
          events.add(const MidiClock());
        case 0xFA:
          events.add(const MidiStart());
        case 0xFC:
          events.add(const MidiStop());
      }
      i++;
      continue;
    }

    if (byte >= 0x80) {
      // System common (0xF0–0xF7) cancels running status and is not handled.
      if (byte >= 0xF0) {
        status = 0;
        i++;
        continue;
      }
      status = byte;
      i++;
    }

    if (status == 0) {
      i++; // A data byte with nothing to belong to.
      continue;
    }

    final type = status & 0xF0;
    final channel = status & 0x0F;
    if (i + 1 >= packet.length) break; // Truncated: better nothing than noise.

    final first = packet[i];
    final second = packet[i + 1];
    i += 2;

    switch (type) {
      case _noteOn:
        // Velocity zero is how most of the industry releases a note.
        events.add(second == 0
            ? MidiNoteOff(channel, first)
            : MidiNoteOn(channel, first, second));
      case _noteOff:
        events.add(MidiNoteOff(channel, first));
      case _controlChange:
        events.add(MidiControlChange(channel, first, second));
    }
  }

  return events;
}

/// Which pad a note plays, or null when it falls outside the grid.
int? padForNote(int note) {
  final pad = note - kMidiPadBaseNote;
  return pad >= 0 && pad < kPadsPerBank ? pad : null;
}

/// MIDI velocity as the app's own strength.
///
/// Scaled from the floor rather than from zero: plenty of cheap pads send a
/// fixed 100, and a controller with no sensitivity must not be stuck playing
/// everything at four fifths for ever.
double velocityFromMidi(int velocity) {
  final v = velocity.clamp(1, 127);
  return (kVelocityMin + (kVelocityMax - kVelocityMin) * (v / 127))
      .clamp(kVelocityMin, kVelocityMax);
}
