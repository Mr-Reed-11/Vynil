import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_platform_interface/method_channel_just_audio.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/diagnostics.dart';
import 'controllers/auth_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/library_controller.dart';
import 'controllers/player_controller.dart';
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

  final api = MusicApi(baseUrl: AppConfig.apiBaseUrl);
  final auth = await AuthController.load(api);

  final offlineStore = OfflineStore();
  final library = LibraryController(api, offlineStore);
  // Cada usuário tem seu namespace offline; com token salvo, inicializa já.
  if (auth.isAuthenticated && auth.userId.isNotEmpty) {
    try {
      await offlineStore.init(auth.userId);
    } catch (error) {
      debugPrint('Falha ao iniciar o armazenamento offline: $error');
    }
    library.load();
  }

  auth.onAuthenticated = () {
    // Login/cadastro concluído: troca o namespace offline e recarrega.
    if (auth.userId.isNotEmpty) {
      offlineStore.init(auth.userId).then((_) => library.load());
    } else {
      library.load();
    }
  };

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicApi>.value(value: api),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<LibraryController>.value(value: library),
        ChangeNotifierProvider(
          create: (_) => PlayerController(api, offlineStore),
        ),
        ChangeNotifierProvider(
          create: (_) => DownloadController(api, offlineStore),
        ),
        ChangeNotifierProvider(create: (_) => UpdateController(api)),
      ],
      child: const MusicServerApp(),
    ),
  );
}
