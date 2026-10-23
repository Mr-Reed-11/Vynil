import 'package:flutter/material.dart';

import '../data/track.dart';
import '../widgets/blurred_backdrop.dart';
import '../widgets/cover_art.dart';
import '../widgets/entrance.dart';
import '../widgets/player_bar.dart';
import '../widgets/track_tile.dart';

/// Agrupamento de faixas por artista (coleção automática por metadados).
class ArtistGroup {
  ArtistGroup(this.name, this.tracks);

  final String name;
  final List<Track> tracks;

  /// Primeira faixa com capa disponível, usada como arte do grupo.
  Track? get cover => tracks.firstWhere(
        (t) => (t.coverUrl ?? t.thumbnailUrl) != null,
        orElse: () => tracks.first,
      );

  int get readyCount => tracks.where((t) => t.isReady).length;
}

List<ArtistGroup> groupByArtist(List<Track> tracks) {
  final map = <String, List<Track>>{};
  for (final track in tracks) {
    map.putIfAbsent(track.artist, () => []).add(track);
  }
  final groups = map.entries
      .map((e) => ArtistGroup(e.key, e.value))
      .toList(growable: false)
    ..sort((a, b) {
      final byCount = b.tracks.length.compareTo(a.tracks.length);
      return byCount != 0 ? byCount : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return groups;
}

/// Agrupa por álbum (tag). Faixas sem álbum ficam de fora.
List<ArtistGroup> groupByAlbum(List<Track> tracks) {
  final map = <String, List<Track>>{};
  for (final track in tracks) {
    final album = track.album;
    if (album == null || album.isEmpty) continue;
    map.putIfAbsent(album, () => []).add(track);
  }
  final groups = map.entries
      .map((e) => ArtistGroup(e.key, e.value))
      .toList(growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

Route<void> artistRoute(ArtistGroup group) {
  return MaterialPageRoute<void>(builder: (_) => ArtistScreen(group: group));
}

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key, required this.group});

  final ArtistGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = group.cover != null
        ? (group.cover!.coverUrl ?? group.cover!.thumbnailUrl)
        : null;
    final label = group.tracks.length == 1 ? 'faixa' : 'faixas';

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const PlayerBar(),
      body: BlurredBackdrop(
        url: coverUrl,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Voltar',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CoverArt(url: coverUrl, size: 150, radius: 20, elevation: 40),
                  const SizedBox(height: 16),
                  Text(
                    group.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${group.tracks.length} $label',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      itemCount: group.tracks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => Entrance(
                        key: ValueKey(group.tracks[index].id),
                        delay: Duration(milliseconds: (index * 35).clamp(0, 400)),
                        child: TrackTile(
                          track: group.tracks[index],
                          queue: group.tracks,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
