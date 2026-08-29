import 'dart:typed_data';

import '../core/constants.dart';

/// The bytes Looper sends out of the cable.
///
/// The mirror image of `midi.dart`, and deliberately in the same shape: a
/// handful of pure functions returning byte lists, so the whole of what this
/// instrument says can be checked without a device — and checked against the
/// very parser that reads what comes in.
///
/// The layout is the one the input already assumes: pads start at note 36 and
/// each bank speaks on its own channel. Sixty-four pads do not fit in one
/// channel's usable range without colliding with somebody's drum map, and the
/// bank is the obvious thing to spend a channel on.
Uint8List noteOnMessage({
  required int bank,
  required int slot,
  required double velocity,
}) =>
    bytes([
      0x90 | _channel(bank),
      _note(slot),
      _sevenBit(velocity),
    ]);

/// A note off, written as note-on-with-zero. Both are legal; this one is what
/// running status makes cheap, and cheap matters on a Bluetooth link.
Uint8List noteOffMessage({required int bank, required int slot}) =>
    bytes([0x80 | _channel(bank), _note(slot), 0]);

Uint8List controlMessage({
  required int channel,
  required int controller,
  required double value,
}) =>
    bytes([
      0xB0 | (channel & 0x0F),
      controller & 0x7F,
      _sevenBit(value),
    ]);

/// The three real-time bytes. They carry no data and no channel: they are
/// addressed to everything on the wire at once.
final Uint8List clockMessage = bytes([0xF8]);
final Uint8List startMessage = bytes([0xFA]);
final Uint8List stopMessage = bytes([0xFC]);

/// How many clock pulses go out per 16th note. The standard is 24 per quarter
/// note and nothing in the world reads anything else, so a 16th is six.
const int kMidiClockPulsesPerStep = 6;

Uint8List bytes(List<int> data) => Uint8List.fromList(data);

int _channel(int bank) => bank.clamp(0, kBankCount - 1);

int _note(int slot) =>
    (kMidiPadBaseNote + slot.clamp(0, kPadsPerBank - 1)) & 0x7F;

/// 0..1 into the only range MIDI has. Rounded rather than truncated so the
/// middle of a knob lands on 64, which is what every desk shows as centre.
int _sevenBit(double value) => (value.clamp(0.0, 1.0) * 127).round();
