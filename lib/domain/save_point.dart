import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import 'session.dart';

const _uuid = Uuid();

/// A named snapshot of a session, kept so a good state can be come back to.
///
/// Undo walks backwards a step at a time; this is the other half — "this is
/// how it sounded before I started changing everything". The session writes
/// itself to disk 800 ms after every edit, so without these there is no way
/// back to a state that was worth keeping.
///
/// A snapshot costs references rather than data: [Session] is immutable, so
/// holding one is holding what was already there.
class SavePoint {
  const SavePoint({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.createdAt,
    required this.session,
  });

  factory SavePoint.capture(Session session, {required String name}) {
    return SavePoint(
      id: _uuid.v4(),
      sessionId: session.id,
      name: name,
      createdAt: DateTime.now(),
      session: session,
    );
  }

  final String id;

  /// Which session this belongs to. Points are listed and capped per session.
  final String sessionId;

  final String name;
  final DateTime createdAt;

  /// What was there when it was taken.
  final Session session;

  /// The snapshot's contents put back onto [current], which keeps its own
  /// identity.
  ///
  /// That is the rule the rest depends on: restoring returns the *contents*,
  /// never the id, name or birth date. Bringing those back would leave the
  /// session list pointing at a ghost, or quietly fork the session in two.
  Session restoreOnto(Session current) {
    return current.copyWith(
      bpm: session.bpm,
      banks: session.banks,
      patterns: session.patterns,
      activePattern: session.activePattern,
      chainLength: session.chainLength,
      swing: session.swing,
      scale: session.scale,
      root: session.root,
      octave: session.octave,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'session': session.toJson(),
      };

  factory SavePoint.fromJson(Map<String, dynamic> json) => SavePoint(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        session: Session.fromJson(
          Map<String, dynamic>.from(json['session'] as Map),
        ),
      );
}

/// Newest first, which is the order they are looked for in.
List<SavePoint> sortedSavePoints(Iterable<SavePoint> points) =>
    List<SavePoint>.of(points)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// Adds [point] to [all], dropping the oldest of *its own session* once that
/// session is over the cap.
///
/// Capped per session rather than in total: filling one session with points
/// must never quietly delete another session's.
List<SavePoint> withSavePoint(List<SavePoint> all, SavePoint point) {
  final next = List<SavePoint>.of(all)..add(point);
  final mine = sortedSavePoints(
    next.where((p) => p.sessionId == point.sessionId),
  );
  if (mine.length <= kSavePointsPerSession) return next;

  final doomed =
      mine.skip(kSavePointsPerSession).map((p) => p.id).toSet();
  return next.where((p) => !doomed.contains(p.id)).toList();
}
