import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../core/format.dart';
import 'cover_art.dart';

class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  double? _dragValue;

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
        final maxValue = total.inMilliseconds <= 0
            ? 1.0
            : total.inMilliseconds.toDouble();
        final position = player.position.inMilliseconds
            .clamp(0, maxValue.toInt())
            .toDouble();
        final value = (_dragValue ?? position).clamp(0.0, maxValue).toDouble();

        return Material(
          color: scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: Theme.of(context).sliderTheme.copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                  child: Slider(
                    min: 0,
                    max: maxValue,
                    value: value,
                    onChanged: (next) => setState(() => _dragValue = next),
                    onChangeEnd: (next) {
                      setState(() => _dragValue = null);
                      player.seek(Duration(milliseconds: next.round()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
                  child: Row(
                    children: [
                      CoverArt(
                        url: track.coverUrl ?? track.thumbnailUrl,
                        size: 48,
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
                            Text(
                              player.error ??
                                  '${track.artist} • '
                                      '${formatDuration(player.position)} / '
                                      '${formatDuration(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: player.error != null
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Voltar 10s',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            player.skipBy(const Duration(seconds: -10)),
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      if (player.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      else
                        IconButton.filled(
                          tooltip: player.isPlaying ? 'Pausar' : 'Reproduzir',
                          onPressed: player.toggle,
                          icon: Icon(
                            player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Avançar 10s',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            player.skipBy(const Duration(seconds: 10)),
                        icon: const Icon(Icons.forward_10_rounded),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
