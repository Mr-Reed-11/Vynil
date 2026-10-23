import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../controllers/update_controller.dart';
import '../core/diagnostics.dart';

/// Envolve a home e, na primeira abertura, checa se há atualização.
/// Se houver, mostra o diálogo uma vez por sessão.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    // Android 13+: pede a permissão de notificação (necessária para a
    // bandeja de mídia aparecer).
    if (!kIsWeb) {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }

    if (!mounted) return;

    // Se a notificação de mídia falhou ao iniciar, avisa (o player segue
    // funcionando sem a bandeja). Ajuda a diagnosticar.
    if (backgroundInitError != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Notificação de mídia indisponível: '
              '$backgroundInitError'),
          duration: const Duration(seconds: 10),
        ),
      );
    }

    final update = context.read<UpdateController>();
    final hasUpdate = await update.check(silent: true);
    if (!mounted || _prompted || !hasUpdate) return;
    _prompted = true;
    await showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Diálogo de atualização, reutilizado pelo gate e pela tela de Configurações.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const UpdateDialog(),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<UpdateController>(
      builder: (context, update, _) {
        final latest = update.latest;
        final mandatory = latest?.mandatory ?? false;

        return PopScope(
          canPop: !mandatory && !update.downloading,
          child: AlertDialog(
            icon: const Icon(Icons.system_update_rounded),
            title: Text('Atualização disponível${latest != null ? ' • ${latest.version}' : ''}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Você está na versão ${update.currentVersion} (build '
                  '${update.currentBuild}).',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                if (latest?.notes != null) ...[
                  const SizedBox(height: 12),
                  Text('Novidades:',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(latest!.notes!),
                ],
                if (!update.canInstall) ...[
                  const SizedBox(height: 12),
                  Text(
                    'A instalação automática só funciona no app Android. '
                    'Baixe o novo APK manualmente.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
                if (update.downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: update.progress > 0 ? update.progress : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Baixando... ${(update.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
                if (update.error != null) ...[
                  const SizedBox(height: 12),
                  Text(update.error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
            actions: [
              if (!mandatory && !update.downloading)
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Agora não'),
                ),
              FilledButton.icon(
                onPressed: (update.downloading || !update.canInstall)
                    ? null
                    : () => update.downloadAndInstall(),
                icon: const Icon(Icons.download_rounded),
                label: Text(update.downloading ? 'Baixando...' : 'Baixar e instalar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
