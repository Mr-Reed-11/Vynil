import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/music_api.dart';
import '../data/offline_store.dart';
import '../data/track.dart';

/// Estado da biblioteca: lista, busca, polling de downloads e ações.
class LibraryController extends ChangeNotifier {
  LibraryController(this._api, [this._store]);

  final MusicApi _api;
  final OfflineStore? _store;

  List<Track> _tracks = const [];
  bool _loading = false;
  bool _offline = false;
  String? _error;
  String _query = '';
  Timer? _pollTimer;
  Timer? _searchTimer;
  bool _disposed = false;

  List<Track> get tracks => _tracks;
  bool get loading => _loading;
  /// true quando a lista exibida vem do cache (servidor inacessível).
  bool get offline => _offline;
  String? get error => _error;
  String get query => _query;
  String get serverUrl => _api.baseUrl;

  bool get hasActiveDownloads =>
      _tracks.any((track) => track.status.isBusy);

  Future<void> load({bool silent = false}) async {
    _pollTimer?.cancel();

    if (!silent) {
      _loading = true;
      _error = null;
      _notify();
    }

    try {
      final tracks = await _api.fetchTracks(query: _query);
      if (_disposed) {
        return;
      }
      _tracks = tracks;
      _error = null;
      _offline = false;
      // Cacheia o catálogo completo para uso offline (só sem busca ativa,
      // pra não gravar uma lista filtrada como se fosse a biblioteca toda).
      if (_query.trim().isEmpty) {
        unawaited(_store?.saveCatalog(tracks) ?? Future.value());
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      // Servidor inacessível: cai para o catálogo em cache (biblioteca toda).
      // As baixadas tocam; as não baixadas aparecem como indisponíveis offline.
      final cached = _offlineTracks();
      if (cached.isNotEmpty) {
        _tracks = cached;
        _offline = true;
        _error = 'Offline — tocando só o que está salvo no dispositivo.';
      } else {
        _offline = false;
        _error = error.toString();
      }
    } finally {
      if (!_disposed) {
        _loading = false;
        _schedulePoll();
        notifyListeners();
      }
    }
  }

  void search(String value) {
    _query = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), () {
      load(silent: true);
    });
  }

  Future<Track> add(String url) async {
    final track = await _api.addTrack(url);
    await load(silent: true);
    return track;
  }

  Future<PlaylistResult> addPlaylist(String url) async {
    final result = await _api.addPlaylist(url);
    await load(silent: true);
    return result;
  }

  Future<void> retry(Track track) async {
    await _api.retryTrack(track.id);
    await load(silent: true);
  }

  Future<void> remove(Track track) async {
    await _api.deleteTrack(track.id);
    await load(silent: true);
  }

  List<Track> _offlineTracks() {
    final store = _store;
    if (store == null) return const [];
    // Catálogo completo (todas as faixas vistas por último), com fallback para
    // as baixadas caso ainda não exista catálogo salvo.
    final all = store.catalog.isNotEmpty ? store.catalog : store.tracks;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!hasActiveDownloads) {
      return;
    }
    _pollTimer = Timer(const Duration(seconds: 2), () {
      load(silent: true);
    });
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    super.dispose();
  }
}
