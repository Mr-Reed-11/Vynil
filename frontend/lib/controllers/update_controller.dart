import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/apk_installer.dart';
import '../data/music_api.dart';

/// Checa a versão publicada no backend e, se houver uma nova, coordena o
/// download + instalação do APK (sideload). Compara pelo buildNumber.
class UpdateController extends ChangeNotifier {
  UpdateController(this._api);

  final MusicApi _api;

  AppVersionInfo? _latest;
  String _currentVersion = '';
  int _currentBuild = 0;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  AppVersionInfo? get latest => _latest;
  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;
  bool get checking => _checking;
  bool get downloading => _downloading;
  double get progress => _progress;
  String? get error => _error;

  bool get updateAvailable =>
      _latest != null &&
      _currentBuild > 0 &&
      _latest!.buildNumber > _currentBuild;

  /// Instalação de APK só faz sentido em plataforma com dart:io (Android).
  bool get canInstall => !kIsWeb;

  Future<void> _ensureCurrent() async {
    if (_currentBuild > 0) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // package_info pode falhar em ambientes de teste; mantém zeros.
    }
  }

  /// Retorna true se há atualização. [silent] evita notificar no começo.
  Future<bool> check({bool silent = true}) async {
    await _ensureCurrent();
    _checking = true;
    _error = null;
    if (!silent) notifyListeners();
    try {
      _latest = await _api.fetchVersion();
    } catch (error) {
      _error = error.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
    return updateAvailable;
  }

  Future<void> downloadAndInstall() async {
    final url = _api.absoluteUrl(_latest?.downloadUrl);
    if (url == null) {
      _error = 'Nenhum APK disponível para download no servidor.';
      notifyListeners();
      return;
    }
    _downloading = true;
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      await downloadAndInstallApk(
        url: url,
        headers: _api.authHeaders,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }
}
