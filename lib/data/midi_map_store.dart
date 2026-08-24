import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/midi_map.dart';
import 'storage.dart';

/// Keeps the controller mapping between runs.
///
/// Learning a knob once and finding it learned tomorrow is the whole point:
/// a mapping that evaporated on every launch would be slower than reaching for
/// the screen.
class MidiMapStore {
  MidiMapStore(this._storage);

  final Storage _storage;

  Future<MidiMap> load() async {
    final file = _storage.midiMapIndex;
    if (!await file.exists()) return const MidiMap.empty();
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return MidiMap.fromJson(raw);
    } on Object catch (e) {
      // A broken mapping is an inconvenience, not a reason to refuse to start.
      debugPrint('No se pudo leer el mapa del controlador: $e');
      return const MidiMap.empty();
    }
  }

  Future<void> save(MidiMap map) async {
    try {
      await _storage.midiMapIndex.writeAsString(jsonEncode(map.toJson()));
    } on Object catch (e) {
      debugPrint('No se pudo guardar el mapa del controlador: $e');
    }
  }
}
