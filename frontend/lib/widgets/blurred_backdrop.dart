import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/music_api.dart';
import 'cover_art.dart';

/// Fundo imersivo: a capa ampliada e borrada, com um scrim escuro por cima
/// para manter o texto legível. Sem capa, cai no gradiente da aplicação.
class BlurredBackdrop extends StatelessWidget {
  const BlurredBackdrop({
    super.key,
    required this.url,
    this.sigma = 45,
    this.child,
  });

  final String? url;
  final double sigma;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final api = context.read<MusicApi>();
    final absolute = resolveCoverUrl(context, url);

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppColors.backdrop,
            ),
          ),
        ),
        RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: absolute == null
                ? const SizedBox.expand(key: ValueKey('no-cover'))
                : ImageFiltered(
                    key: ValueKey(absolute),
                    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: Image.network(
                      absolute,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      headers: api.authHeaders.isEmpty ? null : api.authHeaders,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.35),
                AppColors.background.withValues(alpha: 0.75),
                AppColors.background.withValues(alpha: 0.96),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}
