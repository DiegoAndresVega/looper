import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'mixer_tap.dart';
import 'wav_encoder.dart';

/// Records the performance: what comes out of the mixer, not what the
/// microphone hears. It can run while the grid is being played, which is the
/// whole difference between this and capturing a sound.
class MixdownRecorder {
  MixdownRecorder({required MixerTap tap, required Storage storage})
      : _tap = tap,
        _storage = storage;

  /// The shared tap, not the engine: the mixer hands out one stream, and the
  /// skip-back buffer is already holding it.
  final MixerTap _tap;
  final Storage _storage;

  IOSink? _sink;
  File? _file;
  DateTime? _startedAt;
  int _dataBytes = 0;
  void Function(Uint8List)? _listener;

  bool get isRecording => _startedAt != null;

  Duration get elapsed {
    final start = _startedAt;
    return start == null ? Duration.zero : DateTime.now().difference(start);
  }

  /// Starts writing the mixer output straight to disk, so a long take never
  /// piles up in memory.
  /// [name] renames the file. Stems use it so that four files landing in the
  /// same folder say which family each one is.
  Future<void> start({String? name}) async {
    if (isRecording) return;
    if (!await _storage.mixdowns.exists()) {
      await _storage.mixdowns.create(recursive: true);
    }

    _tap.open();

    final file =
        File('${_storage.mixdowns.path}/${name ?? _mixdownName()}');
    final sink = file.openWrite();
    _file = file;
    _sink = sink;
    _startedAt = DateTime.now();
    _dataBytes = 0;

    // A blank header goes down first and the real one is stamped over it on
    // stop. It cannot come from the engine any more: that header describes the
    // whole stream, and the tap may have been open long before this take.
    sink.add(Uint8List(kWavHeaderBytes));

    void onPcm(Uint8List pcm) {
      _dataBytes += pcm.length;
      sink.add(pcm);
    }

    _listener = onPcm;
    _tap.addSink(onPcm);
  }

  /// Stops the capture and returns the finished file, or null when nothing
  /// was actually written.
  Future<File?> stop() async {
    if (!isRecording) return null;

    final listener = _listener;
    if (listener != null) _tap.removeSink(listener);
    await _sink?.flush();
    await _sink?.close();

    final file = _file;
    final dataBytes = _dataBytes;
    _listener = null;
    _sink = null;
    _file = null;
    _startedAt = null;
    _dataBytes = 0;
    if (file == null) return null;

    if (dataBytes <= 0) {
      await file.delete();
      return null;
    }

    // The size is this take's, not the stream's: the tap keeps running for
    // everyone else and its own header would claim far more audio than is
    // actually in this file.
    final header = wavHeader(
      dataBytes: dataBytes,
      sampleRate: _tap.format.sampleRate,
      channels: _tap.format.channels,
    );

    final handle = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      await handle.setPosition(0);
      await handle.writeFrom(header);
    } finally {
      await handle.close();
    }
    return file;
  }

  String _mixdownName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'mezcla_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.wav';
  }
}

