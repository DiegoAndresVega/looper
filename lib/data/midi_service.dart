import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/midi.dart';

/// The cable end of MIDI: finding controllers, staying attached to one, and
/// turning what it sends into the events the instrument understands.
///
/// Everything about *meaning* lives in `domain/midi.dart` and is tested there.
/// This class only deals with the parts that need a device in your hand.
class MidiService extends ChangeNotifier {
  MidiService({MidiCommand? command}) : _command = command ?? MidiCommand();

  final MidiCommand _command;

  StreamSubscription<MidiDataReceivedEvent>? _dataSubscription;
  StreamSubscription<MidiSetupChange>? _setupSubscription;

  final _events = StreamController<MidiEvent>.broadcast();

  List<MidiDevice> _devices = const [];
  MidiDevice? _connected;
  String? _error;
  bool _scanning = false;

  /// Everything arriving from the controller currently attached.
  Stream<MidiEvent> get events => _events.stream;

  List<MidiDevice> get devices => List.unmodifiable(_devices);
  MidiDevice? get connected => _connected;
  bool get isConnected => _connected != null;
  bool get isScanning => _scanning;
  String? get error => _error;

  /// Starts listening. Data flows the moment a device is connected; the setup
  /// stream keeps the list honest when something is plugged or unplugged.
  Future<void> start() async {
    _dataSubscription ??= _command.onMidiDataReceived?.listen(_onData);
    _setupSubscription ??= _command.onMidiSetupChanged?.listen((_) => refresh());
    await refresh();
  }

  Future<void> refresh() async {
    try {
      _devices = await _command.devices ?? const [];
      // A device can go away while connected — unplugged, or out of range.
      if (_connected != null &&
          !_devices.any((d) => d.id == _connected!.id && d.connected)) {
        _connected = null;
      }
      _error = null;
    } on Object catch (e) {
      _error = 'No se pudo leer la lista de aparatos: $e';
      debugPrint('MIDI: $e');
    }
    notifyListeners();
  }

  /// Looks for Bluetooth controllers. Wired ones are already in the list, so
  /// this is only asked for when someone goes looking.
  Future<void> scanBluetooth() async {
    if (_scanning) return;
    _scanning = true;
    _error = null;
    notifyListeners();

    try {
      // Android 12 and up will not scan without this, and refusing it is a
      // normal answer rather than a failure.
      final granted = await Permission.bluetoothScan.request();
      if (granted.isGranted) {
        await Permission.bluetoothConnect.request();
        await _command.waitUntilBluetoothIsInitialized();
        await _command.startScanningForBluetoothDevices();
      } else {
        _error = 'Sin permiso de Bluetooth no se pueden buscar aparatos.';
      }
    } on Object catch (e) {
      _error = 'No se pudo buscar por Bluetooth: $e';
      debugPrint('MIDI BLE: $e');
    }

    _scanning = false;
    await refresh();
  }

  Future<void> connect(MidiDevice device) async {
    try {
      await _command.connectToDevice(device);
      _connected = device;
      _error = null;
    } on Object catch (e) {
      _error = 'No se pudo conectar con ${device.name}: $e';
      debugPrint('MIDI: $e');
    }
    notifyListeners();
  }

  /// Sends bytes to the connected device. Nothing is queued and nothing is
  /// retried: MIDI is a wire, and a clock pulse that arrives late is worse
  /// than one that never arrives.
  void send(Uint8List data) {
    if (_connected == null) return;
    try {
      _command.sendData(data, deviceId: _connected!.id);
    } on Object catch (e) {
      debugPrint('MIDI: no se pudo enviar: $e');
    }
  }

  void disconnect() {
    final device = _connected;
    if (device == null) return;
    _command.disconnectDevice(device);
    _connected = null;
    notifyListeners();
  }

  void _onData(MidiDataReceivedEvent event) {
    for (final parsed in parseMidi(event.message.data)) {
      _events.add(parsed);
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _setupSubscription?.cancel();
    _events.close();
    super.dispose();
  }
}
