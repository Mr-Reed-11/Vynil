import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const MethodChannel _installerChannel = MethodChannel('vynil/installer');

/// Baixa o APK (com progresso) para um arquivo temporário e abre o instalador
/// do Android. Requer a permissão REQUEST_INSTALL_PACKAGES no manifest e que o
/// usuário permita "instalar apps desconhecidos" para a origem.
Future<void> downloadAndInstallApk({
  required String url,
  required Map<String, String> headers,
  void Function(double progress)? onProgress,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/vynil-update.apk');

  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(headers);
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Falha ao baixar o APK (HTTP ${response.statusCode}).');
    }

    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    }
    await sink.close();
  } finally {
    client.close();
  }

  // Abre o instalador do Android via intent nativa (FileProvider). Evita o
  // plugin open_filex, que falhava ao registrar no AGP 9 (MissingPluginException).
  try {
    final ok = await _installerChannel.invokeMethod<bool>(
      'installApk',
      {'path': file.path},
    );
    if (ok != true) {
      throw Exception('Não foi possível abrir o instalador.');
    }
  } on PlatformException catch (e) {
    throw Exception('Não foi possível abrir o instalador: ${e.message}');
  }
}
