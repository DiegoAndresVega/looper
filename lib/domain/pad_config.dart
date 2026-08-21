import '../core/constants.dart';

/// What one of the 64 pads holds. An empty pad has no [soundId].
///
/// There is no play mode stored here: the gesture decides. A tap fires the
/// sound, a long press leaves it looping. What the pad remembers is only how
/// the loop behaves once it is running.
class PadConfig {
  const PadConfig({
    this.soundId,
    this.volume = 0.8,
    this.semitones = 0,
    this.loopSteps = kStepsPerBar,
    this.synced = true,
    this.muted = false,
  });

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

  bool get isEmpty => soundId == null;

  PadConfig copyWith({
    String? soundId,
    bool clearSound = false,
    double? volume,
    int? semitones,
    int? loopSteps,
    bool? synced,
    bool? muted,
  }) {
    return PadConfig(
      soundId: clearSound ? null : (soundId ?? this.soundId),
      volume: volume ?? this.volume,
      semitones: semitones ?? this.semitones,
      loopSteps: loopSteps ?? this.loopSteps,
      synced: synced ?? this.synced,
      muted: muted ?? this.muted,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundId': soundId,
        'volume': volume,
        'semitones': semitones,
        'loopSteps': loopSteps,
        'sync': synced,
        'muted': muted,
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
