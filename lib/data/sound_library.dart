import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/voices.dart';
import '../audio/chopper.dart';
import '../audio/wav_decoder.dart';
import '../audio/wav_encoder.dart';
import '../core/constants.dart';
import '../domain/sound.dart';
import 'factory_kit.dart';
import 'storage.dart';

/// Rendered bytes for one factory voice, produced off the UI isolate.
class _RenderedVoice {
  const _RenderedVoice(this.voiceId, this.bytes, this.durationMs);

  final String voiceId;
  final Uint8List bytes;
  final int durationMs;
}

/// Runs in a background isolate: synthesises every factory sound to WAV.
List<_RenderedVoice> _renderFactoryVoices(List<String> voiceIds) {
  final out = <_RenderedVoice>[];
  for (final id in voiceIds) {
    final renderer = kVoices[id];
    if (renderer == null) continue;
    final samples = renderer(kSampleRate);
    out.add(_RenderedVoice(
      id,
      encodeWav(samples, sampleRate: kSampleRate),
      (samples.length / kSampleRate * 1000).round(),
    ));
  }
  return out;
}

/// The library: factory kit, your recordings and imported files. Immutable
/// snapshots — every mutation returns through [sounds] as a fresh list.
class SoundLibrary extends ChangeNotifier {
  SoundLibrary(this._storage);

  final Storage _storage;
  final Map<String, Sound> _byId = {};
  /// Keyed by file name, not by sound id: a chop is many sounds over one
  /// file, and the shape being drawn is the file's.
  final Map<String, Float32List> _peaks = {};
  int _sizeBytes = 0;

  List<Sound> get sounds => List.unmodifiable(_byId.values);
  int get sizeBytes => _sizeBytes;
  int get count => _byId.length;

  Sound? byId(String? id) => id == null ? null : _byId[id];

  List<Sound> byOrigin(SoundOrigin origin) =>
      _byId.values.where((s) => s.origin == origin).toList();

  /// Loads the index, generating the factory kit the first time the app runs.
  Future<void> load() async {
    final index = _storage.libraryIndex;
    if (await index.exists()) {
      final raw = jsonDecode(await index.readAsString()) as List<dynamic>;
      for (final entry in raw) {
        final sound = Sound.fromJson(entry as Map<String, dynamic>);
        _byId[sound.id] = sound;
      }
    }

    final missing = kAllFactoryPads
        .where((pad) => !_byId.containsKey(pad.soundId))
        .toList();
    if (missing.isNotEmpty) {
      await _generateFactoryKit(missing);
    }

    _sizeBytes = await _storage.librarySizeBytes();
    notifyListeners();
  }

  Future<void> _generateFactoryKit(List<FactoryPad> pads) async {
    final rendered = await compute(
      _renderFactoryVoices,
      pads.map((p) => p.voiceId).toList(),
    );
    final byVoice = {for (final r in rendered) r.voiceId: r};

    for (final pad in pads) {
      final result = byVoice[pad.voiceId];
      if (result == null) continue;
      final fileName = '${pad.soundId}.wav';
      await _storage.soundFile(fileName).writeAsBytes(result.bytes);
      _byId[pad.soundId] = Sound(
        id: pad.soundId,
        name: pad.name,
        family: pad.family,
        fileName: fileName,
        origin: SoundOrigin.factory_,
        durationMs: result.durationMs,
        sizeBytes: result.bytes.length,
      );
    }
    await _persist();
  }

  /// Registers a freshly recorded or imported file already sitting in storage.
  Future<Sound> add(Sound sound) async {
    _byId[sound.id] = sound;
    _sizeBytes = await _storage.librarySizeBytes();
    await _persist();
    notifyListeners();
    return sound;
  }

  /// Registers several at once. A chop adds sixteen sounds, and going through
  /// [add] for each would rewrite the index and re-measure the folder sixteen
  /// times over.
  Future<void> addAll(Iterable<Sound> sounds) async {
    for (final sound in sounds) {
      _byId[sound.id] = sound;
    }
    _sizeBytes = await _storage.librarySizeBytes();
    await _persist();
    notifyListeners();
  }

  /// A one-off envelope at whatever resolution the caller needs, uncached.
  ///
  /// The drawing envelope is 96 buckets, which is plenty for a waveform and
  /// far too coarse to find hits in: on a sixty-second import each bucket
  /// covers half a second. Onset detection asks for its own.
  Future<Float32List> detailedPeaksFor(Sound sound, int buckets) async {
    final file = _storage.soundFile(sound.fileName);
    if (!await file.exists()) return Float32List(buckets);
    try {
      final decoded = decodeWav(await file.readAsBytes());
      return peakEnvelope(decoded.samples, buckets);
    } on WavFormatException catch (e) {
      debugPrint('No se pudo analizar ${sound.name}: $e');
      return Float32List(buckets);
    }
  }

  Future<void> update(Sound sound) async {
    _byId[sound.id] = sound;
    await _persist();
    notifyListeners();
  }

  /// Forgets a sound, and deletes its file only when nothing else points at
  /// it. Chops are several sounds sharing one file, so deleting one of them
  /// used to pull the audio out from under its siblings.
  Future<void> remove(String id) async {
    final sound = _byId.remove(id);
    if (sound == null) return;
    final file = _storage.soundFile(sound.fileName);
    if (isFileOrphaned(sound.fileName, _byId.values)) {
      _peaks.remove(sound.fileName);
      if (await file.exists()) await file.delete();
    }
    _sizeBytes = await _storage.librarySizeBytes();
    await _persist();
    notifyListeners();
  }

  String pathFor(Sound sound) => _storage.soundFile(sound.fileName).path;

  /// The shape of a sound, for drawing. Read from disk once and kept, because
  /// the editor asks for the same sound on every frame of a drag.
  Future<Float32List> peaksFor(Sound sound) async {
    final cached = _peaks[sound.fileName];
    if (cached != null) return cached;

    final file = _storage.soundFile(sound.fileName);
    if (!await file.exists()) return Float32List(kWaveformBuckets);
    try {
      final decoded = decodeWav(await file.readAsBytes());
      final peaks = peakEnvelope(decoded.samples, kWaveformBuckets);
      _peaks[sound.fileName] = peaks;
      return peaks;
    } on WavFormatException catch (e) {
      debugPrint('No se pudo dibujar ${sound.name}: $e');
      return Float32List(kWaveformBuckets);
    }
  }

  Future<void> _persist() async {
    final data = _byId.values.map((s) => s.toJson()).toList();
    await _storage.libraryIndex.writeAsString(jsonEncode(data));
  }
}
