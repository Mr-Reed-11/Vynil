import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../controllers/library_controller.dart';

/// Escuta links compartilhados de outros apps (ex.: "Compartilhar" do YouTube)
/// e os adiciona automaticamente à biblioteca.
class ShareListener extends StatefulWidget {
  const ShareListener({super.key, required this.child});

  final Widget child;

  @override
  State<ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends State<ShareListener> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // App já aberto recebendo um compartilhamento.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handle,
      onError: (_) {},
    );
    // App aberto a partir de um compartilhamento (cold start).
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handle(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String? _extractUrl(List<SharedMediaFile> files) {
    for (final file in files) {
      final match = RegExp(r'https?://[^\s]+').firstMatch(file.path);
      if (match != null) return match.group(0);
    }
    return null;
  }

  bool _looksLikePlaylist(Uri uri) {
    final hasList = uri.queryParameters.containsKey('list');
    final hasVideo = uri.queryParameters.containsKey('v');
    return hasList && (uri.path.contains('playlist') || !hasVideo);
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final url = _extractUrl(files);
    if (url == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryController>();
    final uri = Uri.tryParse(url);

    try {
      if (uri != null && _looksLikePlaylist(uri)) {
        final r = await library.addPlaylist(url);
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text('Playlist "${r.playlistTitle}": '
              '${r.added} adicionada(s).'),
        ));
      } else {
        final track = await library.add(url);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('"${track.title}" adicionada à fila.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao adicionar o link: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
