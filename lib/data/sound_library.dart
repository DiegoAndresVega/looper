import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/voices.dart';
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

  Future<void> update(Sound sound) async {
    _byId[sound.id] = sound;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final sound = _byId.remove(id);
    if (sound == null) return;
    final file = _storage.soundFile(sound.fileName);
    if (await file.exists()) {
      await file.delete();
    }
    _sizeBytes = await _storage.librarySizeBytes();
    await _persist();
    notifyListeners();
  }

  String pathFor(Sound sound) => _storage.soundFile(sound.fileName).path;

  Future<void> _persist() async {
    final data = _byId.values.map((s) => s.toJson()).toList();
    await _storage.libraryIndex.writeAsString(jsonEncode(data));
  }
}
