import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'track.dart';

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
    this.apiKey = '',
    http.Client? client,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  Map<String, String> get authHeaders =>
      apiKey.isEmpty ? const {} : {'x-api-key': apiKey};

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
    );

    final data = _handle(response) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
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
