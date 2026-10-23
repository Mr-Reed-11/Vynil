import 'package:flutter/foundation.dart';

import '../data/music_api.dart';
import '../data/offline_store.dart';
import '../data/track.dart';

/// Coordena downloads para o dispositivo e expõe o estado (baixado/baixando/
/// progresso) para a UI. O armazenamento real fica no [OfflineStore].
class DownloadController extends ChangeNotifier {
  DownloadController(this._api, this._store);

  final MusicApi _api;
  final OfflineStore _store;
  final Map<String, double> _progress = {};

  OfflineStore get store => _store;

  /// No-op mantido por compatibilidade de wiring; o OfflineStore agora é
  /// inicializado em main.dart com o id do usuário autenticado.
  Future<void> init() async {
    notifyListeners();
  }

  bool get supported => !kIsWeb;

  bool isDownloaded(String id) => _store.isDownloaded(id);
  bool isDownloading(String id) => _progress.containsKey(id);
  double progressOf(String id) => _progress[id] ?? 0;
  Set<String> get downloadedIds => _store.downloadedIds;
  List<Track> get offlineTracks => _store.tracks;

  /// Caminho do arquivo local (ou null se não baixado).
  String? localAudioPath(String id) => _store.audioPath(id);
  String? localCoverPath(String id) => _store.coverPath(id);

  Future<void> download(Track track) async {
    if (!supported || !track.isReady) return;
    if (_store.isDownloaded(track.id) || _progress.containsKey(track.id)) return;

    _progress[track.id] = 0;
    notifyListeners();
    try {
      await _store.download(
        track: track,
        api: _api,
        onProgress: (p) {
          _progress[track.id] = p;
          notifyListeners();
        },
      );
    } finally {
      _progress.remove(track.id);
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    await _store.remove(id);
    notifyListeners();
  }
}
