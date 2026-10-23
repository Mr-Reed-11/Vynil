import 'music_api.dart';
import 'track.dart';

/// Stub web: sem dart:io, download offline não se aplica.
class OfflineStore {
  Future<void> init() async {}

  Set<String> get downloadedIds => const {};
  List<Track> get tracks => const [];

  bool isDownloaded(String id) => false;
  String? audioPath(String id) => null;
  String? coverPath(String id) => null;

  Future<void> download({
    required Track track,
    required MusicApi api,
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('Download offline disponível apenas no app.');
  }

  Future<void> remove(String id) async {}
}
