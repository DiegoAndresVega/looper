/// The order the sessions are played in tonight.
///
/// The RC-505 keeps 99 phrase memories and Loopy Pro keeps set lists; this is
/// the smaller half of that idea, and the useful one: a running order, so the
/// next piece is one tap away instead of a name to find in a list while people
/// are watching.
///
/// It lives beside the sessions rather than inside one, like the controller
/// map does. A set list belongs to the gig, not to any of the pieces in it —
/// and a session can be dropped from tonight's order without being touched.
class SetList {
  const SetList(this.sessionIds);

  const SetList.empty() : sessionIds = const [];

  /// Session ids, in playing order. A session appears at most once: an order
  /// that lists the same piece twice cannot answer «what comes next».
  final List<String> sessionIds;

  bool get isEmpty => sessionIds.isEmpty;
  bool get isNotEmpty => sessionIds.isNotEmpty;
  int get length => sessionIds.length;

  bool contains(String id) => sessionIds.contains(id);

  /// Where a session sits in the order, counting from one — the way it is
  /// written on a piece of paper taped to the desk. Null when it is not in.
  int? positionOf(String id) {
    final at = sessionIds.indexOf(id);
    return at == -1 ? null : at + 1;
  }

  /// What comes after [id], or null at the end of the night. It does not wrap
  /// on purpose: an encore is a decision, not a default.
  String? nextAfter(String id) {
    final at = sessionIds.indexOf(id);
    if (at == -1 || at == sessionIds.length - 1) return null;
    return sessionIds[at + 1];
  }

  SetList appended(String id) =>
      contains(id) ? this : SetList([...sessionIds, id]);

  SetList removed(String id) =>
      SetList([...sessionIds]..removeWhere((s) => s == id));

  /// Swaps an entry with the one [delta] places away. Two arrows, never a
  /// drag: the list is short and a drag on a phone fights the scroll.
  SetList movedAt(int index, int delta) {
    final target = index + delta;
    if (!_isValid(index) || !_isValid(target)) return this;
    final next = [...sessionIds];
    next[index] = sessionIds[target];
    next[target] = sessionIds[index];
    return SetList(next);
  }

  /// Drops the sessions that no longer exist. Deleting a session has to take
  /// it out of tonight's order too, or the order points at a ghost.
  SetList prunedTo(Set<String> existing) {
    final kept = sessionIds.where(existing.contains).toList();
    return kept.length == sessionIds.length ? this : SetList(kept);
  }

  bool _isValid(int index) => index >= 0 && index < sessionIds.length;

  List<String> toJson() => List<String>.of(sessionIds);

  /// Anything that is not a list of ids comes back empty: a broken running
  /// order is an inconvenience, never a reason to refuse to open the app.
  factory SetList.fromJson(dynamic json) {
    if (json is! List) return const SetList.empty();
    return SetList([
      for (final id in json)
        if (id is String) id,
    ]);
  }
}
