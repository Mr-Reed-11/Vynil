/// Stub para plataformas sem dart:io (web): instalar APK não se aplica.
Future<void> downloadAndInstallApk({
  required String url,
  required Map<String, String> headers,
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError('Instalação de APK disponível apenas no Android.');
}
