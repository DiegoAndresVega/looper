import '../core/palette.dart';
import 'fx_curves.dart';

/// Where one family's bus is set: its own filter, its own grit, and how much
/// of it is sent to the shared reverb.
///
/// Immutable on purpose. A knob move builds a new one, so the rack can hand
/// the same instance to the UI and to the engine without either of them being
/// able to change it behind the other's back.
class BusSettings {
  const BusSettings({
    this.cutoff = 1,
    this.resonance = 0,
    this.drive = 0,
    this.send = 0,
  });

  /// Nothing touched: the bus passes its family through untouched and sends
  /// nothing to the reverb. Every bus opens here.
  static const BusSettings flat = BusSettings();

  /// 1.0 is fully open, so a resting knob colours nothing.
  final double cutoff;
  final double resonance;
  final double drive;

  /// Knob position of the send, not the gain it lands on — the taper lives in
  /// [sendGain], next to the other curves.
  final double send;

  bool get isFilterResting =>
      cutoff >= 1 - kFxEpsilon && resonance <= kFxEpsilon;
  bool get isDriveResting => drive <= kFxEpsilon;
  bool get isSendResting => send <= kFxEpsilon;

  /// Whether this bus is doing anything at all. A flat bus is still in the
  /// signal path — bypassing is every wet at zero, never an unplugged bus —
  /// but the UI uses this to decide what to light up.
  bool get isFlat => isFilterResting && isDriveResting && isSendResting;

  /// The gain the send twin is played at, already tapered.
  double get sendVolume => sendGain(send);

  /// Clamps on the way in: a knob dragged past its end never reaches a filter
  /// out of range, which is the one thing the plugin does not forgive.
  BusSettings copyWith({
    double? cutoff,
    double? resonance,
    double? drive,
    double? send,
  }) {
    return BusSettings(
      cutoff: (cutoff ?? this.cutoff).clamp(0.0, 1.0),
      resonance: (resonance ?? this.resonance).clamp(0.0, 1.0),
      drive: (drive ?? this.drive).clamp(0.0, 1.0),
      send: (send ?? this.send).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BusSettings &&
      other.cutoff == cutoff &&
      other.resonance == resonance &&
      other.drive == drive &&
      other.send == send;

  @override
  int get hashCode => Object.hash(cutoff, resonance, drive, send);
}

/// The four family buses, as knob positions. No audio here on purpose: this
/// is the half that can be checked without a device, the same split
/// [fx_curves] makes for the master.
///
/// The families are already buses in everything but wiring — a sound belongs
/// to exactly one of them and wears its colour all over the app — so the rack
/// is keyed by [SoundFamily] and can never grow a fifth entry by accident.
///
/// Like the master knobs, these are performance state: they do not travel
/// with the session and they reset when the app restarts. Where a filter was
/// left is not part of a piece.
class BusRack {
  Map<SoundFamily, BusSettings> _settings = {
    for (final family in SoundFamily.values) family: BusSettings.flat,
  };

  BusSettings settingsFor(SoundFamily family) => _settings[family]!;

  /// True while every bus is still untouched — used to decide whether the
  /// send twins are worth firing at all.
  bool get isFlat => _settings.values.every((s) => s.isFlat);

  /// Replaces one family's settings. The map is rebuilt rather than written
  /// into, so anyone holding the old one still sees what they were handed.
  void update(SoundFamily family, BusSettings settings) {
    _settings = {..._settings, family: settings};
  }

  void setCutoff(SoundFamily family, double value) =>
      update(family, settingsFor(family).copyWith(cutoff: value));

  void setResonance(SoundFamily family, double value) =>
      update(family, settingsFor(family).copyWith(resonance: value));

  void setDrive(SoundFamily family, double value) =>
      update(family, settingsFor(family).copyWith(drive: value));

  void setSend(SoundFamily family, double value) =>
      update(family, settingsFor(family).copyWith(send: value));

  void reset() {
    _settings = {
      for (final family in SoundFamily.values) family: BusSettings.flat,
    };
  }
}
