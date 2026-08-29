import '../core/constants.dart';

/// Which pads have just made a sound, and for how long that still shows.
///
/// The grid could already draw a pad mid-hit — [PadVisualState.firing] paints
/// a full wash and brightens the label — and nothing ever produced it. A pad
/// played by the sequencer, by a controller or by a finger looked exactly like
/// a pad doing nothing, which is the one thing a grid of pads has to say.
///
/// Time is passed in rather than read, and there is no timer in here at all:
/// the grid already repaints thirty times a second while anything is moving,
/// so a flash only has to know when it is over, not announce it.
class PadFlashes {
  PadFlashes({this.life = kPadFlashDuration, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// How long a hit stays visible. Long enough to catch at a glance, short
  /// enough that sixteenths at 180 BPM still read as separate hits.
  final Duration life;

  final DateTime Function() _now;

  final Map<String, DateTime> _until = {};

  /// A pad just sounded. Re-firing one that is still lit restarts it rather
  /// than stacking, so a roll flickers instead of staying on.
  void fire(String key) => _until[key] = _now().add(life);

  bool isLit(String key) {
    final until = _until[key];
    return until != null && until.isAfter(_now());
  }

  /// Whether anything is still lit. The screen asks this to know whether it
  /// has to keep repainting; asking sweeps the ones that have gone out, which
  /// is the only cleaning this needs.
  bool get any {
    final now = _now();
    _until.removeWhere((_, until) => !until.isAfter(now));
    return _until.isNotEmpty;
  }

  void clear() => _until.clear();
}
