import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/library_screen.dart';
import 'widgets/player_error_listener.dart';
import 'widgets/share_listener.dart';
import 'widgets/update_gate.dart';

class MusicServerApp extends StatelessWidget {
  const MusicServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Server',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const UpdateGate(
        child: ShareListener(
          child: PlayerErrorListener(child: LibraryScreen()),
        ),
      ),
    );
  }
}
