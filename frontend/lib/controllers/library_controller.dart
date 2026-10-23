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
  String? _error;
  String _query = '';
  Timer? _pollTimer;
  Timer? _searchTimer;
  bool _disposed = false;

  List<Track> get tracks => _tracks;
  bool get loading => _loading;
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
    } catch (error) {
      if (_disposed) {
        return;
      }
      // Servidor inacessível: cai para a biblioteca offline (faixas baixadas),
      // mantendo o app utilizável sem conexão.
      final offline = _offlineTracks();
      if (offline.isNotEmpty) {
        _tracks = offline;
        _error = 'Offline — mostrando faixas salvas no dispositivo.';
      } else {
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
    final q = _query.trim().toLowerCase();
    final tracks = store.tracks;
    if (q.isEmpty) return tracks;
    return tracks
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
