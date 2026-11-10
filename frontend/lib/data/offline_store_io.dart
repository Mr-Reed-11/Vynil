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
  Future<Track> downloadFromYoutube(
    String videoUrl, {
    void Function(double progress)? onProgress,
  }) async {
    await _ensureBase();
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoUrl);
      final id = 'local-${video.id.value}';
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
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

      // Capa (best-effort).
      final thumbUrl = video.thumbnails.highResUrl;
      try {
        final cover = await http.get(Uri.parse(thumbUrl));
        if (cover.statusCode == 200) {
          await File('$_coversDir/$id.jpg').writeAsBytes(cover.bodyBytes);
        }
      } catch (_) {}

      final track = Track(
        id: id,
        youtubeId: video.id.value,
        url: videoUrl,
        title: video.title,
        artist: video.author,
        durationSeconds: video.duration?.inSeconds ?? 0,
        status: TrackStatus.ready,
        progress: 100,
        thumbnailUrl: thumbUrl,
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
}
