import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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

  final result = await OpenFilex.open(
    file.path,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type != ResultType.done) {
    throw Exception('Não foi possível abrir o instalador: ${result.message}');
  }
}
