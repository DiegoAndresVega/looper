import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/audio_engine.dart';
import 'core/constants.dart';
import 'core/palette.dart';
import 'data/session_store.dart';
import 'data/sound_library.dart';
import 'data/storage.dart';
import 'domain/sound.dart';
import 'state/session_controller.dart';
import 'ui/pads/pads_screen.dart';
import 'ui/record/record_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const LooperApp());
}

class LooperApp extends StatelessWidget {
  const LooperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Looper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.ground,
        colorScheme: const ColorScheme.dark(
          surface: Palette.ground,
          primary: Palette.accent,
          secondary: Palette.tone,
        ),
      ),
      home: const Boot(),
    );
  }
}

/// First run does real work: it synthesises the 32 factory sounds so the app
/// ships without a single binary sample and the grid is never empty.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  final AudioEngine _engine = AudioEngine();
  SessionController? _controller;
  Storage? _storage;
  SoundLibrary? _library;
  SessionStore? _store;
  String _status = 'Afinando el instrumento…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final storage = await Storage.init();

      setState(() => _status = 'Generando el kit de fábrica…');
      final library = SoundLibrary(storage);
      await library.load();

      setState(() => _status = 'Cargando sonidos…');
      await _engine.init();

      final store = SessionStore(storage);
      await store.load();
      final session = await store.firstOrCreate(library);

      final controller = SessionController(engine: _engine, library: library);
      await controller.open(session);

      if (!mounted) return;
      setState(() {
        _storage = storage;
        _library = library;
        _store = store;
        _controller = controller;
      });
    } catch (e, stack) {
      debugPrint('Fallo al arrancar: $e\n$stack');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: Palette.ground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Palette.rec, size: 34),
                const SizedBox(height: 14),
                const Text(
                  'El motor de audio no arrancó',
                  style: TextStyle(
                      color: Palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.inkDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        backgroundColor: Palette.ground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Palette.accent),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: const TextStyle(
                    color: Palette.inkDim, fontSize: 12, letterSpacing: 0.4),
              ),
            ],
          ),
        ),
      );
    }

    return PadsScreen(
      controller: controller,
      onOpenRecorder: _openRecorder,
      onOpenLibrary: () {},
      onOpenSessions: () {},
      onPadLongPress: (_) {},
    );
  }

  /// Hands the audio session over to the microphone and takes it back when the
  /// recording screen closes. A saved sound goes straight onto a free pad, so
  /// it can be played the second it exists.
  Future<void> _openRecorder() async {
    final controller = _controller;
    final library = _library;
    final storage = _storage;
    if (controller == null || library == null || storage == null) return;

    await controller.stopAllLoops();
    await _engine.release();

    if (!mounted) return;
    final sound = await Navigator.of(context).push<Sound>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          engine: _engine,
          library: library,
          storage: storage,
        ),
      ),
    );

    await _engine.init();
    await controller.reloadSounds();
    if (!mounted) return;
    if (sound == null) {
      setState(() {});
      return;
    }

    final target = await controller.placeSound(sound);
    final session = controller.session;
    if (session != null) await _store?.save(session);
    if (!mounted) return;

    setState(() {});
    _announce(
      target == null
          ? '${sound.name} está en la biblioteca: no queda ningún pad libre'
          : '${sound.name} en el pad ${kBankIds[target.bank]} · '
              '${(target.slot + 1).toString().padLeft(2, '0')}',
    );
  }

  void _announce(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Palette.panelHigh,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }
}
