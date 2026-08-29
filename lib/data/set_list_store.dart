import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/set_list.dart';
import 'storage.dart';

/// Keeps tonight's running order between runs.
///
/// A [ChangeNotifier] rather than a plain reader/writer because two places
/// show the order at once — the number on each session's row and the «what
/// comes next» line — and they must never disagree.
class SetListStore extends ChangeNotifier {
  SetListStore(this._storage);

  final Storage _storage;

  SetList _list = const SetList.empty();

  SetList get list => _list;

  Future<void> load() async {
    final file = _storage.setListIndex;
    if (!await file.exists()) return;
    try {
      _list = SetList.fromJson(jsonDecode(await file.readAsString()));
    } on Object catch (e) {
      // A broken running order is an inconvenience, not a reason to refuse
      // to start: the sessions themselves are all still there.
      debugPrint('No se pudo leer la lista de actuación: $e');
      _list = const SetList.empty();
    }
    notifyListeners();
  }

  Future<void> add(String sessionId) => _write(_list.appended(sessionId));

  Future<void> remove(String sessionId) => _write(_list.removed(sessionId));

  Future<void> move(int index, int delta) =>
      _write(_list.movedAt(index, delta));

  /// Drops the sessions that no longer exist. Called after a delete, so the
  /// order can never point at something that is gone.
  Future<void> prune(Set<String> existingIds) {
    final next = _list.prunedTo(existingIds);
    return identical(next, _list) ? Future<void>.value() : _write(next);
  }

  Future<void> _write(SetList next) async {
    _list = next;
    notifyListeners();
    try {
      await _storage.setListIndex.writeAsString(jsonEncode(next.toJson()));
    } on Object catch (e) {
      debugPrint('No se pudo guardar la lista de actuación: $e');
    }
  }
}
