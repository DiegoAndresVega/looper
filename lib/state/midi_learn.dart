import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/midi_map_store.dart';
import '../domain/midi.dart';
import '../domain/midi_map.dart';
import '../domain/midi_target.dart';

/// The one gesture: hold a knob on screen, move a control on the desk, and
/// they are married. No menus, no lists of CC numbers to type in.
///
/// Arming lasts until something moves or the player changes their mind — the
/// same bargain AJUSTAR makes on the grid, where a mode lasts exactly one
/// action.
class MidiLearn extends ChangeNotifier {
  /// Without a store the mapping still works, it just does not survive the
  /// app closing — which is exactly what a test wants.
  MidiLearn([this._store]);

  final MidiMapStore? _store;

  MidiMap _map = const MidiMap.empty();
  MidiTarget? _armed;

  MidiMap get map => _map;

  /// The knob waiting for a control, or null when nothing is listening.
  MidiTarget? get armed => _armed;

  bool isArmed(MidiTarget target) => _armed == target;

  /// Which control moves [target] today, for the knob to wear the number.
  int? controllerFor(MidiTarget target) => _map.controllerFor(target);

  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    _map = await store.load();
    notifyListeners();
  }

  /// Waits for the next control to arrive and gives it to [target]. Arming a
  /// second knob drops the first: only one thing can be listening.
  void arm(MidiTarget target) {
    _armed = target;
    notifyListeners();
  }

  void cancel() {
    if (_armed == null) return;
    _armed = null;
    notifyListeners();
  }

  void forget(MidiTarget target) {
    if (_map.controllerFor(target) == null) return;
    _map = _map.forget(target);
    _armed = null;
    _persist();
    notifyListeners();
  }

  void forgetEverything() {
    if (_map.isEmpty) return;
    _map = const MidiMap.empty();
    _armed = null;
    _persist();
    notifyListeners();
  }

  /// What an arriving control change should move.
  ///
  /// When a knob is waiting, this is where the marriage happens — and the very
  /// move that marries them is also returned, so the parameter jumps to where
  /// the physical control already is instead of waiting for a second nudge.
  MidiTarget? route(MidiControlChange change) {
    final armed = _armed;
    if (armed != null) {
      _map = _map.learn(change.controller, armed);
      _armed = null;
      _persist();
      notifyListeners();
      return armed;
    }
    return _map.targetFor(change.controller);
  }

  /// Writing the file is not worth making a knob move wait for.
  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.save(_map));
  }
}

/// A control change's value as a knob position.
double positionFromMidi(int value) => (value / 127).clamp(0.0, 1.0);
