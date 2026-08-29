import 'dart:math' as math;
import 'dart:typed_data';

/// Reads the tempo out of a loop.
///
/// Two steps, and neither of them needs a spectrum: measure how the loudness
/// moves — a hit is a jump in energy — and then ask how far apart those jumps
/// are, by correlating that curve with itself. The lag that agrees with itself
/// best is the beat.
///
/// It answers null rather than guessing when the sound is too short to hold
/// two beats, or when nothing in it repeats. A wrong tempo is worse than no
/// tempo: everything downstream would be stretched to it.
double? detectBpm(
  Float32List samples,
  int sampleRate, {
  double minBpm = 70,
  double maxBpm = 180,
}) {
  if (samples.isEmpty || sampleRate <= 0) return null;

  // 10 ms per bucket: fine enough to place a hit, coarse enough that a
  // four-second loop is four hundred numbers instead of a hundred thousand.
  final hop = (sampleRate * 0.01).round();
  if (hop <= 0) return null;
  final buckets = samples.length ~/ hop;
  if (buckets < 32) return null;

  final energy = Float64List(buckets);
  for (var b = 0; b < buckets; b++) {
    var sum = 0.0;
    final start = b * hop;
    for (var i = start; i < start + hop; i++) {
      sum += samples[i] * samples[i];
    }
    energy[b] = math.sqrt(sum / hop);
  }

  // Only the rises count. A note dying away is not an event, and counting it
  // would put a second peak halfway between every pair of real ones.
  final onset = Float64List(buckets);
  var mean = 0.0;
  for (var b = 1; b < buckets; b++) {
    final rise = energy[b] - energy[b - 1];
    onset[b] = rise > 0 ? rise : 0;
    mean += onset[b];
  }
  mean /= buckets;
  if (mean <= 0) return null;
  for (var b = 0; b < buckets; b++) {
    onset[b] -= mean;
  }

  final minLag = (60 / maxBpm / 0.01).round();
  final maxLag = math.min((60 / minBpm / 0.01).round(), buckets ~/ 2);
  if (maxLag <= minLag) return null;

  var bestLag = 0;
  var bestScore = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    var score = 0.0;
    for (var b = 0; b + lag < buckets; b++) {
      score += onset[b] * onset[b + lag];
    }
    // Longer lags get fewer terms to add up, so the score is per-term or the
    // slowest tempo in the range always wins.
    score /= buckets - lag;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }

  if (bestLag == 0 || bestScore <= 0) return null;
  return 60 / (bestLag * 0.01);
}
