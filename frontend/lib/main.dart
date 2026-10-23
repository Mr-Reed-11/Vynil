import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_platform_interface/method_channel_just_audio.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/diagnostics.dart';
import 'controllers/download_controller.dart';
import 'controllers/library_controller.dart';
import 'controllers/player_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/update_controller.dart';
import 'core/app_config.dart';
import 'data/music_api.dart';
import 'data/offline_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notificação de mídia + controles na bandeja/lockscreen (Android/iOS).
  if (!kIsWeb) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.reed.musicserver.channel.audio',
        androidNotificationChannelName: 'Vynil',
        androidNotificationOngoing: true,
      );
    } catch (error, stack) {
      // Se a notificação de mídia falhar ao iniciar, NÃO deixamos a reprodução
      // quebrar: revertemos o override da plataforma para o player padrão.
      backgroundInitError = '$error';
      debugPrint('Falha ao iniciar a notificação de mídia: $error\n$stack');
      try {
        JustAudioPlatform.instance = MethodChannelJustAudio();
      } catch (_) {}
    }
  }

  // Obs: NÃO configuramos o AudioSession manualmente — o audio_service (base
  // do just_audio_background) gerencia a sessão e a media session que aciona
  // a notificação. Configurar por cima a desfazia (notificação não aparecia).

  final api = MusicApi(
    baseUrl: AppConfig.apiBaseUrl,
    apiKey: AppConfig.apiKey,
  );
  final settings = await SettingsController.load(api);

  final offlineStore = OfflineStore();
  try {
    await offlineStore.init();
  } catch (error) {
    debugPrint('Falha ao iniciar o armazenamento offline: $error');
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicApi>.value(value: api),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => LibraryController(api, offlineStore)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerController(api, offlineStore),
        ),
        ChangeNotifierProvider(
          create: (_) => DownloadController(api, offlineStore)..init(),
        ),
        ChangeNotifierProvider(create: (_) => UpdateController(api)),
      ],
      child: const MusicServerApp(),
    ),
  );
}
