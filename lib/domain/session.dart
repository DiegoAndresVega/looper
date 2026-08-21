import '../core/constants.dart';
import 'pad_config.dart';
import 'pattern.dart';

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
    this.activePattern = 0,
    this.chainLength = 1,
    this.swing = kSwingDefault,
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

  /// How much the off-beat sixteenths lag. It belongs to the session because
  /// it is part of how the pattern is meant to be felt, like the tempo.
  final double swing;

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
      swing: swing,
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
    double? swing,
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
      swing: swing ?? this.swing,
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
        'swing': swing,
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
        // A session written before swing existed was played straight.
        swing: (json['swing'] as num?)?.toDouble() ?? kSwingDefault,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
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
