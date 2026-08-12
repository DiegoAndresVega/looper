import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'audio_engine.dart';

/// Records the performance: what comes out of the mixer, not what the
/// microphone hears. It can run while the grid is being played, which is the
/// whole difference between this and capturing a sound.
class TakeRecorder {
  TakeRecorder({required AudioEngine engine, required Storage storage})
      : _engine = engine,
        _storage = storage;

  final AudioEngine _engine;
  final Storage _storage;

  StreamSubscription<Uint8List>? _subscription;
  IOSink? _sink;
  File? _file;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  Duration get elapsed {
    final start = _startedAt;
    return start == null ? Duration.zero : DateTime.now().difference(start);
  }

  /// Starts writing the mixer output straight to disk, so a long take never
  /// piles up in memory.
  Future<void> start() async {
    if (isRecording) return;
    if (!await _storage.takes.exists()) {
      await _storage.takes.create(recursive: true);
    }

    final file = File('${_storage.takes.path}/${_takeName()}');
    final sink = file.openWrite();
    _file = file;
    _sink = sink;
    _startedAt = DateTime.now();

    _subscription = _engine.startTakeCapture().listen(
      sink.add,
      onError: (Object error) => debugPrint('Fallo capturando la toma: $error'),
      cancelOnError: false,
    );
  }

  /// Stops the capture and returns the finished file, or null when nothing
  /// was actually written.
  Future<File?> stop() async {
    if (!isRecording) return null;

    _engine.stopTakeCapture();
    await _subscription?.cancel();
    await _sink?.flush();
    await _sink?.close();

    final file = _file;
    _subscription = null;
    _sink = null;
    _file = null;
    _startedAt = null;
    if (file == null) return null;

    // The header written at the start carries placeholder sizes; the real one
    // only exists once the engine knows how much audio there was.
    final header = _engine.takeWavHeader();
    final length = await file.length();
    if (length <= _wavHeaderBytes || header.length != _wavHeaderBytes) {
      await file.delete();
      return null;
    }

    final handle = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      await handle.setPosition(0);
      await handle.writeFrom(header);
    } finally {
      await handle.close();
    }
    return file;
  }

  String _takeName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'toma_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.wav';
  }
}

const int _wavHeaderBytes = 44;
