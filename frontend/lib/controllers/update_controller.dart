import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/apk_installer.dart';

/// Informações de um release publicado no GitHub.
class ReleaseInfo {
  ReleaseInfo({
    required this.version,
    this.downloadUrl,
    this.notes,
  });

  final String version;
  final String? downloadUrl;
  final String? notes;

  /// Releases do GitHub não têm o conceito de "obrigatório".
  bool get mandatory => false;
}

/// Checa o último release público no GitHub Releases e, se a versão for maior
/// que a instalada, baixa e instala o APK (sideload). Sem backend.
class UpdateController extends ChangeNotifier {
  UpdateController();

  /// Repositório público que hospeda os APKs em Releases.
  static const String _repo = 'Mr-Reed-11/Vynil';
  static final Uri _latestUrl =
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest');

  ReleaseInfo? _latest;
  String _currentVersion = '';
  int _currentBuild = 0;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  ReleaseInfo? get latest => _latest;
  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;
  bool get checking => _checking;
  bool get downloading => _downloading;
  double get progress => _progress;
  String? get error => _error;

  bool get updateAvailable =>
      _latest != null &&
      _currentVersion.isNotEmpty &&
      _compareVersions(_latest!.version, _currentVersion) > 0;

  /// Instalação de APK só faz sentido em plataforma com dart:io (Android).
  bool get canInstall => !kIsWeb;

  Future<void> _ensureCurrent() async {
    if (_currentVersion.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // package_info pode falhar em ambientes de teste.
    }
  }

  /// Retorna true se há atualização. [silent] evita notificar no começo.
  Future<bool> check({bool silent = true}) async {
    await _ensureCurrent();
    _checking = true;
    _error = null;
    if (!silent) notifyListeners();
    try {
      final response = await http.get(
        _latestUrl,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Vynil-App',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        // Nenhum release publicado ainda.
        _latest = null;
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        _latest = _parseRelease(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        );
      } else {
        _error = 'Falha ao checar atualizações (HTTP ${response.statusCode}).';
      }
    } catch (error) {
      _error = 'Não foi possível checar atualizações: $error';
    } finally {
      _checking = false;
      notifyListeners();
    }
    return updateAvailable;
  }

  ReleaseInfo _parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = tag.replaceFirst(RegExp(r'^v'), '');
    final notes = (json['body'] as String?)?.trim();

    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    String? apkUrl;
    // Prefere o APK arm64 (o build padrão do dispositivo).
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') && name.contains('arm64')) {
        apkUrl = a['browser_download_url'] as String?;
        break;
      }
    }
    apkUrl ??= assets
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (a) =>
              (a?['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => null,
        )?['browser_download_url'] as String?;

    return ReleaseInfo(
      version: version,
      downloadUrl: apkUrl,
      notes: notes != null && notes.isNotEmpty ? notes : null,
    );
  }

  Future<void> downloadAndInstall() async {
    final url = _latest?.downloadUrl;
    if (url == null) {
      _error = 'Nenhum APK disponível neste release.';
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
        headers: const {'User-Agent': 'Vynil-App'},
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

  /// Compara "1.4.0" vs "1.10.2" numericamente. >0 se [a] > [b].
  int _compareVersions(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  List<int> _parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();
}
