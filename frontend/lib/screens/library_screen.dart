import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../core/theme.dart';
import '../widgets/add_track_sheet.dart';
import '../widgets/artist_card.dart';
import '../widgets/entrance.dart';
import '../widgets/player_bar.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _openAddSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const AddTrackSheet(),
    );

    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = context.read<LibraryController>().search;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Minha música'),
          actions: [
            Consumer<LibraryController>(
              builder: (context, library, _) => IconButton(
                tooltip: 'Atualizar',
                onPressed: library.loading ? null : () => library.load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            IconButton(
              tooltip: 'Configurações',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppColors.backdrop,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por título ou artista',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: search,
                      ),
                    ),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Faixas'),
                        Tab(text: 'Álbuns'),
                        Tab(text: 'Artistas'),
                      ],
                    ),
                    Expanded(
                      child: Consumer<LibraryController>(
                        builder: (context, library, _) {
                          final state = _stateOf(context, library);
                          if (state != null) return state;
                          return TabBarView(
                            children: [
                              _TracksTab(library: library),
                              _AlbumsTab(library: library),
                              _ArtistsTab(library: library),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAddSheet(context),
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Adicionar'),
        ),
        bottomNavigationBar: const PlayerBar(),
      ),
    );
  }

  /// Estados que substituem ambas as abas (carregando/erro/vazio).
  Widget? _stateOf(BuildContext context, LibraryController library) {
    if (library.loading && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (library.error != null && library.tracks.isEmpty) {
      return _ErrorState(message: library.error!, onRetry: () => library.load());
    }
    if (library.tracks.isEmpty) {
      return _EmptyState(
        serverUrl: library.serverUrl,
        onAdd: () => _openAddSheet(context),
      );
    }
    return null;
  }
}

class _TracksTab extends StatelessWidget {
  const _TracksTab({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final hasBanner = library.error != null;

    return RefreshIndicator(
      onRefresh: () => library.load(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
        itemCount: library.tracks.length + (hasBanner ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (hasBanner) {
            if (index == 0) {
              return _ErrorBanner(
                message: library.error!,
                onRetry: () => library.load(silent: true),
              );
            }
            index -= 1;
          }
          final track = library.tracks[index];
          return Entrance(
            key: ValueKey(track.id),
            delay: Duration(milliseconds: (index * 35).clamp(0, 400)),
            child: TrackTile(track: track, queue: library.tracks),
          );
        },
      ),
    );
  }
}

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final groups = groupByAlbum(library.tracks);
    final scheme = Theme.of(context).colorScheme;

    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => library.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 120),
          children: [
            Icon(Icons.album_rounded,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Nenhum álbum ainda',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Álbuns aparecem ao baixar uma playlist (vira um álbum) ou '
              'faixas que tenham a tag de álbum.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => library.load(silent: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 220,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: groups.length,
        itemBuilder: (context, index) => Entrance(
          key: ValueKey('album-${groups[index].name}'),
          delay: Duration(milliseconds: (index * 40).clamp(0, 400)),
          child: ArtistCard(group: groups[index]),
        ),
      ),
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final groups = groupByArtist(library.tracks);

    return RefreshIndicator(
      onRefresh: () => library.load(silent: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 220,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: groups.length,
        itemBuilder: (context, index) => Entrance(
          key: ValueKey('artist-${groups[index].name}'),
          delay: Duration(milliseconds: (index * 40).clamp(0, 400)),
          child: ArtistCard(group: groups[index]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.serverUrl, required this.onAdd});

  final String serverUrl;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 120),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.surfaceContainerHighest,
                ],
              ),
            ),
            child: Icon(
              Icons.library_music_rounded,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sua biblioteca está vazia',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Cole o link de um vídeo do YouTube para baixar a música e '
            'ouvir aqui mesmo.',
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Adicionar música'),
          ),
          const SizedBox(height: 32),
          Text(
            'Servidor: $serverUrl',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 120),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: scheme.error),
          const SizedBox(height: 16),
          Text(
            'Não foi possível falar com o servidor',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Tentar'),
            ),
          ],
        ),
      ),
    );
  }
}
