import 'track.dart';

/// Stub web: sem dart:io, download offline não se aplica.
class OfflineStore {
  Future<void> init([String userId = '_default']) async {}

  Set<String> get downloadedIds => const {};
  List<Track> get tracks => const [];

  bool isDownloaded(String id) => false;
  String? audioPath(String id) => null;
  String? coverPath(String id) => null;

  Future<void> setDurationIfMissing(String id, int seconds) async {}

  Future<void> remove(String id) async {}

  Future<Track> downloadFromYoutube(
    String videoUrl, {
    required String serverUrl,
    String serverKey = '',
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('Download disponível apenas no app.');
  }
}
