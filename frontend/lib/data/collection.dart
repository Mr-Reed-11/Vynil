import 'track.dart';

/// Playlist/coleção manual.
class Collection {
  Collection({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.trackCount,
    this.items = const [],
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final int trackCount;

  /// Faixas resolvidas (preenchido no detalhe; vazio na listagem).
  final List<Track> items;

  factory Collection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return Collection(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Playlist',
      trackIds: (json['trackIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      trackCount: (json['trackCount'] as num?)?.toInt() ??
          (json['trackIds'] as List<dynamic>? ?? const []).length,
      items: rawItems
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
