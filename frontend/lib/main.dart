import 'dart:async';

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
import 'controllers/update_controller.dart';
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

  final offlineStore = OfflineStore();
  final library = LibraryController(offlineStore);
  // App standalone: inicializa o armazenamento local e carrega a biblioteca.
  try {
    await offlineStore.init();
  } catch (error) {
    debugPrint('Falha ao iniciar o armazenamento local: $error');
  }
  unawaited(library.load());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryController>.value(value: library),
        ChangeNotifierProvider(
          create: (_) => PlayerController(offlineStore),
        ),
        ChangeNotifierProvider(
          create: (_) => DownloadController(offlineStore),
        ),
        ChangeNotifierProvider(create: (_) => UpdateController()),
      ],
      child: const MusicServerApp(),
    ),
  );
}
