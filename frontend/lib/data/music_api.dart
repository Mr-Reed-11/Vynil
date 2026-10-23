import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'track.dart';

class AppVersionInfo {
  AppVersionInfo({
    required this.version,
    required this.buildNumber,
    this.downloadUrl,
    this.notes,
    this.mandatory = false,
  });

  final String version;
  final int buildNumber;
  final String? downloadUrl;
  final String? notes;
  final bool mandatory;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    final notes = (json['notes'] as String?)?.trim();
    return AppVersionInfo(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      downloadUrl: json['downloadUrl'] as String?,
      notes: notes != null && notes.isNotEmpty ? notes : null,
      mandatory: json['mandatory'] == true,
    );
  }
}

class PlaylistResult {
  PlaylistResult({
    required this.playlistTitle,
    required this.total,
    required this.added,
    required this.skipped,
  });

  final String playlistTitle;
  final int total;
  final int added;
  final int skipped;
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Cliente HTTP do music-server.
class MusicApi {
  MusicApi({
    required String baseUrl,
    String apiKey = '',
    http.Client? client,
  })  : baseUrl = _normalizeBase(baseUrl),
        apiKey = apiKey.trim(),
        _client = client ?? http.Client();

  /// URL do servidor; pode ser alterada em runtime pela tela de configuração.
  String baseUrl;
  String apiKey;
  final http.Client _client;

  static String _normalizeBase(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  /// Atualiza servidor/chave em runtime (sem recriar os controllers).
  void configure({required String baseUrl, required String apiKey}) {
    this.baseUrl = _normalizeBase(baseUrl);
    this.apiKey = apiKey.trim();
  }

  Map<String, String> get authHeaders =>
      apiKey.isEmpty ? const {} : {'x-api-key': apiKey};

  /// URL de capa para a notificação de mídia: o carregador de artwork do
  /// sistema não envia headers, então a API key vai na query (o guard aceita
  /// ?api_key=...).
  String? artworkUrl(String? coverUrl) {
    final absolute = absoluteUrl(coverUrl);
    if (absolute == null) return null;
    if (apiKey.isEmpty) return absolute;
    final sep = absolute.contains('?') ? '&' : '?';
    return '$absolute${sep}api_key=${Uri.encodeQueryComponent(apiKey)}';
  }

  /// Converte `streamUrl`/`coverUrl` relativos em URL absoluta.
  String? absoluteUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null && uri.hasScheme) {
      return pathOrUrl;
    }
    return Uri.parse(baseUrl).resolve(pathOrUrl).toString();
  }

  Future<List<Track>> fetchTracks({String? query, TrackStatus? status}) async {
    final params = <String, String>{
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (status != null) 'status': status.name,
    };
    final response = await _send(
      () => _client.get(
        _uri('/api/tracks', params),
        headers: authHeaders,
      ),
      // Timeout curto: offline, cai rápido para o catálogo em cache.
      timeout: const Duration(seconds: 8),
    );

    final data = _handle(response) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<PlaylistResult> addPlaylist(String url) async {
    final response = await _send(
      () => _client.post(
        _uri('/api/tracks/playlist'),
        headers: {
          ...authHeaders,
          'content-type': 'application/json',
        },
        body: jsonEncode({'url': url}),
      ),
      timeout: const Duration(seconds: 180),
    );

    final data = _handle(response) as Map<String, dynamic>;
    return PlaylistResult(
      playlistTitle: data['playlistTitle'] as String? ?? 'Playlist',
      total: (data['total'] as num?)?.toInt() ?? 0,
      added: (data['added'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Track> addTrack(String url) async {
    final response = await _send(
      () => _client.post(
        _uri('/api/tracks'),
        headers: {
          ...authHeaders,
          'content-type': 'application/json',
        },
        body: jsonEncode({'url': url}),
      ),
      timeout: const Duration(seconds: 120),
    );

    return Track.fromJson(_handle(response) as Map<String, dynamic>);
  }

  Future<Track> retryTrack(String id) async {
    final response = await _send(
      () => _client.post(
        _uri('/api/tracks/$id/retry'),
        headers: authHeaders,
      ),
    );
    return Track.fromJson(_handle(response) as Map<String, dynamic>);
  }

  Future<AppVersionInfo> fetchVersion() async {
    final response = await _send(
      () => _client.get(_uri('/api/app/version'), headers: authHeaders),
    );
    return AppVersionInfo.fromJson(_handle(response) as Map<String, dynamic>);
  }

  Future<void> deleteTrack(String id) async {
    final response = await _send(
      () => _client.delete(
        _uri('/api/tracks/$id'),
        headers: authHeaders,
      ),
    );
    _handle(response);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'O servidor demorou para responder. Tente novamente.');
    } on http.ClientException catch (error) {
      throw ApiException(
        0,
        'Não foi possível conectar em $baseUrl.\n${error.message}',
      );
    }
  }

  dynamic _handle(http.Response response) {
    dynamic decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    var message = 'Erro ${response.statusCode}';
    if (decoded is Map<String, dynamic>) {
      final raw = decoded['message'];
      if (raw is List) {
        message = raw.join('\n');
      } else if (raw != null) {
        message = raw.toString();
      }
    }

    throw ApiException(response.statusCode, message);
  }
}
