import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/save_point.dart';
import '../domain/session.dart';
import 'storage.dart';

/// The named snapshots, for every session at once.
///
/// They live in their own file rather than inside each session: a session
/// document that carried eight copies of its own past would be rewritten
/// whole on every autosave, eight times the size, for something read once in
/// a blue moon.
class SavePointStore extends ChangeNotifier {
  SavePointStore(this._storage);

  final Storage _storage;
  List<SavePoint> _points = const [];

  /// This session's snapshots, newest first.
  List<SavePoint> forSession(String sessionId) => List.unmodifiable(
        sortedSavePoints(_points.where((p) => p.sessionId == sessionId)),
      );

  int countFor(String sessionId) =>
      _points.where((p) => p.sessionId == sessionId).length;

  Future<void> load() async {
    final file = _storage.savePointsIndex;
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
        _points = raw
            .map((e) => SavePoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } on Object catch (e) {
        // A corrupt history is not worth taking the app down for: the
        // sessions themselves are elsewhere and still fine.
        debugPrint('No se pudieron leer los puntos de guardado: $e');
        _points = const [];
      }
    }
    notifyListeners();
  }

  Future<SavePoint> capture(Session session, {required String name}) async {
    final point = SavePoint.capture(session, name: name);
    _points = withSavePoint(_points, point);
    await _persist();
    notifyListeners();
    return point;
  }

  Future<void> remove(String id) async {
    _points = _points.where((p) => p.id != id).toList();
    await _persist();
    notifyListeners();
  }

  /// Drops a whole session's history. Called when the session itself goes, so
  /// snapshots of something deleted do not pile up for ever.
  Future<void> removeForSession(String sessionId) async {
    _points = _points.where((p) => p.sessionId != sessionId).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final data = _points.map((p) => p.toJson()).toList();
    await _storage.savePointsIndex.writeAsString(jsonEncode(data));
  }
}
