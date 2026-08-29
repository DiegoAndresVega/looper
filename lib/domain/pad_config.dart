import '../core/constants.dart';

/// How a pad answers a second hit while the first is still ringing. The
/// RC-505 gives four modes per track; these are the three that change what a
/// finger can do — the fourth, reverse, is the sound's own business and lives
/// in the library.
enum PadPlayMode {
  /// A new hit cuts the one before it. Fast tapping reads as a roll, which is
  /// what a drum pad does, and it is why this is the default.
  cut('Corte'),

  /// Hits pile up. Eight taps on a bell leave eight bells ringing — the RC-505
  /// calls this multi, and it is the difference between a pad and a drum.
  layer('Capas'),

  /// Plays through and refuses to be interrupted, itself included. A stab or
  /// a spoken line that must not stutter.
  once('Una vez');

  const PadPlayMode(this.label);

  final String label;
}

/// What a fresh hit does to the voice the same pad already has running.
enum HitAction { cutPrevious, layer, ignore }

/// The rule, on its own so it can be read and tested without an engine.
HitAction hitActionFor({
  required PadPlayMode mode,
  required bool isSounding,
}) =>
    switch (mode) {
      PadPlayMode.cut => HitAction.cutPrevious,
      PadPlayMode.layer => HitAction.layer,
      PadPlayMode.once => isSounding ? HitAction.ignore : HitAction.layer,
    };

/// Which of the voices in [sounding] this hit cuts short.
///
/// [sounding] maps each ringing pad's key to its choke group. A pad never
/// appears among its own victims: what a pad does to itself is [PadPlayMode]'s
/// business, and mixing the two rules would make a pad in a group unable to
/// layer with itself.
Set<String> chokeVictims({
  required String firingKey,
  required int group,
  required Map<String, int> sounding,
}) {
  if (group == kNoChokeGroup) return const {};
  return {
    for (final entry in sounding.entries)
      if (entry.key != firingKey && entry.value == group) entry.key,
  };
}

/// What one of the 64 pads holds. An empty pad has no [soundId].
///
/// The gesture still decides the big thing — a tap fires, a long press loops.
/// What the pad remembers is how it behaves once it is going: how a second hit
/// treats the first, and which other pads it cannot sound alongside.
class PadConfig {
  const PadConfig({
    this.soundId,
    this.volume = 0.8,
    this.semitones = 0,
    this.loopSteps = kStepsPerBar,
    this.synced = true,
    this.muted = false,
    this.pan = 0,
    this.playMode = PadPlayMode.cut,
    int chokeGroup = kNoChokeGroup,
  }) : chokeGroup = chokeGroup < kNoChokeGroup
            ? kNoChokeGroup
            : (chokeGroup > kChokeGroups ? kChokeGroups : chokeGroup);

  static const PadConfig empty = PadConfig();

  final String? soundId;
  final double volume;
  final int semitones;

  /// Loop length in 16th notes. Only meaningful when [synced] is true;
  /// a free loop runs at its own natural length.
  final int loopSteps;

  /// Whether the loop rides the tempo grid. On by default: an instrument
  /// where two pads left running do not line up is not an instrument.
  final bool synced;
  final bool muted;

  /// Where the pad sits across the stereo field, -1 left to 1 right. The
  /// files are mono, but the engine is not: separating two parts is the
  /// cheapest way to let a mix breathe.
  final double pan;

  /// What a second hit does while the first is still ringing.
  final PadPlayMode playMode;

  /// Which choke group the pad belongs to, or [kNoChokeGroup]. Pads sharing a
  /// group cut each other short.
  final int chokeGroup;

  bool get isEmpty => soundId == null;

  PadConfig copyWith({
    String? soundId,
    bool clearSound = false,
    double? volume,
    int? semitones,
    int? loopSteps,
    bool? synced,
    bool? muted,
    double? pan,
    PadPlayMode? playMode,
    int? chokeGroup,
  }) {
    return PadConfig(
      soundId: clearSound ? null : (soundId ?? this.soundId),
      volume: volume ?? this.volume,
      semitones: semitones ?? this.semitones,
      loopSteps: loopSteps ?? this.loopSteps,
      synced: synced ?? this.synced,
      muted: muted ?? this.muted,
      pan: pan ?? this.pan,
      playMode: playMode ?? this.playMode,
      chokeGroup: chokeGroup ?? this.chokeGroup,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundId': soundId,
        'volume': volume,
        'semitones': semitones,
        'loopSteps': loopSteps,
        'sync': synced,
        'muted': muted,
        'pan': pan,
        'playMode': playMode.name,
        'chokeGroup': chokeGroup,
      };

  /// Sessions saved before the gesture rewrite carry a 'mode' key, and ones
  /// saved before loops were put on the grid carry 'synced'. Both are ignored
  /// on purpose: 'synced' was written false for every pad back when free
  /// running was the default, and reading it back would keep old sessions out
  /// of time forever. The new key is 'sync', so an old session simply takes
  /// the new default.
  factory PadConfig.fromJson(Map<String, dynamic> json) => PadConfig(
        soundId: json['soundId'] as String?,
        volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
        semitones: json['semitones'] as int? ?? 0,
        loopSteps: json['loopSteps'] as int? ?? kStepsPerBar,
        synced: json['sync'] as bool? ?? true,
        muted: json['muted'] as bool? ?? false,
        // A pad written before panning existed sat in the middle.
        pan: (json['pan'] as num?)?.toDouble() ?? 0,
        // And one written before the modes cut its own tail and choked
        // nobody, which is what these defaults say.
        playMode: PadPlayMode.values.asNameMap()[json['playMode'] as String?] ??
            PadPlayMode.cut,
        chokeGroup: (json['chokeGroup'] as num?)?.toInt() ?? kNoChokeGroup,
      );
}

/// Whether a pad is silent right now, given which pad — if any — is soloed.
///
/// Solo deliberately lives *outside* [PadConfig]. The first version wrote
/// `muted: true` onto every other pad to implement it and `muted: false` onto
/// every one of them to undo it, which threw away the mutes the player had set
/// by hand — and the session autosaves, so the loss was written to disk.
///
/// The rule is the one every mixer uses: while a solo is up it decides alone,
/// and the manual mutes wait underneath for it to come down. Soloing a muted
/// pad therefore lets it through, because that is what the finger just asked
/// for.
bool isPadSilenced({
  required PadConfig pad,
  required String key,
  required String? soloKey,
}) =>
    soloKey == null ? pad.muted : soloKey != key;

/// One page of the grid. Four of these make up a session.
class Bank {
  const Bank({required this.id, required this.label, required this.pads});

  final String id;
  final String label;
  final List<PadConfig> pads;

  factory Bank.blank(String id, String label) => Bank(
        id: id,
        label: label,
        pads: List<PadConfig>.filled(kPadsPerBank, PadConfig.empty),
      );

  bool get isEmpty => pads.every((p) => p.isEmpty);
  int get filledCount => pads.where((p) => !p.isEmpty).length;

  /// Index of the first pad with nothing on it, or null when the bank is full.
  int? get firstFreeSlot {
    final i = pads.indexWhere((p) => p.isEmpty);
    return i == -1 ? null : i;
  }

  /// Returns a new bank with [pad] at [slot]. The original is untouched.
  Bank withPad(int slot, PadConfig pad) {
    final next = List<PadConfig>.of(pads);
    next[slot] = pad;
    return Bank(id: id, label: label, pads: next);
  }

  Bank copyWith({String? label, List<PadConfig>? pads}) =>
      Bank(id: id, label: label ?? this.label, pads: pads ?? this.pads);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pads': pads.map((p) => p.toJson()).toList(),
      };

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] as String,
        label: json['label'] as String,
        pads: (json['pads'] as List<dynamic>)
            .map((p) => PadConfig.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
