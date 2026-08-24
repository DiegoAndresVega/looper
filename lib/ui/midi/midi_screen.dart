import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../data/midi_service.dart';
import '../../domain/midi_map.dart';
import '../../state/midi_learn.dart';

/// Controllers, and which one the grid is listening to.
///
/// There is still no mapping to set up here: notes from [kMidiPadBaseNote]
/// upwards play the sixteen pads of the bank on screen, and knobs are married
/// on the instrument itself by holding one down. What this screen adds is the
/// list of what got married — somewhere to check, and somewhere to undo it
/// without hunting for the knob that learned it.
class MidiScreen extends StatefulWidget {
  const MidiScreen({super.key, required this.midi, required this.learn});

  final MidiService midi;
  final MidiLearn learn;

  @override
  State<MidiScreen> createState() => _MidiScreenState();
}

class _MidiScreenState extends State<MidiScreen> {
  MidiService get m => widget.midi;
  MidiLearn get learn => widget.learn;

  @override
  void initState() {
    super.initState();
    m.addListener(_onChange);
    learn.addListener(_onChange);
    m.refresh();
  }

  @override
  void dispose() {
    m.removeListener(_onChange);
    learn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ground,
      appBar: AppBar(
        backgroundColor: Palette.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Palette.inkDim),
        title: Text('Controlador', style: Brand.title(18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            _explainer(),
            const SizedBox(height: 16),
            if (m.error != null) ...[_errorPanel(m.error!), const SizedBox(height: 12)],
            ...m.devices.map(_deviceRow),
            if (m.devices.isEmpty) _empty(),
            const SizedBox(height: 16),
            _scanButton(),
            const SizedBox(height: 26),
            _mappings(),
          ],
        ),
      ),
    );
  }

  Widget _explainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIN NADA QUE CONFIGURAR', style: Brand.label(8.5, weight: 700)),
          const SizedBox(height: 8),
          Text(
            'Las notas a partir del do grave tocan los dieciséis pads del banco '
            'que tengas delante, en orden. Es la distribución que ya trae '
            'cualquier controlador de pads.',
            style: Brand.body(12.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Con el secuenciador escribiendo, lo que toques entra en el patrón. '
            'Con el teclado encendido, cada nota es un grado de la escala.',
            style: Brand.body(12.5, color: Palette.inkFaint),
          ),
          const SizedBox(height: 12),
          Text('LOS MANDOS SE APRENDEN SOLOS',
              style: Brand.label(8.5, weight: 700)),
          const SizedBox(height: 8),
          Text(
            'Mantén pulsado un mando de la franja, mueve el mando físico, y '
            'quedan casados. El número del control queda escrito dentro del '
            'dial. Se aprenden en el sitio, no aquí.',
            style: Brand.body(12.5),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.rec),
      ),
      child: Text(message, style: Brand.body(12, color: Palette.rec)),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Text(
        'No hay ningún controlador a la vista. Enchufa uno por USB, o busca '
        'por Bluetooth aquí abajo.',
        textAlign: TextAlign.center,
        style: Brand.body(12.5, color: Palette.inkFaint),
      ),
    );
  }

  Widget _deviceRow(MidiDevice device) {
    final isThisOne = m.connected?.id == device.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => isThisOne ? m.disconnect() : m.connect(device),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Palette.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isThisOne ? Palette.accent : Palette.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isThisOne ? Palette.accent : Palette.line,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: Brand.strong(14)),
                    const SizedBox(height: 3),
                    Text(device.type.name.toUpperCase(),
                        style: Brand.label(7.5, width: 75)),
                  ],
                ),
              ),
              Text(
                isThisOne ? 'CONECTADO' : 'CONECTAR',
                style: Brand.label(
                  8,
                  weight: 700,
                  color: isThisOne ? Palette.accent : Palette.inkDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanButton() {
    return GestureDetector(
      onTap: m.isScanning ? null : m.scanBluetooth,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          m.isScanning ? 'BUSCANDO…' : 'BUSCAR POR BLUETOOTH',
          style: Brand.label(
            9.5,
            weight: 700,
            color: m.isScanning ? Palette.inkFaint : Palette.ink,
          ),
        ),
      ),
    );
  }

  /// What the desk moves today. It is a list to *undo* from, not one to set up
  /// from: nothing here can create a mapping, only forget one.
  Widget _mappings() {
    final bindings = learn.map.bindings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('MANDOS APRENDIDOS · ${bindings.length}',
                  style: Brand.label(8.5, weight: 700)),
            ),
            if (bindings.isNotEmpty)
              GestureDetector(
                onTap: learn.forgetEverything,
                child: Text('OLVIDAR TODO',
                    style: Brand.label(8.5, weight: 700, color: Palette.rec)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (bindings.isEmpty)
          Text(
            'Ninguno todavía. Mantén pulsado cualquier mando de la franja para '
            'enseñarle uno.',
            style: Brand.body(12.5, color: Palette.inkFaint),
          ),
        ...bindings.map(_mappingRow),
      ],
    );
  }

  Widget _mappingRow(MidiBinding binding) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text('CC${binding.controller}',
                  style: Brand.readout(12, weight: 700)),
            ),
            Expanded(
              child: Text(binding.target.label, style: Brand.strong(13)),
            ),
            GestureDetector(
              onTap: () => learn.forget(binding.target),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('OLVIDAR',
                    style:
                        Brand.label(8, weight: 700, color: Palette.inkDim)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
