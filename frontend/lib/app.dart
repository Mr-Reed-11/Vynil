import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
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
      home: Consumer<AuthController>(
        builder: (context, auth, _) {
          if (!auth.isAuthenticated) return const AuthScreen();
          return const UpdateGate(
            child: ShareListener(
              child: PlayerErrorListener(child: LibraryScreen()),
            ),
          );
        },
      ),
    );
  }
}
