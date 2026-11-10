import 'package:flutter/foundation.dart';

import '../data/offline_store.dart';
import '../data/track.dart';

/// Expõe o estado do armazenamento local (o que está salvo, caminhos dos
/// arquivos) para a UI. O download em si acontece no [OfflineStore] via
/// [LibraryController.downloadFromYoutube].
class DownloadController extends ChangeNotifier {
  DownloadController(this._store);

  final OfflineStore _store;

  OfflineStore get store => _store;

  bool get supported => !kIsWeb;

  bool isDownloaded(String id) => _store.isDownloaded(id);
  Set<String> get downloadedIds => _store.downloadedIds;
  List<Track> get offlineTracks => _store.tracks;

  String? localAudioPath(String id) => _store.audioPath(id);
  String? localCoverPath(String id) => _store.coverPath(id);

  Future<void> remove(String id) async {
    await _store.remove(id);
    notifyListeners();
  }
}
