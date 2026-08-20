import 'package:flutter/material.dart';

/// The instrument is dark-first: a stage tool, not an office one.
///
/// The ground is aubergine, not charcoal — the brand violet dropped to 11 %
/// luminance while keeping 54 % saturation. It reads as the wall of a room
/// under UV, which is the point: the app lives inside the machine, not on a
/// sheet of paper. Everything else is light crossing that room.
///
/// Colour carries meaning here — each sound family owns a hue, and the hue
/// travels with the sound, not with the pad position. The four family hues sit
/// on one arc, so no accent ever looks imported from another palette.
class Palette {
  const Palette._();

  /// The five steps of the ground, darkest first. Depth is built by climbing
  /// this ladder, never by dropping a translucent black on top.
  static const Color well = Color(0xFF0F0820);
  static const Color ground = Color(0xFF170D2B);
  static const Color panel = Color(0xFF211441);
  static const Color panelHigh = Color(0xFF2C1D57);
  static const Color line = Color(0xFF33205C);

  /// A hairline that is meant to be seen — a focused field, an armed control.
  static const Color lineLive = Color(0xFF48307E);

  /// Ink is violet-tinted bone, never neutral grey: a grey here would read as
  /// a different system sitting on top of the aubergine.
  static const Color ink = Color(0xFFEDE9F6);
  static const Color inkDim = Color(0xFFA79BC0);
  static const Color inkFaint = Color(0xFF8A7DAE);

  /// Phosphor. The brand's first accent and the colour of anything armed.
  static const Color accent = Color(0xFFB4EC5C);

  /// Laser. Writing the pattern, and nothing else — the old red belonged to
  /// three different buttons, which is exactly why it stopped meaning anything.
  static const Color rec = Color(0xFFFF4FA0);

  /// The four sound families, one hue arc: phosphor → mint → sky → UV.
  static const Color percussion = Color(0xFFB4EC5C);
  static const Color voice = Color(0xFF4FE3B4);
  static const Color tone = Color(0xFF5BB4F5);
  static const Color texture = Color(0xFF9B78F0);

  /// What to print on top of a filled accent. Every accent is a light colour,
  /// so the ground is the only readable ink: white on laser is 3,05 : 1, the
  /// ground is 6,09 : 1.
  static const Color onAccent = ground;
}

/// Sound families. The four colours above map one-to-one onto these.
enum SoundFamily {
  percussion('Percusión', Palette.percussion),
  voice('Voz', Palette.voice),
  tone('Tono', Palette.tone),
  texture('Textura', Palette.texture);

  const SoundFamily(this.label, this.color);

  final String label;
  final Color color;
}
