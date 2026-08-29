import '../core/constants.dart';
import 'chord.dart';
import 'pad_config.dart';
import 'scale.dart';
import 'pattern.dart';
import 'scene.dart';
import 'song.dart';

/// Everything a saved session remembers: which sound sits on each of the 64
/// pads, their settings and the tempo. Active loops are not persisted — a
/// session opens silent and you decide what starts.
class Session {
  const Session({
    required this.id,
    required this.name,
    required this.bpm,
    required this.banks,
    required this.createdAt,
    required this.updatedAt,
    required this.patterns,
    required this.scenes,
    this.activePattern = 0,
    this.chainLength = 1,
    this.song = const Song.empty(),
    this.songMode = false,
    this.isTemplate = false,
    this.swing = kSwingDefault,
    this.scale = Scale.pentatonicMinor,
    this.root = 0,
    this.octave = 0,
    this.chord = ChordVoicing.single,
    this.arp = ArpMode.off,
  });

  final String id;
  final String name;
  final int bpm;
  final List<Bank> banks;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The sixteen step patterns and which one is on the grid. They travel with
  /// the session because a pattern only means something next to its pads.
  final List<Pattern> patterns;
  final int activePattern;

  /// How many patterns play back to back, 1..16 bars.
  final int chainLength;

  /// The running order when the chain is not enough: any pattern, any number
  /// of bars, in any order. It travels with the session because it *is* the
  /// piece — the chain and the song are two answers to the same question, and
  /// [songMode] says which one is being asked.
  final Song song;
  final bool songMode;

  /// Whether this session is a starting point rather than a piece: a kit and
  /// a tempo you want every new session to begin from. It travels with the
  /// session because it *is* a property of this one, and duplicating a
  /// template gives another template — starting *from* one is a different
  /// action, and that one clears the flag.
  final bool isTemplate;

  /// The eight scenes: what was looping and which pattern went with it. Part
  /// of the session for the same reason the patterns are — a scene names pads
  /// of this session and means nothing next to another one's.
  final List<Scene> scenes;

  /// How much the off-beat sixteenths lag. It belongs to the session because
  /// it is part of how the pattern is meant to be felt, like the tempo.
  final double swing;

  /// What the grid plays when it is being used as a keyboard: which scale,
  /// which note it starts on, and how high. Kept with the session because a
  /// key is part of a piece, not a knob position.
  final Scale scale;
  final int root;
  final int octave;

  /// How many notes a key plays, and whether they arrive together or one
  /// after another. They belong next to the scale for the same reason the
  /// scale belongs to the session: they are part of the key of the piece,
  /// not a knob position that resets.
  final ChordVoicing chord;
  final ArpMode arp;

  factory Session.blank({required String id, required String name}) {
    final now = DateTime.now();
    return Session(
      id: id,
      name: name,
      bpm: kDefaultBpm,
      banks: [
        Bank.blank('A', 'Kit'),
        Bank.blank('B', 'Techno'),
        Bank.blank('C', 'Mías'),
        Bank.blank('D', 'Libre'),
      ],
      patterns: List.generate(kPatternCount, (_) => Pattern.empty()),
      scenes: emptyScenes(),
      createdAt: now,
      updatedAt: now,
    );
  }

  int get filledPadCount =>
      banks.fold(0, (sum, bank) => sum + bank.filledCount);

  int get usedBankCount => banks.where((b) => !b.isEmpty).length;

  PadConfig padAt(int bankIndex, int slot) => banks[bankIndex].pads[slot];

  /// Returns a new session with one pad replaced.
  Session withPad(int bankIndex, int slot, PadConfig pad) {
    final next = List<Bank>.of(banks);
    next[bankIndex] = next[bankIndex].withPad(slot, pad);
    return copyWith(banks: next);
  }

  /// Returns a new session with a whole bank replaced.
  Session withBank(int bankIndex, Bank bank) {
    final next = List<Bank>.of(banks);
    next[bankIndex] = bank;
    return copyWith(banks: next);
  }

  /// Returns a new session with one scene replaced. An index outside the
  /// eight is ignored rather than thrown: the strip is the only caller and it
  /// cannot produce one, but a scene lost is better than a session lost.
  Session withScene(int index, Scene scene) {
    if (index < 0 || index >= kScenesPerSession) return this;
    final next = List<Scene>.of(scenes);
    next[index] = scene;
    return copyWith(scenes: next);
  }

  /// First free slot across banks, searching C first because that is where
  /// recordings land, then D, then A and B.
  ({int bank, int slot})? get nextFreeSlot {
    for (final bankIndex in [2, 3, 0, 1]) {
      final slot = banks[bankIndex].firstFreeSlot;
      if (slot != null) return (bank: bankIndex, slot: slot);
    }
    return null;
  }

  /// A copy of this session under a new identity. Everything else travels:
  /// banks, patterns, tempo and how many bars the chain runs.
  ///
  /// It lives here, next to [copyWith], because the first version of this
  /// listed the fields at the call site and quietly forgot [chainLength] — a
  /// duplicated eight-bar session came back playing one. A field added to the
  /// class now has to be added inches away from where a copy is made.
  Session duplicateAs({required String id, required String name}) {
    final now = DateTime.now();
    return Session(
      id: id,
      name: name,
      bpm: bpm,
      banks: banks,
      patterns: patterns,
      activePattern: activePattern,
      chainLength: chainLength,
      song: song,
      songMode: songMode,
      scenes: scenes,
      isTemplate: isTemplate,
      swing: swing,
      scale: scale,
      root: root,
      octave: octave,
      chord: chord,
      arp: arp,
      createdAt: now,
      updatedAt: now,
    );
  }

  Session copyWith({
    String? name,
    int? bpm,
    List<Bank>? banks,
    List<Pattern>? patterns,
    int? activePattern,
    int? chainLength,
    Song? song,
    bool? songMode,
    List<Scene>? scenes,
    bool? isTemplate,
    double? swing,
    Scale? scale,
    int? root,
    int? octave,
    ChordVoicing? chord,
    ArpMode? arp,
    DateTime? updatedAt,
  }) {
    return Session(
      id: id,
      name: name ?? this.name,
      bpm: bpm ?? this.bpm,
      banks: banks ?? this.banks,
      patterns: patterns ?? this.patterns,
      activePattern: activePattern ?? this.activePattern,
      chainLength: chainLength ?? this.chainLength,
      song: song ?? this.song,
      songMode: songMode ?? this.songMode,
      scenes: scenes ?? this.scenes,
      isTemplate: isTemplate ?? this.isTemplate,
      swing: swing ?? this.swing,
      scale: scale ?? this.scale,
      root: root ?? this.root,
      octave: octave ?? this.octave,
      chord: chord ?? this.chord,
      arp: arp ?? this.arp,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bpm': bpm,
        'banks': banks.map((b) => b.toJson()).toList(),
        'patterns': patterns.map((p) => p.toJson()).toList(),
        'activePattern': activePattern,
        'chainLength': chainLength,
        'song': song.toJson(),
        'songMode': songMode,
        'scenes': scenes.map((s) => s.toJson()).toList(),
        'isTemplate': isTemplate,
        'swing': swing,
        'scale': scale.name,
        'root': root,
        'octave': octave,
        'chord': chord.name,
        'arp': arp.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Sessions saved before the sequencer existed simply come back with empty
  /// patterns instead of failing to open.
  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        name: json['name'] as String,
        bpm: json['bpm'] as int,
        banks: (json['banks'] as List<dynamic>)
            .map((b) => Bank.fromJson(b as Map<String, dynamic>))
            .toList(),
        patterns: _patternsFrom(json['patterns'] as List<dynamic>?),
        activePattern: json['activePattern'] as int? ?? 0,
        chainLength: json['chainLength'] as int? ?? 1,
        // A session written before songs and scenes existed opens with
        // neither, which is exactly what it was saved with.
        song: Song.fromJson(json['song']),
        songMode: json['songMode'] as bool? ?? false,
        scenes: _scenesFrom(json['scenes'] as List<dynamic>?),
        isTemplate: json['isTemplate'] as bool? ?? false,
        // A session written before swing existed was played straight.
        swing: (json['swing'] as num?)?.toDouble() ?? kSwingDefault,
        // A session written before the grid could play a scale opens on the
        // one that cannot sound wrong.
        scale: Scale.values.asNameMap()[json['scale'] as String?] ??
            Scale.pentatonicMinor,
        root: json['root'] as int? ?? 0,
        octave: json['octave'] as int? ?? 0,
        chord: ChordVoicing.values.asNameMap()[json['chord'] as String?] ??
            ChordVoicing.single,
        arp: ArpMode.values.asNameMap()[json['arp'] as String?] ?? ArpMode.off,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  /// Always eight, however many the file carries: the strip asks for scene
  /// six without checking, the same way the grid asks for pattern six.
  static List<Scene> _scenesFrom(List<dynamic>? raw) => List.generate(
        kScenesPerSession,
        (i) => raw != null && i < raw.length
            ? Scene.fromJson(raw[i])
            : const Scene.empty(),
      );

  /// No cast on the way in: a pattern is a bare list in sessions written
  /// before accents existed and a map in the ones written since, and
  /// [Pattern.fromJson] is the one place that knows the difference.
  static List<Pattern> _patternsFrom(List<dynamic>? raw) {
    return List.generate(
      kPatternCount,
      (i) => raw != null && i < raw.length
          ? Pattern.fromJson(raw[i])
          : Pattern.empty(),
    );
  }
}
