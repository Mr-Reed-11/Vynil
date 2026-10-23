import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../core/format.dart';
import '../screens/now_playing_screen.dart';
import 'cover_art.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        final track = player.current;
        if (track == null) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final total = player.duration ?? track.duration;
        final maxMs = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Só a linha de progresso escuta a posição (ValueListenable),
                    // evitando reconstruir a barra inteira a cada tick.
                    ValueListenableBuilder<Duration>(
                      valueListenable: player.positionListenable,
                      builder: (context, position, _) {
                        final progress = player.isLoading
                            ? null
                            : (position.inMilliseconds / maxMs)
                                .clamp(0.0, 1.0)
                                .toDouble();
                        return LinearProgressIndicator(
                          value: progress,
                          minHeight: 2.5,
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.08),
                        );
                      },
                    ),
                    InkWell(
                      onTap: () =>
                          Navigator.of(context).push(nowPlayingRoute()),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'player-cover',
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                child: CoverArt(
                                  key: ValueKey(track.id),
                                  url: track.coverUrl ?? track.thumbnailUrl,
                                  size: 50,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (player.error != null)
                                    Text(
                                      player.error!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.error,
                                      ),
                                    )
                                  else
                                    ValueListenableBuilder<Duration>(
                                      valueListenable: player.positionListenable,
                                      builder: (context, position, _) => Text(
                                        '${track.artist} • '
                                        '${formatDuration(position)} / '
                                        '${formatDuration(total)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Anterior',
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  player.hasQueue ? player.previous : null,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            if (player.isLoading)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            else
                              IconButton.filled(
                                tooltip:
                                    player.isPlaying ? 'Pausar' : 'Reproduzir',
                                onPressed: player.toggle,
                                icon: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: Icon(
                                    player.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey(player.isPlaying),
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: 'Próxima',
                              visualDensity: VisualDensity.compact,
                              onPressed: player.hasQueue ? player.next : null,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            IconButton(
                              tooltip: 'Fechar player',
                              visualDensity: VisualDensity.compact,
                              onPressed: player.stop,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
