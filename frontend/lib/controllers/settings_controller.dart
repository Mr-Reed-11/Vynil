import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../data/music_api.dart';

/// Guarda e aplica as configurações de conexão (URL do servidor e API key),
/// persistidas em shared_preferences para sobreviver a reinícios.
class SettingsController extends ChangeNotifier {
  SettingsController(this._api, this._prefs);

  final MusicApi _api;
  final SharedPreferences _prefs;

  static const _kServerUrl = 'server_url';
  static const _kApiKey = 'api_key';

  String get serverUrl => _api.baseUrl;
  String get apiKey => _api.apiKey;

  /// Lê as preferências salvas e aplica na API. Chamado no boot.
  static Future<SettingsController> load(MusicApi api) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kServerUrl);
    final key = prefs.getString(_kApiKey);
    api.configure(
      baseUrl: (url != null && url.trim().isNotEmpty)
          ? url
          : AppConfig.apiBaseUrl,
      apiKey: key ?? AppConfig.apiKey,
    );
    return SettingsController(api, prefs);
  }

  Future<void> save({required String serverUrl, required String apiKey}) async {
    _api.configure(baseUrl: serverUrl, apiKey: apiKey);
    await _prefs.setString(_kServerUrl, _api.baseUrl);
    await _prefs.setString(_kApiKey, _api.apiKey);
    notifyListeners();
  }
}
