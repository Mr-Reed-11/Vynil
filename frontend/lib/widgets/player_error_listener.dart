import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';

/// Mostra a mensagem COMPLETA de erro de reprodução num SnackBar (a player bar
/// só mostra truncada). Serve como "log" visível para diagnóstico.
class PlayerErrorListener extends StatefulWidget {
  const PlayerErrorListener({super.key, required this.child});

  final Widget child;

  @override
  State<PlayerErrorListener> createState() => _PlayerErrorListenerState();
}

class _PlayerErrorListenerState extends State<PlayerErrorListener> {
  String? _lastShown;

  @override
  Widget build(BuildContext context) {
    final error = context.select<PlayerController, String?>((p) => p.error);

    if (error == null) {
      _lastShown = null;
    } else if (error != _lastShown) {
      _lastShown = error;
      if (kDebugMode) debugPrint('[Vynil] erro de reprodução: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(error),
              duration: const Duration(seconds: 12),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'OK',
                onPressed: messenger.hideCurrentSnackBar,
              ),
            ),
          );
      });
    }

    return widget.child;
  }
}
