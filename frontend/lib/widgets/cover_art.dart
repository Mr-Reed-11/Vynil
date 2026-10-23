import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/download_controller.dart';
import '../data/music_api.dart';
import 'local_image.dart';

/// Resolve a URL de capa para exibição, aplicando a regra do web:
/// thumbnails do YouTube (ytimg.com) não têm CORS, então no web caem no
/// placeholder até a capa local do servidor ficar pronta.
String? resolveCoverUrl(BuildContext context, String? url) {
  final api = context.read<MusicApi>();
  final effective =
      kIsWeb && (url?.contains('ytimg.com') ?? false) ? null : url;
  return api.absoluteUrl(effective);
}

class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 12,
    this.loading = false,
    this.heroTag,
    this.elevation = 0,
    this.trackId,
  });

  final String? url;
  final double size;
  final double radius;
  final bool loading;
  final Object? heroTag;
  final double elevation;

  /// Se informado e a faixa estiver baixada, usa a capa LOCAL (funciona
  /// offline, sem depender do servidor).
  final String? trackId;

  @override
  Widget build(BuildContext context) {
    final api = context.read<MusicApi>();
    final absolute = resolveCoverUrl(context, url);
    final localProvider = trackId == null
        ? null
        : localImage(context.read<DownloadController>().localCoverPath(trackId!));

    // Decodifica a imagem no tamanho de exibição (evita decodificar 1280px
    // para caber em 50px — grande ganho de memória/fluidez).
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = size.isFinite ? (size * dpr).round() : null;

    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: localProvider != null
            ? Image(
                image: cachePx != null
                    ? ResizeImage(localProvider,
                        width: cachePx, height: cachePx)
                    : localProvider,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _Placeholder(loading: loading),
              )
            : absolute == null
            ? _Placeholder(loading: loading)
            : Image.network(
                absolute,
                headers: api.authHeaders.isEmpty ? null : api.authHeaders,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: cachePx,
                cacheHeight: cachePx,
                errorBuilder: (_, _, _) => _Placeholder(loading: loading),
                frameBuilder: (context, child, frame, wasSync) {
                  if (wasSync) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _Placeholder(loading: true);
                },
              ),
      ),
    );

    if (elevation > 0) {
      image = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: elevation,
              offset: Offset(0, elevation * 0.35),
            ),
          ],
        ),
        child: image,
      );
    }

    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return image;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimaryContainer,
                ),
              )
            : Icon(
                Icons.music_note_rounded,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
      ),
    );
  }
}
