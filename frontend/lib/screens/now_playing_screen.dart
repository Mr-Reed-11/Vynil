import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../core/format.dart';
import '../widgets/blurred_backdrop.dart';
import '../widgets/cover_art.dart';

/// Rota com transição de subida + fade para a tela cheia do player.
Route<void> nowPlayingRoute() {
  return PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;

    // Se o player for fechado enquanto a tela está aberta, volta.
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final coverUrl = track.coverUrl ?? track.thumbnailUrl;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BlurredBackdrop(
        url: coverUrl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _TopBar(onClose: () => Navigator.of(context).maybePop()),
                const Spacer(),
                Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side =
                          (constraints.maxWidth).clamp(0.0, 340.0).toDouble();
                      // Hero por fora, crossfade por dentro: a capa "voa" ao
                      // abrir a tela e faz fade ao trocar de faixa.
                      return Hero(
                        tag: 'player-cover',
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: CoverArt(
                            key: ValueKey(track.id),
                            url: coverUrl,
                            size: side,
                            radius: 24,
                            elevation: 48,
                            trackId: track.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Column(
                    key: ValueKey(track.id),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artist,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SeekBar(),
                const SizedBox(height: 8),
                const _Controls(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          tooltip: 'Fechar',
        ),
        Expanded(
          child: Text(
            'TOCANDO AGORA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final total = player.duration ?? player.current?.duration ?? Duration.zero;
    final maxValue =
        total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();

    // A posição vem do ValueNotifier: só este bloco reconstrói a cada tick.
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionListenable,
      builder: (context, pos, _) {
        final position =
            pos.inMilliseconds.clamp(0, maxValue.toInt()).toDouble();
        final value = (_dragValue ?? position).clamp(0.0, maxValue).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: Theme.of(context).sliderTheme.copyWith(
                    activeTrackColor: scheme.primary,
                    thumbColor: scheme.primary,
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(Duration(milliseconds: value.round())),
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  Text(
                    formatDuration(total),
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final canQueue = player.hasQueue;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 26,
              onPressed: player.toggleShuffle,
              tooltip: player.isShuffle ? 'Aleatório: ligado' : 'Aleatório: desligado',
              icon: Icon(
                Icons.shuffle_rounded,
                color: player.isShuffle
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              iconSize: 36,
              onPressed: canQueue ? player.previous : null,
              icon: const Icon(Icons.skip_previous_rounded),
              tooltip: 'Anterior',
            ),
            _PlayButton(
              isPlaying: player.isPlaying,
              isLoading: player.isLoading,
              onTap: player.toggle,
              color: scheme.primary,
              onColor: scheme.onPrimary,
            ),
            IconButton(
              iconSize: 36,
              onPressed: canQueue ? player.next : null,
              icon: const Icon(Icons.skip_next_rounded),
              tooltip: 'Próxima',
            ),
            IconButton(
              iconSize: 26,
              onPressed: player.stop,
              tooltip: 'Fechar player',
              icon: Icon(Icons.stop_rounded, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          player.isShuffle ? 'Reprodução aleatória' : 'Reprodução sequencial',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
    required this.color,
    required this.onColor,
  });

  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 3, color: onColor),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(isPlaying),
                  size: 40,
                  color: onColor,
                ),
              ),
      ),
    );
  }
}
