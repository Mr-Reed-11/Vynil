import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/offline_store.dart';
import '../data/track.dart';

/// Biblioteca local: lista as faixas salvas no aparelho e dispara o download
/// (que passa pelo servidor de download configurado).
class LibraryController extends ChangeNotifier {
  LibraryController(this._store);

  final OfflineStore _store;

  static const _kServerUrl = 'download_server_url';
  static const _kServerKey = 'download_server_key';

  String _serverUrl = '';
  String _serverKey = '';
  bool _prefsLoaded = false;

  String get serverUrl => _serverUrl;
  String get serverKey => _serverKey;
  bool get hasServer => _serverUrl.trim().isNotEmpty;

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString(_kServerUrl) ?? '';
      _serverKey = prefs.getString(_kServerKey) ?? '';
    } catch (_) {}
    _prefsLoaded = true;
  }

  Future<void> setServer(String url, String key) async {
    _serverUrl = url.trim();
    _serverKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServerUrl, _serverUrl);
      await prefs.setString(_kServerKey, _serverKey);
    } catch (_) {}
    _notify();
  }

  List<Track> _tracks = const [];
  // Downloads em andamento (ou que falharam), exibidos no topo da lista.
  final Map<String, Track> _pending = {};
  bool _loading = false;
  String? _error;
  String _query = '';
  Timer? _searchTimer;
  bool _disposed = false;

  /// Faixas exibidas: downloads em andamento primeiro, depois as salvas.
  List<Track> get tracks {
    if (_pending.isEmpty) return _tracks;
    final pendingIds = _pending.keys.toSet();
    final rest = _tracks.where((t) => !pendingIds.contains(t.id));
    return [..._pending.values, ...rest];
  }

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
      await _loadPrefs();
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

  /// Baixa um vídeo do YouTube direto no dispositivo. A faixa aparece na lista
  /// imediatamente com "Baixando… X%" e vira faixa normal ao concluir (ou
  /// mostra "Erro" se falhar).
  Future<Track> downloadFromYoutube(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final videoId = _extractVideoId(url);
    final tempId = videoId != null
        ? 'local-$videoId'
        : 'pending-${DateTime.now().microsecondsSinceEpoch}';

    _pending[tempId] = Track(
      id: tempId,
      youtubeId: videoId ?? '',
      url: url,
      title: 'Baixando…',
      artist: '',
      durationSeconds: 0,
      status: TrackStatus.downloading,
      progress: 0,
      thumbnailUrl: videoId != null
          ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
          : null,
    );
    _notify();

    try {
      await _loadPrefs();
      final track = await _store.downloadFromYoutube(
        url,
        serverUrl: _serverUrl,
        serverKey: _serverKey,
        onProgress: (p) {
          final cur = _pending[tempId];
          if (cur != null) {
            _pending[tempId] = cur.copyWith(progress: (p * 100).clamp(0, 100));
            _notify();
          }
          onProgress?.call(p);
        },
      );
      _pending.remove(tempId);
      await load(silent: true);
      return track;
    } catch (error) {
      final cur = _pending[tempId];
      if (cur != null) {
        _pending[tempId] = cur.copyWith(
          status: TrackStatus.error,
          title: 'Falha no download',
          error: error.toString(),
        );
        _notify();
      }
      rethrow;
    }
  }

  /// Remove um download que falhou (o item vermelho na lista).
  void dismissFailed(String id) {
    if (_pending.remove(id) != null) _notify();
  }

  Future<void> remove(Track track) async {
    // Item de download que falhou: só tira da lista.
    if (_pending.containsKey(track.id)) {
      dismissFailed(track.id);
      return;
    }
    await _store.remove(track.id);
    await load(silent: true);
  }

  /// Extrai o id de 11 caracteres das formas comuns de URL do YouTube.
  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final v = uri.queryParameters['v'];
    if (v != null && _isVideoId(v)) return v;
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      // youtu.be/<id>, /shorts/<id>, /embed/<id>
      final last = segments.last;
      if (_isVideoId(last)) return last;
    }
    final m = RegExp(r'[A-Za-z0-9_-]{11}').firstMatch(url);
    return m?.group(0);
  }

  bool _isVideoId(String s) => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(s);

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
