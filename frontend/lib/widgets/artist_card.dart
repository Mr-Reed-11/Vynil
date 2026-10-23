import 'package:flutter/material.dart';

import '../screens/artist_screen.dart';
import 'cover_art.dart';

class ArtistCard extends StatelessWidget {
  const ArtistCard({super.key, required this.group});

  final ArtistGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = group.cover;
    final coverUrl =
        cover != null ? (cover.coverUrl ?? cover.thumbnailUrl) : null;
    final label = group.tracks.length == 1 ? 'faixa' : 'faixas';

    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(artistRoute(group)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CoverArt(
                      url: coverUrl,
                      size: double.infinity,
                      radius: 14,
                      elevation: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${group.tracks.length} $label',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
