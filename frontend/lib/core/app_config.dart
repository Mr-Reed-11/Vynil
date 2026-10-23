import 'package:flutter/foundation.dart';

/// Configuração de ambiente do app.
///
/// A URL padrão aponta para o backend local:
/// - Android Emulator: 10.0.2.2 (o localhost do computador)
/// - Web/Desktop: localhost
/// - Celular físico: use --dart-define=API_BASE_URL=http://SEU_IP:3000
class AppConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _envApiKey = String.fromEnvironment('API_KEY');

  static String get apiBaseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static String get apiKey => _envApiKey;
}
