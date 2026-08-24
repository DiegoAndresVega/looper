import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/audio_engine.dart';
import 'core/constants.dart';
import 'core/palette.dart';
import 'core/type.dart';
import 'data/session_store.dart';
import 'data/sound_library.dart';
import 'data/storage.dart';
import 'domain/session.dart';
import 'domain/sound.dart';
import 'state/session_controller.dart';
import 'ui/library/library_screen.dart';
import 'data/midi_service.dart';
import 'data/save_point_store.dart';
import 'ui/midi/midi_screen.dart';
import 'ui/pads/pads_screen.dart';
import 'ui/sampler/sampler_screen.dart';
import 'ui/sessions/sessions_screen.dart';

/// The two brand faces are the only third-party material in the app — the kit
/// is synthesised and the code is ours — and the SIL Open Font License asks to
/// be shipped alongside them. This puts both licences on the app's own licence
/// page, next to the ones Flutter collects by itself.
void _registerFontLicenses() {
  const licences = {
    'Archivo': 'assets/fonts/OFL-Archivo.txt',
    'Martian Mono': 'assets/fonts/OFL-MartianMono.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in licences.entries) {
      yield LicenseEntryWithLineBreaks(
        [entry.key],
        await rootBundle.loadString(entry.value),
      );
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // The system bars join the room instead of framing it: the aubergine runs
  // edge to edge, so the phone stops looking like a phone holding an app.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Palette.ground,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
        canvasColor: Palette.ground,
        dividerColor: Palette.line,
        fontFamily: Brand.faceDisplay,
        colorScheme: const ColorScheme.dark(
          surface: Palette.ground,
          onSurface: Palette.ink,
          surfaceContainerHighest: Palette.panelHigh,
          primary: Palette.accent,
          onPrimary: Palette.onAccent,
          secondary: Palette.tone,
          onSecondary: Palette.onAccent,
          error: Palette.rec,
          onError: Palette.onAccent,
          outline: Palette.line,
          outlineVariant: Palette.lineLive,
        ),
        // Only the roles Material draws on its own — dialogs, the licence
        // page, text fields. Everything the instrument draws itself asks
        // Brand directly.
        textTheme: TextTheme(
          displayLarge: Brand.hero(32),
          titleLarge: Brand.title(19),
          titleMedium: Brand.title(15),
          bodyLarge: Brand.body(15, color: Palette.ink),
          bodyMedium: Brand.body(13),
          bodySmall: Brand.body(11),
          labelLarge: Brand.label(12, color: Palette.ink),
          labelMedium: Brand.label(10, color: Palette.inkDim),
          labelSmall: Brand.label(8),
        ),
        iconTheme: const IconThemeData(color: Palette.inkDim),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Palette.panelHigh,
          contentTextStyle: Brand.body(12.5, color: Palette.ink),
          behavior: SnackBarBehavior.floating,
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
  SavePointStore? _savePoints;
  final MidiService _midi = MidiService();
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
      final savePoints = SavePointStore(storage);
      await savePoints.load();
      final session = await store.firstOrCreate(library);

      final controller = SessionController(
        engine: _engine,
        library: library,
        store: store,
      );
      await controller.open(session);
      // The controller mapping belongs to the desk, not to the piece: it is
      // read once here and outlives every session opened afterwards.
      await controller.midiLearn.load();

      if (!mounted) return;
      setState(() {
        _storage = storage;
        _savePoints = savePoints;
        _library = library;
        _store = store;
        _controller = controller;
        // The controller listens to whatever device the service is attached
        // to; picking one is a screen away, and none is a perfectly normal
        // state to stay in for ever.
        controller.listenToMidi(_midi.events);
        _midi.start();
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
                Text(
                  'El motor de audio no arrancó',
                  style: Brand.title(17),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Brand.body(12, color: Palette.inkFaint),
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
              const SizedBox(height: 18),
              Text(
                _status.toUpperCase(),
                style: Brand.label(8.5, color: Palette.inkDim),
              ),
            ],
          ),
        ),
      );
    }

    return PadsScreen(
      controller: controller,
      onOpenSampler: _openSampler,
      onOpenMidi: _openMidi,
      isMidiConnected: _midi.isConnected,
      onOpenLibrary: _openLibrary,
      onOpenSessions: _openSessions,
    );
  }

  Future<void> _openMidi() async {
    final controller = _controller;
    if (controller == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MidiScreen(midi: _midi, learn: controller.midiLearn),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Hands the audio session over to the microphone and takes it back when the
  /// recording screen closes. A saved sound goes straight onto a free pad, so
  /// it can be played the second it exists.
  Future<void> _openSampler() async {
    final controller = _controller;
    final library = _library;
    final storage = _storage;
    if (controller == null || library == null || storage == null) return;

    await controller.stopAllLoops();
    // The microphone needs the engine to itself, so the tap has to let go
    // first — and what it held belongs to before the break.
    await controller.stopListeningToMaster();
    await _engine.release();

    if (!mounted) return;
    final sound = await Navigator.of(context).push<Sound>(
      MaterialPageRoute(
        builder: (_) => SamplerScreen(
          engine: _engine,
          library: library,
          storage: storage,
        ),
      ),
    );

    await _engine.init();
    await controller.reloadSounds();
    controller.listenToMaster();
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

  /// The library screen. Deleting a sound also empties the pads holding it,
  /// so the grid never points at a file that is gone.
  Future<void> _openLibrary() async {
    final controller = _controller;
    final library = _library;
    final storage = _storage;
    if (controller == null || library == null || storage == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          library: library,
          storage: storage,
          onPreview: controller.preview,
          onDelete: (sound) async {
            await controller.clearPadsUsing(sound.id);
            await library.remove(sound.id);
          },
          slicesFor: controller.previewChop,
          onChop: controller.chop,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// The session list. The open session is written to disk before leaving, so
  /// switching away never loses the last few edits.
  Future<void> _openSessions() async {
    final controller = _controller;
    final store = _store;
    final library = _library;
    final savePoints = _savePoints;
    final current = controller?.session;
    if (controller == null ||
        store == null ||
        library == null ||
        savePoints == null ||
        current == null) {
      return;
    }

    await controller.flush();
    if (!mounted) return;

    final chosen = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => SessionsScreen(
          store: store,
          library: library,
          currentId: current.id,
          savePoints: savePoints,
          currentSession: current,
          onRestore: controller.restore,
        ),
      ),
    );
    if (chosen != null && chosen.id != current.id) {
      await controller.open(chosen);
    }
    if (mounted) setState(() {});
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
