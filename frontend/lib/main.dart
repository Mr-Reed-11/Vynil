import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'app.dart';
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
    } catch (error) {
      debugPrint('Falha ao iniciar a notificação de mídia: $error');
    }
  }

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (error) {
    debugPrint('Não foi possível configurar a sessão de áudio: $error');
  }

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
