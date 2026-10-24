import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../data/music_api.dart';

/// Autenticação (login/cadastro) + configuração do servidor, persistidos.
class AuthController extends ChangeNotifier {
  AuthController(this._api, this._prefs);

  final MusicApi _api;
  final SharedPreferences _prefs;

  static const _kServerUrl = 'server_url';
  static const _kToken = 'auth_token';
  static const _kUsername = 'auth_username';
  static const _kUserId = 'auth_user_id';

  String _username = '';
  String _userId = '';
  bool _busy = false;
  String? _error;
  /// true após cadastro que ficou pendente de aprovação.
  bool _pending = false;
  String? _info;

  String get serverUrl => _api.baseUrl;
  String get username => _username;
  String get userId => _userId;
  bool get isAuthenticated => _api.token.isNotEmpty;
  bool get busy => _busy;
  String? get error => _error;
  bool get pending => _pending;
  String? get info => _info;

  /// Disparado quando o usuário autentica (login/cadastro). Usado no boot
  /// para recarregar biblioteca e reinicializar o armazenamento offline.
  void Function()? onAuthenticated;

  /// Carrega prefs e aplica na API; registra o auto-logout em 401.
  static Future<AuthController> load(MusicApi api) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kServerUrl);
    final token = prefs.getString(_kToken);
    api.configure(
      baseUrl: (url != null && url.trim().isNotEmpty)
          ? url
          : AppConfig.apiBaseUrl,
      token: token ?? '',
    );
    final controller = AuthController(api, prefs);
    controller._username = prefs.getString(_kUsername) ?? '';
    controller._userId = prefs.getString(_kUserId) ?? '';
    api.onUnauthorized = controller._onUnauthorized;
    return controller;
  }

  Future<void> setServerUrl(String url) async {
    _api.configure(baseUrl: url);
    await _prefs.setString(_kServerUrl, _api.baseUrl);
    notifyListeners();
  }

  Future<bool> login(String username, String password) {
    return _auth(() => _api.login(username.trim(), password));
  }

  Future<bool> register(String username, String password, String email) {
    return _auth(() => _api.register(username.trim(), password, email));
  }

  Future<bool> _auth(Future<AuthResult> Function() action) async {
    _busy = true;
    _error = null;
    _info = null;
    _pending = false;
    notifyListeners();
    try {
      final result = await action();
      if (result.pending) {
        // Cadastro em fila de aprovação: não loga, mostra a espera.
        _pending = true;
        _info = result.message ?? 'Cadastro enviado. Aguarde a aprovação.';
        _busy = false;
        notifyListeners();
        return true;
      }
      _api.configure(token: result.token);
      _username = result.username;
      _userId = result.userId;
      await _prefs.setString(_kToken, result.token);
      await _prefs.setString(_kUsername, result.username);
      await _prefs.setString(_kUserId, result.userId);
      _busy = false;
      notifyListeners();
      onAuthenticated?.call();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      _busy = false;
      notifyListeners();
      return false;
    } catch (error) {
      _error = error.toString();
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _api.configure(token: '');
    _username = '';
    _userId = '';
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUsername);
    await _prefs.remove(_kUserId);
    notifyListeners();
  }

  void _onUnauthorized() {
    // Token expirou/ inválido: desloga.
    if (isAuthenticated) {
      logout();
    }
  }
}
