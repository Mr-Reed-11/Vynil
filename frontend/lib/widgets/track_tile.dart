import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../controllers/player_controller.dart';
import '../core/format.dart';
import '../data/track.dart';
import 'cover_art.dart';

enum _TrackAction { play, delete }

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, this.queue});

  final Track track;

  /// Lista visível à qual esta faixa pertence; vira a fila do player.
  final List<Track>? queue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // `select` evita reconstruir TODA a lista a cada mudança de player.
    final isCurrent = context.select<PlayerController, bool>(
      (p) => p.current?.id == track.id,
    );
    final isPlaying = context.select<PlayerController, bool>(
      (p) => p.current?.id == track.id && p.isPlaying,
    );

    return Material(
      color: isCurrent
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLow.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () =>
            context.read<PlayerController>().playTrack(track, queue: queue),
        leading: CoverArt(
          url: track.coverUrl ?? track.thumbnailUrl,
          trackId: track.id,
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            color: isCurrent ? scheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${track.artist} • ${formatDuration(track.duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
              onPressed: () =>
                  context.read<PlayerController>().playTrack(track, queue: queue),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            PopupMenuButton<_TrackAction>(
              tooltip: 'Opções',
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _TrackAction.play,
                  child: Text('Reproduzir'),
                ),
                PopupMenuItem(
                  value: _TrackAction.delete,
                  child: Text('Excluir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, _TrackAction action) async {
    switch (action) {
      case _TrackAction.play:
        await context.read<PlayerController>().playTrack(track, queue: queue);
      case _TrackAction.delete:
        await _delete(context);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final library = context.read<LibraryController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir faixa?'),
        content: Text('"${track.title}" será removida do dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await library.remove(track);
      messenger.showSnackBar(
        const SnackBar(content: Text('Faixa excluída.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
