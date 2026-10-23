import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/download_controller.dart';
import '../controllers/library_controller.dart';
import '../controllers/player_controller.dart';
import '../core/format.dart';
import '../data/track.dart';
import 'cover_art.dart';

enum _TrackAction { play, retry, delete, download, removeDownload }

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
    final downloaded = context.select<DownloadController, bool>(
      (d) => d.isDownloaded(track.id),
    );
    final downloading = context.select<DownloadController, bool>(
      (d) => d.isDownloading(track.id),
    );
    final offline = context.select<LibraryController, bool>((l) => l.offline);
    // Sem conexão e não baixada: não dá pra tocar (só mostrar como indisponível).
    final unavailableOffline =
        offline && !downloaded && track.status == TrackStatus.ready;
    final busy = track.status.isBusy;

    return Opacity(
      opacity: unavailableOffline ? 0.55 : 1.0,
      child: Material(
      color: isCurrent
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLow.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () => _onTap(context),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            CoverArt(
              url: track.coverUrl ?? track.thumbnailUrl,
              trackId: track.id,
            ),
            if (busy) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: track.status == TrackStatus.downloading
                      ? (track.progress / 100).clamp(0.0, 1.0).toDouble()
                      : null,
                  strokeWidth: 2.5,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
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
          _subtitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: track.status == TrackStatus.error
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (downloading)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Builder(
                    builder: (context) {
                      final p = context.select<DownloadController, double>(
                        (d) => d.progressOf(track.id),
                      );
                      return CircularProgressIndicator(
                        strokeWidth: 2,
                        value: p > 0 ? p : null,
                        color: scheme.primary,
                      );
                    },
                  ),
                ),
              )
            else if (downloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Salvo no dispositivo',
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
              ),
            if (unavailableOffline)
              IconButton(
                tooltip: 'Indisponível offline',
                onPressed: () => _offlineNotice(context),
                icon: Icon(Icons.cloud_off_rounded,
                    color: scheme.onSurfaceVariant),
              )
            else if (track.status == TrackStatus.ready)
              IconButton.filledTonal(
                tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
                onPressed: () => context
                    .read<PlayerController>()
                    .playTrack(track, queue: queue),
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              )
            else if (track.status == TrackStatus.error)
              IconButton(
                tooltip: 'Tentar novamente',
                onPressed: () => _retry(context),
                icon: const Icon(Icons.refresh_rounded),
              ),
            PopupMenuButton<_TrackAction>(
              tooltip: 'Opções',
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (menuContext) {
                final downloads = menuContext.read<DownloadController>();
                return [
                  if (track.status == TrackStatus.ready)
                    const PopupMenuItem(
                      value: _TrackAction.play,
                      child: Text('Reproduzir'),
                    ),
                  if (track.status == TrackStatus.error)
                    const PopupMenuItem(
                      value: _TrackAction.retry,
                      child: Text('Tentar novamente'),
                    ),
                  if (track.status == TrackStatus.ready &&
                      downloads.supported &&
                      !downloaded &&
                      !downloading)
                    const PopupMenuItem(
                      value: _TrackAction.download,
                      child: Text('Baixar no dispositivo'),
                    ),
                  if (downloaded)
                    const PopupMenuItem(
                      value: _TrackAction.removeDownload,
                      child: Text('Remover download'),
                    ),
                  const PopupMenuItem(
                    value: _TrackAction.delete,
                    child: Text('Excluir'),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _subtitle() {
    return switch (track.status) {
      TrackStatus.error => track.error ?? 'Falha no download.',
      TrackStatus.queued => '${track.status.label} • 0%',
      TrackStatus.downloading =>
        '${track.status.label} • ${track.progress.round()}%',
      TrackStatus.ready =>
        '${track.artist} • ${formatDuration(track.duration)}',
    };
  }

  void _offlineNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Faixa não baixada — conecte ao servidor ou '
            'baixe-a para ouvir offline.'),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final offline = context.read<LibraryController>().offline;
    final downloaded = context.read<DownloadController>().isDownloaded(track.id);
    if (track.status == TrackStatus.ready) {
      if (offline && !downloaded) {
        _offlineNotice(context);
        return;
      }
      context.read<PlayerController>().playTrack(track, queue: queue);
      return;
    }
    if (track.status == TrackStatus.error) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(track.error ?? 'Falha no download.'),
          action: SnackBarAction(
            label: 'Tentar',
            onPressed: () => _retry(context),
          ),
        ),
      );
    }
  }

  Future<void> _handleAction(BuildContext context, _TrackAction action) async {
    switch (action) {
      case _TrackAction.play:
        await context
            .read<PlayerController>()
            .playTrack(track, queue: queue);
      case _TrackAction.retry:
        await _retry(context);
      case _TrackAction.delete:
        await _delete(context);
      case _TrackAction.download:
        await _download(context);
      case _TrackAction.removeDownload:
        await context.read<DownloadController>().remove(track.id);
    }
  }

  Future<void> _download(BuildContext context) async {
    final downloads = context.read<DownloadController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await downloads.download(track);
      messenger.showSnackBar(
        SnackBar(content: Text('"${track.title}" salva no dispositivo.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _retry(BuildContext context) async {
    final library = context.read<LibraryController>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await library.retry(track);
      messenger.showSnackBar(
        const SnackBar(content: Text('Download reenfileirado.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final library = context.read<LibraryController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir faixa?'),
        content: Text('"${track.title}" será removida do servidor.'),
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

    if (confirmed != true) {
      return;
    }

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
