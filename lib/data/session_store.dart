import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/palette.dart';
import '../domain/pad_config.dart';
import '../domain/session.dart';
import '../domain/sound.dart';
import 'factory_kit.dart';
import 'sound_library.dart';
import 'storage.dart';

const _uuid = Uuid();

/// The list of saved sessions. Each one remembers its four banks, their
/// settings and the tempo — but never which loops were running.
class SessionStore extends ChangeNotifier {
  SessionStore(this._storage);

  final Storage _storage;
  final List<Session> _sessions = [];

  List<Session> get sessions {
    final sorted = List<Session>.of(_sessions)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(sorted);
  }

  bool get isEmpty => _sessions.isEmpty;

  Future<void> load() async {
    final file = _storage.sessionsIndex;
    if (await file.exists()) {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _sessions
        ..clear()
        ..addAll(raw.map((e) => Session.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  /// The session the app opens with. On a fresh install this is a new one
  /// already carrying the factory kit, so there is never an empty grid.
  Future<Session> firstOrCreate(SoundLibrary library) async {
    if (_sessions.isNotEmpty) return sessions.first;
    final session = buildStarterSession(library);
    await save(session);
    return session;
  }

  Future<void> save(Session session) async {
    final index = _sessions.indexWhere((s) => s.id == session.id);
    final stamped = session.copyWith(updatedAt: DateTime.now());
    if (index == -1) {
      _sessions.add(stamped);
    } else {
      _sessions[index] = stamped;
    }
    await _persist();
    notifyListeners();
  }

  Future<Session> duplicate(Session source) async {
    final copy = Session(
      id: _uuid.v4(),
      name: '${source.name} copia',
      bpm: source.bpm,
      banks: source.banks,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await save(copy);
    return copy;
  }

  Future<void> rename(Session session, String name) =>
      save(session.copyWith(name: name));

  Future<void> remove(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final data = _sessions.map((s) => s.toJson()).toList();
    await _storage.sessionsIndex.writeAsString(jsonEncode(data));
  }
}

/// Builds a session with banks A and B loaded from the factory kit, and C and
/// D left empty on purpose: C fills with your recordings, D is yours.
Session buildStarterSession(SoundLibrary library, {String name = 'Sesión 1'}) {
  final base = Session.blank(id: _uuid.v4(), name: name);
  var session = base;

  kFactoryBanks.forEach((bankIndex, pads) {
    for (var slot = 0; slot < pads.length; slot++) {
      final definition = pads[slot];
      final sound = library.byId(definition.soundId);
      if (sound == null) continue;
      session = session.withPad(
        bankIndex,
        slot,
        PadConfig(
          soundId: sound.id,
          mode: PadMode.oneShot,
          loopSteps: definition.loopSteps,
        ),
      );
    }
  });

  return session;
}

/// Registers a freshly captured file in the library.
Future<Sound> registerRecording({
  required SoundLibrary library,
  required String fileName,
  required String name,
  required SoundFamily family,
  required int durationMs,
  required int sizeBytes,
  SoundOrigin origin = SoundOrigin.recorded,
}) {
  return library.add(Sound(
    id: _uuid.v4(),
    name: name,
    family: family,
    fileName: fileName,
    origin: origin,
    durationMs: durationMs,
    sizeBytes: sizeBytes,
  ));
}
