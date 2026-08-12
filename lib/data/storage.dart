import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Everything lives on the device. No accounts, no server, no sync.
class Storage {
  Storage._(this.root);

  final Directory root;

  static Storage? _instance;
  static Storage get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Storage.init() must run before use');
    }
    return i;
  }

  static Future<Storage> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/looper');
    final storage = Storage._(root);
    await storage._ensureLayout();
    _instance = storage;
    return storage;
  }

  Directory get sounds => Directory('${root.path}/sounds');

  /// Where a rendered performance lands, ready to be shared out.
  Directory get mixdowns => Directory('${root.path}/mixdowns');
  File get libraryIndex => File('${root.path}/library.json');
  File get sessionsIndex => File('${root.path}/sessions.json');

  Future<void> _ensureLayout() async {
    for (final dir in [root, sounds, mixdowns]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  File soundFile(String fileName) => File('${sounds.path}/$fileName');

  /// Where the microphone writes while recording, before the take is trimmed,
  /// normalised and saved into the library. Overwritten on every take.
  File get captureScratch => File('${root.path}/capture.wav');

  /// Total bytes taken by recorded, imported and factory sounds.
  Future<int> librarySizeBytes() async {
    var total = 0;
    await for (final entity in sounds.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
