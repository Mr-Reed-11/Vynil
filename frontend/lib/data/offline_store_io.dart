import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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

  /// Inicializa o armazenamento local. Sem backend/usuários, há uma única
  /// biblioteca (namespace `_default`).
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
        // Só conta como baixada se o arquivo de áudio realmente existe.
        if (_audioFile(track.id) != null) {
          _index[track.id] = track;
        }
      }
    } catch (_) {
      // Índice corrompido: ignora (começa vazio).
    }
  }

  Future<void> _saveIndex() async {
    final list = _index.values.map((t) => t.toJson()).toList();
    await _indexFile.writeAsString(jsonEncode(list));
  }

  Set<String> get downloadedIds => _index.keys.toSet();
  List<Track> get tracks => _index.values.toList(growable: false);

  bool isDownloaded(String id) => _index.containsKey(id);

  /// Resolve o arquivo de áudio local (qualquer container suportado).
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

  /// Baixa um vídeo do YouTube DIRETO no dispositivo, usando youtube_explode.
  /// Salva o áudio + capa e registra a faixa como `localOnly`.
  ///
  /// Para evitar o rate limiting do YouTube (RequestLimitExceededException),
  /// NÃO usamos a página `/watch` (fortemente bloqueada): os metadados vêm do
  /// oEmbed e o manifesto de streams vem dos clients de API mobile/VR
  /// (endpoint `youtubei/v1/player`), com `requireWatchPage: false`.
  Future<Track> downloadFromYoutube(
    String videoUrl, {
    void Function(double progress)? onProgress,
  }) async {
    await _ensureBase();
    final yt = YoutubeExplode();
    try {
      final videoId = VideoId.fromString(videoUrl);
      final id = 'local-${videoId.value}';

      final meta = await _fetchMeta(yt, videoId);

      // Manifesto via clients de API (sem a página /watch). Driblam o rate
      // limit e não precisam decifrar assinatura.
      final manifest = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.ios,
          YoutubeApiClient.android,
          YoutubeApiClient.tv,
        ],
        requireWatchPage: false,
      );
      final audio = manifest.audioOnly.withHighestBitrate();
      final ext = audio.container.name;

      final file = File('$_musicDir/$id.$ext');
      final tmp = File('${file.path}.part');
      final total = audio.size.totalBytes;

      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in yt.videos.streamsClient.get(audio)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }

      // Limpa versões antigas (outras extensões) do mesmo id e efetiva.
      for (final e in _audioExts) {
        if (e == ext) continue;
        final old = File('$_musicDir/$id.$e');
        if (await old.exists()) await old.delete();
      }
      await tmp.rename(file.path);

      // Capa (best-effort): tenta maxres e cai para hqdefault.
      await _saveCover(id, videoId.value);

      final track = Track(
        id: id,
        youtubeId: videoId.value,
        url: videoUrl,
        title: meta.title,
        artist: meta.author,
        durationSeconds: meta.durationSeconds,
        status: TrackStatus.ready,
        progress: 100,
        thumbnailUrl: 'https://i.ytimg.com/vi/${videoId.value}/hqdefault.jpg',
        sizeBytes: total,
        localOnly: true,
      );
      _index[id] = track;
      await _saveIndex();
      return track;
    } finally {
      yt.close();
    }
  }

  /// Metadados (título/artista/duração) sem bater na página `/watch`.
  /// 1) oEmbed (leve, não rate-limitado); 2) best-effort via watch page só
  /// para pegar a duração — se falhar (rate limit), seguimos sem ela.
  Future<_Meta> _fetchMeta(YoutubeExplode yt, VideoId videoId) async {
    var title = videoId.value;
    var author = '';
    var durationSeconds = 0;

    try {
      final res = await http.get(Uri.parse(
        'https://www.youtube.com/oembed?format=json'
        '&url=https://www.youtube.com/watch?v=${videoId.value}',
      ));
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final t = (j['title'] as String?)?.trim();
        if (t != null && t.isNotEmpty) title = t;
        author = (j['author_name'] as String? ?? '')
            .replaceAll(RegExp(r' - Topic$'), '')
            .trim();
      }
    } catch (_) {}

    try {
      final video = await yt.videos.get(videoId);
      if (video.title.isNotEmpty) title = video.title;
      if (video.author.isNotEmpty) {
        author = video.author.replaceAll(RegExp(r' - Topic$'), '').trim();
      }
      durationSeconds = video.duration?.inSeconds ?? 0;
    } catch (_) {
      // Rate limit / watch page bloqueada: fica com os dados do oEmbed.
    }

    return _Meta(title: title, author: author, durationSeconds: durationSeconds);
  }

  Future<void> _saveCover(String id, String videoId) async {
    for (final name in ['maxresdefault', 'hqdefault']) {
      try {
        final res =
            await http.get(Uri.parse('https://i.ytimg.com/vi/$videoId/$name.jpg'));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await File('$_coversDir/$id.jpg').writeAsBytes(res.bodyBytes);
          return;
        }
      } catch (_) {}
    }
  }
}

class _Meta {
  _Meta({
    required this.title,
    required this.author,
    required this.durationSeconds,
  });

  final String title;
  final String author;
  final int durationSeconds;
}
