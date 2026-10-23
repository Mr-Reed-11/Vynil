import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/music_api.dart';
import '../data/track.dart';

/// Estado da biblioteca: lista, busca, polling de downloads e ações.
class LibraryController extends ChangeNotifier {
  LibraryController(this._api);

  final MusicApi _api;

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
      _error = error.toString();
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

  Future<void> retry(Track track) async {
    await _api.retryTrack(track.id);
    await load(silent: true);
  }

  Future<void> remove(Track track) async {
    await _api.deleteTrack(track.id);
    await load(silent: true);
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
