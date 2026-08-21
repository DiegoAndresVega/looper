/// One tap on the mixer output, shared by everything that listens to it.
///
/// The engine hands out a single mixer stream: opening a second one would stop
/// the first. So exporting a session, resampling the master back onto a pad and
/// keeping the last few seconds around cannot each open their own — they all
/// drink from here.
///
/// This file holds the half that needs no engine, which is the half worth
/// testing: the ring that always holds the most recent audio, and the
/// conversion from what the mixer emits (interleaved 16-bit PCM) to the mono
/// float samples the rest of the app works in.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/constants.dart';
import 'audio_engine.dart';
import 'wav_encoder.dart';

/// A fixed window of the most recent bytes.
///
/// It keeps the newest and drops the oldest, which is the whole idea behind
/// skip-back: what you just played is what you might want, and what happened a
/// minute ago is not worth the memory.
class RingBuffer {
  RingBuffer({required this.capacity}) : _store = Uint8List(capacity);

  final int capacity;
  final Uint8List _store;

  int _writeAt = 0;
  int _filled = 0;

  /// How many bytes are held, never more than [capacity].
  int get length => _filled;

  bool get isEmpty => _filled == 0;

  void write(Uint8List chunk) {
    if (chunk.isEmpty || capacity == 0) return;

    // A chunk bigger than the window: only its tail could survive anyway.
    final from = chunk.length > capacity ? chunk.length - capacity : 0;
    for (var i = from; i < chunk.length; i++) {
      _store[_writeAt] = chunk[i];
      _writeAt = (_writeAt + 1) % capacity;
    }
    _filled = (_filled + (chunk.length - from)).clamp(0, capacity);
  }

  /// The window in the order it was written, oldest first. Reading does not
  /// consume: the tap keeps running behind it.
  Uint8List read() {
    if (_filled == 0) return Uint8List(0);
    final out = Uint8List(_filled);
    final start = (_writeAt - _filled + capacity) % capacity;
    for (var i = 0; i < _filled; i++) {
      out[i] = _store[(start + i) % capacity];
    }
    return out;
  }

  void clear() {
    _writeAt = 0;
    _filled = 0;
  }
}

/// What the mixer is actually emitting.
typedef MixerFormat = ({int channels, int sampleRate});

/// Reads channels and rate out of the 44-byte WAV header the engine provides,
/// rather than assuming them: the engine is initialised in stereo while the
/// rest of the app works in mono, and that is exactly the kind of mismatch
/// that plays back at half speed without ever raising an error.
MixerFormat formatFromHeader(Uint8List header) {
  if (header.length < 28) {
    return (channels: kChannels, sampleRate: kSampleRate);
  }
  final data = ByteData.sublistView(header);
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  return (
    channels: channels > 0 ? channels : kChannels,
    sampleRate: rate > 0 ? rate : kSampleRate,
  );
}

/// Interleaved 16-bit PCM to mono float samples.
///
/// Channels are averaged rather than dropped, so a part panned hard to one
/// side does not vanish when the master is folded down. Trailing bytes that do
/// not make up a whole frame are ignored — stream chunks do not arrive aligned
/// to sample boundaries.
Float32List samplesFromPcm16(Uint8List pcm, {required int channels}) {
  final lanes = channels < 1 ? 1 : channels;
  final frameBytes = 2 * lanes;
  final frames = pcm.length ~/ frameBytes;
  if (frames == 0) return Float32List(0);

  final data = ByteData.sublistView(pcm);
  final out = Float32List(frames);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var lane = 0; lane < lanes; lane++) {
      final value = data.getInt16((frame * lanes + lane) * 2, Endian.little);
      // Divided by the negative floor so that -32768 lands exactly on -1 and
      // the positive peak sits a hair under 1, which is what the format is.
      sum += value / 32768.0;
    }
    out[frame] = sum / lanes;
  }
  return out;
}


/// The single listener on the mixer output, and the thing that hands the audio
/// on to everyone who wants it.
///
/// While open it always holds the last [kSkipBackSeconds] of the master —
/// effects included, microphone never — so anything worth keeping can be
/// rescued after the fact instead of having to be armed for in advance.
class MixerTap {
  MixerTap({required this._engine});

  final AudioEngine _engine;

  StreamSubscription<Uint8List>? _subscription;
  RingBuffer? _ring;
  MixerFormat _format = (channels: kChannels, sampleRate: kSampleRate);

  /// Where the raw PCM also goes while it flows: a take being written to disk
  /// registers itself here rather than opening a second stream.
  final List<void Function(Uint8List pcm)> _sinks = [];

  /// The header arrives once, at the head of the first chunk, and is not audio.
  bool _headerSeen = false;

  bool get isOpen => _subscription != null;

  MixerFormat get format => _format;

  /// How much audio is held right now.
  Duration get buffered {
    final ring = _ring;
    if (ring == null) return Duration.zero;
    final frames = ring.length ~/ (2 * _format.channels);
    return Duration(milliseconds: frames * 1000 ~/ _format.sampleRate);
  }

  void open() {
    if (isOpen) return;
    _headerSeen = false;
    // Sized for the worst case rather than asked of the engine, which has no
    // stream yet to describe. The real format arrives with the first chunk;
    // if it turns out to be mono, the ring simply holds more than it promised.
    _ring = RingBuffer(
      capacity: kSkipBackSeconds * kSampleRate * 2 * 2,
    );
    _subscription = _engine.startMixdownCapture().listen(
      _onBytes,
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    if (!isOpen) return;
    _engine.stopMixdownCapture();
    await _subscription?.cancel();
    _subscription = null;
    _ring = null;
    _sinks.clear();
  }

  void addSink(void Function(Uint8List pcm) sink) => _sinks.add(sink);

  void removeSink(void Function(Uint8List pcm) sink) => _sinks.remove(sink);

  void _onBytes(Uint8List chunk) {
    var pcm = chunk;
    if (!_headerSeen) {
      _headerSeen = true;
      // The stream opens with a WAV header carrying placeholder sizes. It is
      // not audio, and letting it into the ring would put a click at the
      // front of every rescue.
      if (chunk.length >= kWavHeaderBytes) {
        _format = formatFromHeader(chunk);
        pcm = Uint8List.sublistView(chunk, kWavHeaderBytes);
      }
    }
    if (pcm.isEmpty) return;

    _ring?.write(pcm);
    for (final sink in _sinks) {
      sink(pcm);
    }
  }

  /// The most recent [window] of the master as a finished WAV, or null when
  /// there is not enough audio to be worth keeping.
  Uint8List? recentWav({Duration? window}) {
    final ring = _ring;
    if (ring == null || ring.isEmpty) return null;

    var pcm = ring.read();
    if (window != null) {
      final wanted = window.inMilliseconds *
          _format.sampleRate *
          _format.channels *
          2 ~/
          1000;
      if (wanted > 0 && pcm.length > wanted) {
        pcm = Uint8List.sublistView(pcm, pcm.length - wanted);
      }
    }

    final samples = samplesFromPcm16(pcm, channels: _format.channels);
    if (samples.length < kMinRecordSamples) return null;
    return encodeWav(samples, sampleRate: _format.sampleRate);
  }

  /// Throws away what is held. Used when the engine is torn down for the
  /// microphone, so the next rescue cannot splice two sessions together.
  void clearBuffer() => _ring?.clear();
}
