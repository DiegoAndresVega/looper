import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../data/save_point_store.dart';
import '../../data/session_store.dart';
import '../../data/sound_library.dart';
import '../../domain/save_point.dart';
import '../../domain/session.dart';

/// The list of saved sessions. Tapping one opens it; a long press is where
/// renaming, duplicating and deleting live, so the list stays a list.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    super.key,
    required this.store,
    required this.library,
    required this.currentId,
    required this.savePoints,
    required this.onRestore,
    required this.currentSession,
  });

  final SessionStore store;
  final SoundLibrary library;
  final String currentId;

  /// Named snapshots for every session, and the one thing only the
  /// instrument can do with them: put one back.
  final SavePointStore savePoints;
  final Future<void> Function(SavePoint point) onRestore;

  /// The session as it stands right now, which is what a new point captures.
  final Session currentSession;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  @override
  Widget build(BuildContext context) {
    final sessions = widget.store.sessions;

    return Scaffold(
      backgroundColor: Palette.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) => _row(sessions[i]),
                ),
              ),
              _newButton(),
              const SizedBox(height: 10),
              _licensesLink(),
            ],
          ),
        ),
      ),
    );
  }

  /// The one legal obligation of the app: flutter_recorder ships under
  /// Apache 2.0 and asks to be credited. This is the quietest place that is
  /// still findable — settings territory, without building a settings screen.
  Widget _licensesLink() {
    return Center(
      child: GestureDetector(
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Looper',
          applicationLegalese:
              'Instrumento de bolsillo. Todo el audio vive en tu dispositivo.',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            'LICENCIAS DE CÓDIGO ABIERTO',
            style: Brand.label(8).copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Palette.inkFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Palette.line),
            ),
            child: const Icon(Icons.arrow_back, size: 16, color: Palette.inkDim),
          ),
        ),
        const SizedBox(width: 12),
        Text('Sesiones', style: Brand.title(17)),
      ],
    );
  }

  Widget _row(Session session) {
    final isCurrent = session.id == widget.currentId;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(session),
      onLongPress: () => _openActions(session),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isCurrent ? Palette.panelHigh : Palette.panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: isCurrent ? Palette.accent : Palette.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name,
                    overflow: TextOverflow.ellipsis,
                    style: Brand.strong(
                      14.5,
                      color: isCurrent ? Palette.ink : Palette.inkDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.filledPadCount} pads · ${session.bpm} BPM · '
                    '${_formatDate(session.updatedAt)}',
                    style: Brand.readout(9, color: Palette.inkFaint),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              Text(
                'ABIERTA',
                style: Brand.label(8, weight: 700, color: Palette.accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _newButton() {
    return GestureDetector(
      onTap: _createSession,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'SESIÓN NUEVA',
          style: Brand.label(10, weight: 700, color: Palette.onAccent),
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    final session = buildStarterSession(
      widget.library,
      name: 'Sesión ${widget.store.sessions.length + 1}',
    );
    await widget.store.save(session);
    if (!mounted) return;
    Navigator.of(context).pop(session);
  }

  Future<void> _openActions(Session session) async {
    final isCurrent = session.id == widget.currentId;
    final isLast = widget.store.sessions.length == 1;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _action(sheetContext, Icons.edit_outlined, 'Renombrar',
                () => _rename(session)),
            _action(sheetContext, Icons.copy_outlined, 'Duplicar',
                () => _duplicate(session)),
            _action(
              sheetContext,
              Icons.bookmark_border,
              _savePointsLabel(session),
              () => _openSavePoints(session),
            ),
            _action(
              sheetContext,
              Icons.delete_outline,
              isCurrent
                  ? 'No se puede borrar la sesión abierta'
                  : (isLast ? 'Debe quedar una sesión' : 'Borrar'),
              isCurrent || isLast ? null : () => _delete(session),
              danger: true,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _action(
    BuildContext sheetContext,
    IconData icon,
    String label,
    Future<void> Function()? onTap, {
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final color = !enabled
        ? Palette.inkFaint
        : (danger ? Palette.rec : Palette.ink);

    return ListTile(
      leading: Icon(icon, size: 18, color: color),
      title: Text(label, style: Brand.strong(13.5, color: color)),
      onTap: enabled
          ? () {
              Navigator.of(sheetContext).pop();
              onTap();
            }
          : null,
    );
  }

  Future<void> _rename(Session session) async {
    final controller = TextEditingController(text: session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text('Renombrar', style: Brand.title(16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          style: Brand.strong(15),
          cursorColor: Palette.accent,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCELAR',
                style: Brand.label(9, weight: 700, color: Palette.inkDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text('GUARDAR',
                style: Brand.label(9, weight: 700, color: Palette.accent)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) return;
    await widget.store.rename(session, name);
    if (mounted) setState(() {});
  }

  Future<void> _duplicate(Session session) async {
    await widget.store.duplicate(session);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Session session) async {
    await widget.store.remove(session.id);
    // Snapshots of something deleted have nothing left to restore onto.
    await widget.savePoints.removeForSession(session.id);
    if (mounted) setState(() {});
  }

  String _savePointsLabel(Session session) {
    final n = widget.savePoints.countFor(session.id);
    if (n == 0) return 'Puntos de guardado';
    return 'Puntos de guardado · $n';
  }

  /// The snapshots of one session. Capturing is only offered for the session
  /// that is open — the instrument only holds one at a time, and a point of a
  /// session you are not in would be a copy of what is already on disk.
  Future<void> _openSavePoints(Session session) async {
    final isCurrent = session.id == widget.currentId;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final points = widget.savePoints.forSession(session.id);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PUNTOS DE GUARDADO', style: Brand.label(8.5, weight: 700)),
                  const SizedBox(height: 6),
                  Text(
                    'Una foto de cómo suena ahora, para poder volver.',
                    style: Brand.body(12, color: Palette.inkFaint),
                  ),
                  const SizedBox(height: 14),
                  if (points.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Todavía no hay ninguno.',
                        textAlign: TextAlign.center,
                        style: Brand.body(12.5, color: Palette.inkFaint),
                      ),
                    ),
                  ...points.map((p) => _savePointRow(
                        p,
                        canRestore: isCurrent,
                        onChanged: () => setSheetState(() {}),
                        sheetContext: sheetContext,
                      )),
                  const SizedBox(height: 10),
                  if (isCurrent)
                    _sheetButton(
                      'GUARDAR ESTE MOMENTO',
                      onTap: () async {
                        await widget.savePoints.capture(
                          widget.currentSession,
                          name: _defaultPointName(points.length),
                        );
                        setSheetState(() {});
                      },
                    )
                  else
                    Text(
                      'Abre esta sesión para guardar un punto nuevo.',
                      textAlign: TextAlign.center,
                      style: Brand.body(11.5, color: Palette.inkFaint),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  String _defaultPointName(int existing) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Punto ${existing + 1} · ${two(now.hour)}:${two(now.minute)}';
  }

  Widget _savePointRow(
    SavePoint point, {
    required bool canRestore,
    required VoidCallback onChanged,
    required BuildContext sheetContext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(point.name, style: Brand.strong(13.5)),
                  const SizedBox(height: 3),
                  Text(
                    '${point.session.filledPadCount} pads · '
                    '${point.session.bpm} BPM',
                    style: Brand.label(7.5, width: 75),
                  ),
                ],
              ),
            ),
            if (canRestore)
              GestureDetector(
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await widget.onRestore(point);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('VOLVER',
                      style: Brand.label(8.5, weight: 700, color: Palette.accent)),
                ),
              ),
            GestureDetector(
              onTap: () async {
                await widget.savePoints.remove(point.id);
                onChanged();
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close, size: 16, color: Palette.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.accent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(label,
            style: Brand.label(9.5, weight: 700, color: Palette.onAccent)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 1) return 'ahora';
    if (difference.inHours < 1) return 'hace ${difference.inMinutes} min';
    if (difference.inDays < 1) return 'hace ${difference.inHours} h';
    if (difference.inDays < 7) return 'hace ${difference.inDays} d';
    return '${date.day}/${date.month}';
  }
}
