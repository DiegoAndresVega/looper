import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';

/// How much room is left on the device.
///
/// Recording without stopping fills a phone, and the difference between a
/// nuisance and a lost session is being told before the write fails rather
/// than after. Flutter ships no way to ask, so the app asks the platform
/// itself through a channel of its own — a few lines of Kotlin and Swift,
/// which is cheaper than a package that would have to survive the versions
/// this project pins by force.
class DiskSpace {
  DiskSpace({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('looper/storage');

  final MethodChannel _channel;

  /// Free bytes, or null when the platform does not answer. Null is a real
  /// answer here and it means «do not warn»: a warning invented out of a
  /// failed call is a warning the player learns to ignore.
  Future<int?> freeBytes() async {
    try {
      final value = await _channel.invokeMethod<Object?>('freeBytes');
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    } on Object catch (e) {
      debugPrint('No se pudo leer el espacio libre: $e');
      return null;
    }
  }
}

/// Whether what is left is little enough to say something about it.
bool isSpaceLowFor(int? freeBytes) =>
    freeBytes != null && freeBytes < kLowSpaceBytes;

/// The number as a person reads it. Megabytes up to a gigabyte, then one
/// decimal — «0,9 GB» says less than «900 MB» about whether a take fits.
String? freeSpaceLabelFor(int? freeBytes) {
  if (freeBytes == null) return null;
  const mega = 1024 * 1024;
  if (freeBytes < 1024 * mega) return '${(freeBytes / mega).round()} MB';
  final gigas = freeBytes / (1024 * mega);
  return '${gigas.toStringAsFixed(1).replaceAll('.', ',')} GB';
}
