import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/offline_store.dart';
import '../data/track.dart';

/// Biblioteca 100% local (sem backend): lista as faixas baixadas no aparelho.
class LibraryController extends ChangeNotifier {
  LibraryController(this._store);

  final OfflineStore _store;

  List<Track> _tracks = const [];
  bool _loading = false;
  String? _error;
  String _query = '';
  Timer? _searchTimer;
  bool _disposed = false;

  List<Track> get tracks => _tracks;
  bool get loading => _loading;
  String? get error => _error;
  String get query => _query;

  /// Mantido por compatibilidade com a UI; tudo é local, então nada fica
  /// "indisponível offline".
  bool get offline => false;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      _notify();
    }
    try {
      await _store.init();
      _tracks = _applyQuery(_store.tracks);
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void search(String value) {
    _query = value;
    _searchTimer?.cancel();
    _searchTimer =
        Timer(const Duration(milliseconds: 250), () => load(silent: true));
  }

  /// Baixa um vídeo do YouTube direto no dispositivo e atualiza a lista.
  Future<Track> downloadFromYoutube(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final track = await _store.downloadFromYoutube(url, onProgress: onProgress);
    await load(silent: true);
    return track;
  }

  Future<void> remove(Track track) async {
    await _store.remove(track.id);
    await load(silent: true);
  }

  List<Track> _applyQuery(List<Track> tracks) {
    final sorted = [...tracks]
      ..sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return sorted;
    return sorted
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }
}
