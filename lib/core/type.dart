import 'package:flutter/material.dart';

import 'palette.dart';

/// The brand's two faces, and the only place their axes are set.
///
/// Both files are variable fonts, so weight and width are coordinates, not
/// separate assets. Every style below sets `wght` explicitly: the shipped
/// default instance of Archivo is 600, which would render body copy far too
/// heavy if a style ever left the axis alone. Weight is set *only* through
/// `fontVariations` — never `fontWeight` — so the engine interpolates the axis
/// instead of faking bold on top of it.
///
/// - **Archivo** carries the voice. Wide and heavy for anything that names
///   something; normal width and light for anything that explains it.
/// - **Martian Mono** carries the data: step numbers, tempo, pad addresses and
///   the micro-captions under the transport. It is the face of the machine
///   talking back, so it is always uppercase and always spaced out.
class Brand {
  const Brand._();

  static const String faceDisplay = 'Archivo';
  static const String faceMono = 'MartianMono';

  /// Tracking in the artifact is expressed in ems; Flutter wants logical
  /// pixels, so it has to be derived from the size at every call.
  static const double _monoTracking = 0.16;
  static const double _titleTracking = -0.015;

  /// The widest, heaviest cut. For the app's own name and for the one line a
  /// screen leads with — the two places the brand signs its work.
  static TextStyle hero(
    double size, {
    Color color = Palette.ink,
    double height = 1.02,
  }) {
    return TextStyle(
      fontFamily: faceDisplay,
      fontVariations: const [FontVariation('wdth', 125), FontVariation('wght', 900)],
      fontSize: size,
      height: height,
      letterSpacing: size * _titleTracking,
      color: color,
    );
  }

  /// Section and sheet headings. Wide, but a step back from the logotype.
  static TextStyle title(
    double size, {
    Color color = Palette.ink,
    double height = 1.12,
  }) {
    return TextStyle(
      fontFamily: faceDisplay,
      fontVariations: const [FontVariation('wdth', 118), FontVariation('wght', 800)],
      fontSize: size,
      height: height,
      letterSpacing: size * _titleTracking,
      color: color,
    );
  }

  /// A name inside a list or a card: the thing the finger is aiming at.
  static TextStyle strong(
    double size, {
    Color color = Palette.ink,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: faceDisplay,
      fontVariations: const [FontVariation('wdth', 100), FontVariation('wght', 600)],
      fontSize: size,
      height: height,
      color: color,
    );
  }

  /// Running copy. Normal width, normal weight, generous line height.
  static TextStyle body(
    double size, {
    Color color = Palette.inkDim,
    double height = 1.42,
  }) {
    return TextStyle(
      fontFamily: faceDisplay,
      fontVariations: const [FontVariation('wdth', 100), FontVariation('wght', 400)],
      fontSize: size,
      height: height,
      color: color,
    );
  }

  /// The machine's caption: uppercase, spaced, monospaced. Call it with text
  /// already uppercased — the style spaces the letters, it does not change them.
  /// `width` narrows the face where a caption has to survive a tight row —
  /// Martian Mono advances 0,648 em at 87 and 0,600 em at 75.
  static TextStyle label(
    double size, {
    Color color = Palette.inkFaint,
    double weight = 600,
    double width = 87,
    double? tracking,
  }) {
    return TextStyle(
      fontFamily: faceMono,
      fontVariations: [FontVariation('wdth', width), FontVariation('wght', weight)],
      fontSize: size,
      height: 1.1,
      letterSpacing: size * (tracking ?? _monoTracking),
      color: color,
    );
  }

  /// Numbers that change while you watch them — tempo, step, bars, seconds.
  /// Monospaced, so the layout never twitches as the digits roll.
  static TextStyle readout(
    double size, {
    Color color = Palette.ink,
    double weight = 500,
  }) {
    return TextStyle(
      fontFamily: faceMono,
      fontVariations: [const FontVariation('wdth', 100), FontVariation('wght', weight)],
      fontSize: size,
      height: 1.05,
      letterSpacing: size * 0.02,
      color: color,
    );
  }
}
