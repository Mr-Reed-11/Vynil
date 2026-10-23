import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'music_api.dart';
import 'track.dart';

/// Armazena faixas baixadas no dispositivo (áudio + capa) e um índice de
/// metadados em JSON, permitindo tocar e navegar offline.
///
/// Layout em getApplicationDocumentsDirectory()/vynil:
///   `music/<id>.mp3`
///   `covers/<id>.jpg`
///   `library.json`  (lista de Track em JSON)
class OfflineStore {
  Directory? _base;
  final Map<String, Track> _index = {};
  final List<Track> _catalog = [];

  Future<void> init() async {
    if (_base != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final base = Directory('${dir.path}/vynil');
    await Directory('${base.path}/music').create(recursive: true);
    await Directory('${base.path}/covers').create(recursive: true);
    _base = base;
    await _loadIndex();
    await _loadCatalog();
  }

  String get _musicDir => '${_base!.path}/music';
  String get _coversDir => '${_base!.path}/covers';
  File get _indexFile => File('${_base!.path}/library.json');
  File get _catalogFile => File('${_base!.path}/catalog.json');

  /// Catálogo completo (última biblioteca vista no servidor), usado para
  /// mostrar TODAS as faixas quando offline.
  List<Track> get catalog => List.unmodifiable(_catalog);

  Future<void> saveCatalog(List<Track> tracks) async {
    await init();
    _catalog
      ..clear()
      ..addAll(tracks);
    try {
      await _catalogFile
          .writeAsString(jsonEncode(tracks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadCatalog() async {
    try {
      if (!await _catalogFile.exists()) return;
      final raw = jsonDecode(await _catalogFile.readAsString());
      if (raw is! List) return;
      _catalog.clear();
      for (final item in raw) {
        if (item is Map<String, dynamic>) _catalog.add(Track.fromJson(item));
      }
    } catch (_) {}
  }

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
        if (File('$_musicDir/${track.id}.mp3').existsSync()) {
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

  String? audioPath(String id) =>
      isDownloaded(id) ? '$_musicDir/$id.mp3' : null;

  String? coverPath(String id) {
    final path = '$_coversDir/$id.jpg';
    return File(path).existsSync() ? path : null;
  }

  Future<void> download({
    required Track track,
    required MusicApi api,
    void Function(double progress)? onProgress,
  }) async {
    await init();
    final streamUrl = api.absoluteUrl(track.streamUrl);
    if (streamUrl == null) {
      throw Exception('Faixa ainda não está pronta para download.');
    }

    final audioFile = File('$_musicDir/${track.id}.mp3');
    final tmp = File('${audioFile.path}.part');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(streamUrl))
        ..headers.addAll(api.authHeaders);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Falha ao baixar (HTTP ${response.statusCode}).');
      }
      final total = response.contentLength ?? 0;
      final sink = tmp.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.close();
      await tmp.rename(audioFile.path);

      // Capa (best-effort; falha não impede o áudio).
      final coverUrl = api.absoluteUrl(track.coverUrl);
      if (coverUrl != null) {
        try {
          final cover =
              await client.get(Uri.parse(coverUrl), headers: api.authHeaders);
          if (cover.statusCode == 200) {
            await File('$_coversDir/${track.id}.jpg')
                .writeAsBytes(cover.bodyBytes);
          }
        } catch (_) {}
      }
    } catch (e) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }

    _index[track.id] = track;
    await _saveIndex();
  }

  Future<void> remove(String id) async {
    await init();
    try {
      await File('$_musicDir/$id.mp3').delete();
    } catch (_) {}
    try {
      await File('$_coversDir/$id.jpg').delete();
    } catch (_) {}
    _index.remove(id);
    await _saveIndex();
  }
}
