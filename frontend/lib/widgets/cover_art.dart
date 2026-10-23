import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/music_api.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 12,
    this.loading = false,
  });

  final String? url;
  final double size;
  final double radius;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final api = context.read<MusicApi>();
    // Thumbnails do YouTube não têm CORS; no web usamos o placeholder até a
    // capa local ficar pronta no servidor.
    final effectiveUrl =
        kIsWeb && (url?.contains('ytimg.com') ?? false) ? null : url;
    final absolute = api.absoluteUrl(effectiveUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: absolute == null
            ? _Placeholder(loading: loading)
            : Image.network(
                absolute,
                headers: api.authHeaders.isEmpty ? null : api.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _Placeholder(loading: loading),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return const _Placeholder(loading: true);
                },
              ),
      ),
    );
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
