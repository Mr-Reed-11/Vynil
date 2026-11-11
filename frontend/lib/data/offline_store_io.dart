import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'track.dart';

const _audioExts = ['mp3', 'm4a', 'webm', 'opus', 'mp4', 'ogg'];

/// Armazena faixas baixadas no dispositivo (áudio + capa) e um índice de
/// metadados em JSON, permitindo tocar e navegar 100% offline.
///
/// Layout em getApplicationDocumentsDirectory()/vynil/_default:
///   `music/<id>.<ext>`
///   `covers/<id>.jpg`
///   `library.json`  (lista de Track em JSON)
class OfflineStore {
  Directory? _base;
  final Map<String, Track> _index = {};

  /// Inicializa o armazenamento local. Biblioteca única (namespace `_default`).
  Future<void> init([String userId = '_default']) async {
    if (_base != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final base = Directory('${dir.path}/vynil/_default');
    await Directory('${base.path}/music').create(recursive: true);
    await Directory('${base.path}/covers').create(recursive: true);
    _base = base;
    await _loadIndex();
  }

  Future<void> _ensureBase() async {
    if (_base == null) await init();
  }

  String get _musicDir => '${_base!.path}/music';
  String get _coversDir => '${_base!.path}/covers';
  File get _indexFile => File('${_base!.path}/library.json');

  Future<void> _loadIndex() async {
    try {
      if (!await _indexFile.exists()) return;
      final raw = jsonDecode(await _indexFile.readAsString());
      if (raw is! List) return;
      _index.clear();
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final track = Track.fromJson(item);
        if (_audioFile(track.id) != null) {
          _index[track.id] = track;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveIndex() async {
    final list = _index.values.map((t) => t.toJson()).toList();
    await _indexFile.writeAsString(jsonEncode(list));
  }

  Set<String> get downloadedIds => _index.keys.toSet();
  List<Track> get tracks => _index.values.toList(growable: false);

  bool isDownloaded(String id) => _index.containsKey(id);

  File? _audioFile(String id) {
    if (_base == null) return null;
    for (final ext in _audioExts) {
      final f = File('$_musicDir/$id.$ext');
      if (f.existsSync()) return f;
    }
    return null;
  }

  String? audioPath(String id) =>
      isDownloaded(id) ? _audioFile(id)?.path : null;

  String? coverPath(String id) {
    final path = '$_coversDir/$id.jpg';
    return File(path).existsSync() ? path : null;
  }

  Future<void> setDurationIfMissing(String id, int seconds) async {
    final t = _index[id];
    if (t == null || seconds <= 0 || t.durationSeconds > 0) return;
    _index[id] = t.copyWith(durationSeconds: seconds);
    await _saveIndex();
  }

  Future<void> remove(String id) async {
    await _ensureBase();
    for (final ext in _audioExts) {
      try {
        final f = File('$_musicDir/$id.$ext');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    try {
      await File('$_coversDir/$id.jpg').delete();
    } catch (_) {}
    _index.remove(id);
    await _saveIndex();
  }

  /// Baixa o MP3 de um link do YouTube a partir do servidor de download (que
  /// usa yt-dlp) e salva no dispositivo. O app sozinho não extrai de forma
  /// confiável (o YouTube bloqueia), por isso o download passa pelo servidor.
  Future<Track> downloadFromYoutube(
    String videoUrl, {
    required String serverUrl,
    String serverKey = '',
    void Function(double progress)? onProgress,
  }) async {
    await _ensureBase();

    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw Exception('Configure o servidor de download nas Configurações.');
    }

    final uri = Uri.parse('$base/download').replace(queryParameters: {
      'url': videoUrl,
      if (serverKey.trim().isNotEmpty) 'key': serverKey.trim(),
    });

    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 200));

      if (response.statusCode == 401) {
        throw Exception('Chave do servidor inválida (confira nas Configurações).');
      }
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('Servidor: ${_errorFrom(body, response.statusCode)}');
      }

      final h = response.headers;
      final videoId = (h['x-video-id']?.trim().isNotEmpty ?? false)
          ? h['x-video-id']!.trim()
          : (_extractVideoId(videoUrl) ?? 'desconhecido');
      final id = 'local-$videoId';
      final title = _decode(h['x-title']) ?? videoId;
      final artist = _decode(h['x-artist']) ?? '';
      final duration = int.tryParse(h['x-duration'] ?? '') ?? 0;
      final total = int.tryParse(h['content-length'] ?? '') ??
          response.contentLength ??
          0;

      final file = File('$_musicDir/$id.mp3');
      final tmp = File('${file.path}.part');
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }

      // Limpa versões antigas (outras extensões) do mesmo id e efetiva.
      for (final e in _audioExts) {
        if (e == 'mp3') continue;
        final old = File('$_musicDir/$id.$e');
        if (await old.exists()) await old.delete();
      }
      await tmp.rename(file.path);

      await _saveCover(id, videoId);

      final track = Track(
        id: id,
        youtubeId: videoId,
        url: videoUrl,
        title: title,
        artist: artist,
        durationSeconds: duration,
        status: TrackStatus.ready,
        progress: 100,
        thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        sizeBytes: total > 0 ? total : received,
        localOnly: true,
      );
      _index[id] = track;
      await _saveIndex();
      return track;
    } finally {
      client.close();
    }
  }

  Future<void> _saveCover(String id, String videoId) async {
    for (final name in ['maxresdefault', 'hqdefault']) {
      try {
        final res = await http
            .get(Uri.parse('https://i.ytimg.com/vi/$videoId/$name.jpg'));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await File('$_coversDir/$id.jpg').writeAsBytes(res.bodyBytes);
          return;
        }
      } catch (_) {}
    }
  }

  String _errorFrom(String body, int status) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    return 'erro HTTP $status';
  }

  String? _decode(String? v) {
    if (v == null || v.isEmpty) return null;
    try {
      return Uri.decodeComponent(v);
    } catch (_) {
      return v;
    }
  }

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final v = uri.queryParameters['v'];
    if (v != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v)) return v;
    final m = RegExp(r'[A-Za-z0-9_-]{11}').firstMatch(url);
    return m?.group(0);
  }
}
