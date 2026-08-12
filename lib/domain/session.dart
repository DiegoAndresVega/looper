import '../core/constants.dart';
import 'pad_config.dart';

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
  });

  final String id;
  final String name;
  final int bpm;
  final List<Bank> banks;
  final DateTime createdAt;
  final DateTime updatedAt;

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

  Session copyWith({
    String? name,
    int? bpm,
    List<Bank>? banks,
    DateTime? updatedAt,
  }) {
    return Session(
      id: id,
      name: name ?? this.name,
      bpm: bpm ?? this.bpm,
      banks: banks ?? this.banks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bpm': bpm,
        'banks': banks.map((b) => b.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        name: json['name'] as String,
        bpm: json['bpm'] as int,
        banks: (json['banks'] as List<dynamic>)
            .map((b) => Bank.fromJson(b as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
