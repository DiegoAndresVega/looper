import 'package:flutter/material.dart';

/// The instrument is dark-first: a stage tool, not an office one.
/// Colour carries meaning here — each sound family owns a hue, and the hue
/// travels with the sound, not with the pad position.
class Palette {
  const Palette._();

  static const Color ground = Color(0xFF0B0F0E);
  static const Color panel = Color(0xFF151B19);
  static const Color panelHigh = Color(0xFF1C2321);
  static const Color line = Color(0xFF262E2C);

  static const Color ink = Color(0xFFEDF2EE);
  static const Color inkDim = Color(0xFF8F9B96);
  static const Color inkFaint = Color(0xFF5C6864);

  static const Color accent = Color(0xFFF2A73B);
  static const Color rec = Color(0xFFFF4B3E);

  static const Color percussion = Color(0xFFE0574A);
  static const Color voice = Color(0xFFF2A73B);
  static const Color tone = Color(0xFF4FC3D9);
  static const Color texture = Color(0xFFA98BE0);
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
