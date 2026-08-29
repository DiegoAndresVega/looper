import '../core/constants.dart';

/// What is playing, remembered so it can be brought back with one finger.
///
/// GarageBand's Live Loops teaches song structure with a single rule: rows
/// are instruments, columns are scenes, and firing a column launches the whole
/// section. Looper's grid is already spoken for — it is the pads — so the
/// scenes live in a strip of their own, but they hold the same thing a column
/// holds: which loops sound, and which pattern goes with them.
///
/// A scene is contents, never identity: it names pads by their key, so an
/// empty pad in the scene simply does not start. That is what lets a scene
/// survive the session being rebuilt around it.
class Scene {
  const Scene({required this.loops, this.pattern = 0});

  const Scene.empty() : loops = const {}, pattern = 0;

  /// A snapshot of what is looping right now. The set is copied on the way in:
  /// the caller's live map of loops keeps changing, and a scene that changed
  /// with it would not be a snapshot of anything.
  factory Scene.capture({
    required Set<String> loops,
    required int pattern,
  }) =>
      Scene(loops: Set.unmodifiable(Set<String>.of(loops)), pattern: pattern);

  /// Pad keys ('bank:slot'), the same currency patterns are written in.
  final Set<String> loops;

  /// Which of the sixteen patterns belongs with this section.
  final int pattern;

  bool get isEmpty => loops.isEmpty;

  Map<String, dynamic> toJson() => {
        'loops': loops.toList()..sort(),
        'pattern': pattern,
      };

  factory Scene.fromJson(dynamic json) {
    if (json is! Map) return const Scene.empty();
    final loops = json['loops'];
    return Scene(
      loops: Set.unmodifiable({
        if (loops is List)
          for (final key in loops)
            if (key is String) key,
      }),
      pattern: (json['pattern'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What a scene change actually costs: the loops to start and the ones to
/// stop. Nothing else moves — a pad in both the old scene and the new one is
/// left alone rather than stopped and started again, which would put a hole
/// in the middle of a sound that was supposed to carry on.
class SceneChange {
  const SceneChange({required this.start, required this.stop});

  final Set<String> start;
  final Set<String> stop;

  bool get isNothing => start.isEmpty && stop.isEmpty;
}

/// Works out the change from what is [playing] to what [scene] asks for.
///
/// Pure on purpose: the controller has an audio engine behind it and cannot
/// be tested without a device, but this — the half that decides what happens
/// — is just two sets.
SceneChange sceneTransition({
  required Set<String> playing,
  required Scene scene,
}) {
  return SceneChange(
    start: scene.loops.difference(playing),
    stop: playing.difference(scene.loops),
  );
}

/// The eight scenes a session always has, however few of them are filled.
List<Scene> emptyScenes() =>
    List<Scene>.filled(kScenesPerSession, const Scene.empty());
