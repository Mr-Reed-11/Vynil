import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/library_screen.dart';

class MusicServerApp extends StatelessWidget {
  const MusicServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Server',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LibraryScreen(),
    );
  }
}
