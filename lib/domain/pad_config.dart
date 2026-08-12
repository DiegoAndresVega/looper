import '../core/constants.dart';

/// A pad either fires once while touched, or keeps repeating until switched off.
enum PadMode { oneShot, loop }

/// What one of the 64 pads holds. An empty pad has no [soundId].
class PadConfig {
  const PadConfig({
    this.soundId,
    this.mode = PadMode.oneShot,
    this.volume = 0.8,
    this.semitones = 0,
    this.loopSteps = kStepsPerBar,
    this.synced = false,
    this.muted = false,
  });

  static const PadConfig empty = PadConfig();

  final String? soundId;
  final PadMode mode;
  final double volume;
  final int semitones;

  /// Loop length in 16th notes. Only meaningful when [synced] is true;
  /// a free loop runs at its own natural length.
  final int loopSteps;
  final bool synced;
  final bool muted;

  bool get isEmpty => soundId == null;
  bool get isLoop => mode == PadMode.loop;

  PadConfig copyWith({
    String? soundId,
    bool clearSound = false,
    PadMode? mode,
    double? volume,
    int? semitones,
    int? loopSteps,
    bool? synced,
    bool? muted,
  }) {
    return PadConfig(
      soundId: clearSound ? null : (soundId ?? this.soundId),
      mode: mode ?? this.mode,
      volume: volume ?? this.volume,
      semitones: semitones ?? this.semitones,
      loopSteps: loopSteps ?? this.loopSteps,
      synced: synced ?? this.synced,
      muted: muted ?? this.muted,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundId': soundId,
        'mode': mode.name,
        'volume': volume,
        'semitones': semitones,
        'loopSteps': loopSteps,
        'synced': synced,
        'muted': muted,
      };

  factory PadConfig.fromJson(Map<String, dynamic> json) => PadConfig(
        soundId: json['soundId'] as String?,
        mode: PadMode.values.byName(json['mode'] as String? ?? 'oneShot'),
        volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
        semitones: json['semitones'] as int? ?? 0,
        loopSteps: json['loopSteps'] as int? ?? kStepsPerBar,
        synced: json['synced'] as bool? ?? false,
        muted: json['muted'] as bool? ?? false,
      );
}

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
