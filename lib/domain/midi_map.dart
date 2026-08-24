/// Which physical control moves what.
///
/// Immutable, like everything else that gets handed to the UI and to the
/// engine at once: a marriage builds a new map rather than writing into the
/// old one.
///
/// **The channel is ignored on purpose.** A knob is that knob whatever channel
/// it shouts on, and the notes already work the same way. The day someone
/// plugs in two controllers that both send CC 21, this is the line that has to
/// change — and it will be obvious, because one knob will move two things.
library;

import 'midi_target.dart';

/// One control married to one parameter.
typedef MidiBinding = ({int controller, MidiTarget target});

class MidiMap {
  const MidiMap(this._targets);

  const MidiMap.empty() : _targets = const {};

  /// Control number → what it moves.
  final Map<int, MidiTarget> _targets;

  int get length => _targets.length;
  bool get isEmpty => _targets.isEmpty;
  bool get isNotEmpty => _targets.isNotEmpty;

  /// What control number [controller] moves, or null when nothing is married
  /// to it — which is the normal answer for most of the 128.
  MidiTarget? targetFor(int controller) => _targets[controller];

  /// Which control moves [target], for the knob to write it on itself.
  int? controllerFor(MidiTarget target) {
    for (final entry in _targets.entries) {
      if (entry.value == target) return entry.key;
    }
    return null;
  }

  /// Every marriage, lowest control number first.
  List<MidiBinding> get bindings {
    final numbers = _targets.keys.toList()..sort();
    return List.unmodifiable([
      for (final n in numbers) (controller: n, target: _targets[n]!),
    ]);
  }

  /// Marries [controller] to [target], breaking whatever either of them was
  /// married to before.
  ///
  /// Both directions matter. One control moving two parameters is a controller
  /// that fights itself; one parameter answering to two controls is a value
  /// that jumps when the forgotten knob is nudged.
  MidiMap learn(int controller, MidiTarget target) {
    return MidiMap({
      for (final entry in _targets.entries)
        if (entry.key != controller && entry.value != target)
          entry.key: entry.value,
      controller: target,
    });
  }

  MidiMap forget(MidiTarget target) {
    return MidiMap({
      for (final entry in _targets.entries)
        if (entry.value != target) entry.key: entry.value,
    });
  }

  Map<String, dynamic> toJson() => {
        for (final entry in _targets.entries)
          entry.key.toString(): entry.value.id,
      };

  /// Anything unreadable is dropped rather than thrown: a mapping file written
  /// by another version must not cost the player the mappings that still work.
  factory MidiMap.fromJson(Map<String, dynamic> json) {
    final targets = <int, MidiTarget>{};
    for (final entry in json.entries) {
      final controller = int.tryParse(entry.key);
      final target = MidiTarget.parse('${entry.value}');
      if (controller == null || target == null) continue;
      if (controller < 0 || controller > 127) continue;
      targets[controller] = target;
    }
    return MidiMap(targets);
  }

  @override
  bool operator ==(Object other) {
    if (other is! MidiMap || other.length != length) return false;
    for (final entry in _targets.entries) {
      if (other._targets[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        _targets.entries.map((e) => Object.hash(e.key, e.value)),
      );
}
