/// What a physical control can be married to.
///
/// A target is a *parameter*, never a position on the strip. Learning a knob
/// that happens to be showing the percussion bus marries the control to the
/// percussion bus, not to «the first knob of whatever the strip is showing» —
/// otherwise selecting another pad would silently rewire the hardware under
/// the player's hands mid-take.
library;

import '../core/palette.dart';

/// Where a parameter lives, which is also what it follows.
enum MidiScope {
  /// The master output. Always there, whatever is on screen.
  master('Maestro'),

  /// One family's bus. Fixed at the moment of learning: the control keeps
  /// moving that family for ever, not the family of whatever is selected.
  bus('Bus'),

  /// The pad the surface is pointing at. It follows the selection on purpose —
  /// sixty-four pads times five parameters is not a thing anyone maps by hand.
  pad('Pad'),

  /// The grid as a keyboard.
  scale('Escala');

  const MidiScope(this.label);

  final String label;
}

/// Every parameter on the control surface a control can be married to.
///
/// The bus tab's first knob — the one that points the row at the master or at
/// the family — is deliberately absent: it changes what you are looking at,
/// not what you are hearing, and a controller that changes the view is a
/// controller you have to look at.
enum MidiParam {
  masterVolume('Vol', MidiScope.master),
  masterCutoff('Filtro', MidiScope.master),
  masterResonance('Reso', MidiScope.master),
  masterEcho('Eco', MidiScope.master),
  masterDrive('Drive', MidiScope.master),
  busCutoff('Filtro', MidiScope.bus),
  busResonance('Reso', MidiScope.bus),
  busSend('Envío', MidiScope.bus),
  busDrive('Drive', MidiScope.bus),
  padVolume('Vol', MidiScope.pad),
  padPitch('Tono', MidiScope.pad),
  padPan('Pan', MidiScope.pad),
  padMute('Mute', MidiScope.pad),
  padSolo('Solo', MidiScope.pad),
  padLoop('Loop', MidiScope.pad),
  padSync('Sync', MidiScope.pad),
  padLoopSteps('Tiempos', MidiScope.pad),
  scaleOn('Teclado', MidiScope.scale),
  scaleRoot('Tónica', MidiScope.scale),
  scaleKind('Escala', MidiScope.scale),
  scaleOctave('Octava', MidiScope.scale);

  const MidiParam(this.label, this.scope);

  final String label;
  final MidiScope scope;

  bool get needsFamily => scope == MidiScope.bus;
}

/// One parameter, pinned to a family when it takes one.
class MidiTarget {
  const MidiTarget(this.param, {this.family});

  /// A bus parameter of [family]'s bus.
  MidiTarget.bus(MidiParam param, SoundFamily family)
      : this(param, family: family);

  final MidiParam param;

  /// Only ever set for [MidiScope.bus] parameters.
  final SoundFamily? family;

  /// How this target is written down on disk. Names rather than indexes: a
  /// reordered enum must not turn every saved mapping into a different one.
  String get id => family == null ? param.name : '${param.name}:${family!.name}';

  /// What the mapping list calls it.
  String get label {
    final where = family?.label ?? param.scope.label;
    return '${param.label} · $where';
  }

  /// Reads an id back, or null when it names something this version does not
  /// have. A mapping file older than the code is normal; taking the app down
  /// for it is not.
  static MidiTarget? parse(String id) {
    final parts = id.split(':');
    final param = _byName(MidiParam.values, parts[0]);
    if (param == null) return null;

    if (!param.needsFamily) return parts.length == 1 ? MidiTarget(param) : null;
    if (parts.length != 2) return null;

    final family = _byName(SoundFamily.values, parts[1]);
    return family == null ? null : MidiTarget(param, family: family);
  }

  @override
  bool operator ==(Object other) =>
      other is MidiTarget && other.param == param && other.family == family;

  @override
  int get hashCode => Object.hash(param, family);

  @override
  String toString() => 'MidiTarget($id)';
}

/// `byName` without the throw: an unknown name is a mapping from another
/// version, not a crash.
T? _byName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
