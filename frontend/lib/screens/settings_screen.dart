import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/library_controller.dart';
import '../controllers/update_controller.dart';
import '../core/theme.dart';
import '../widgets/update_gate.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(
      text: context.read<AuthController>().serverUrl,
    );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthController>();
    final library = context.read<LibraryController>();
    setState(() => _saving = true);

    await auth.setServerUrl(_url.text);
    await library.load();

    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(
      const SnackBar(content: Text('Configurações salvas.')),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Configurações')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.backdrop,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text('Servidor',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Endereço do backend do Vynil. Use o IP do PC na mesma '
                    'rede (ex.: http://192.168.0.10:3000) ou a URL de um túnel.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL do servidor',
                      hintText: 'https://exemplo.trycloudflare.com',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Salvando...' : 'Salvar e conectar'),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  const _AccountSection(),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Versão',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const _UpdateSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conta', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Sessão de: ${auth.username.isEmpty ? 'usuário' : auth.username}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final navigator = Navigator.of(context);
            await auth.logout();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthScreen()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sair'),
        ),
      ],
    );
  }
}

class _UpdateSection extends StatelessWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<UpdateController>(
      builder: (context, update, _) {
        final latest = update.latest;
        final current = update.currentVersion.isEmpty
            ? '—'
            : '${update.currentVersion} (build ${update.currentBuild})';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instalada: $current',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (latest != null)
              Text(
                'No servidor: ${latest.version} (build ${latest.buildNumber})',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 12),
            if (update.updateAvailable)
              FilledButton.tonalIcon(
                onPressed: () => showUpdateDialog(context),
                icon: const Icon(Icons.system_update_rounded),
                label: const Text('Atualização disponível'),
              )
            else
              OutlinedButton.icon(
                onPressed: update.checking
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final has = await update.check(silent: false);
                        if (!context.mounted) return;
                        if (has) {
                          await showUpdateDialog(context);
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Você está na versão mais recente.'),
                            ),
                          );
                        }
                      },
                icon: update.checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                    update.checking ? 'Verificando...' : 'Verificar atualizações'),
              ),
            if (update.error != null) ...[
              const SizedBox(height: 8),
              Text(update.error!,
                  style: TextStyle(color: scheme.error, fontSize: 12)),
            ],
          ],
        );
      },
    );
  }
}
