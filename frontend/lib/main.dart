import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/library_controller.dart';
import 'controllers/player_controller.dart';
import 'core/app_config.dart';
import 'data/music_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicApi>.value(value: api),
        ChangeNotifierProvider(create: (_) => LibraryController(api)..load()),
        ChangeNotifierProvider(create: (_) => PlayerController(api)),
      ],
      child: const MusicServerApp(),
    ),
  );
}
