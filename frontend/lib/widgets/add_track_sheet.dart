import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';

class AddTrackSheet extends StatefulWidget {
  const AddTrackSheet({super.key});

  @override
  State<AddTrackSheet> createState() => _AddTrackSheetState();
}

class _AddTrackSheetState extends State<AddTrackSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  bool _direct = false; // qual ação está rodando (direto x servidor)
  double _directProgress = 0;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Playlist "pura": link /playlist?list=... ou com list= e sem vídeo (v=).
  /// `watch?v=X&list=Y` é tratado como vídeo único.
  bool _looksLikePlaylist(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final hasList = uri.queryParameters.containsKey('list');
    final hasVideo = uri.queryParameters.containsKey('v');
    return hasList && (uri.path.contains('playlist') || !hasVideo);
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Cole o link do vídeo.');
      return;
    }

    FocusScope.of(context).unfocus();
    final library = context.read<LibraryController>();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String message;
      if (_looksLikePlaylist(url)) {
        final r = await library.addPlaylist(url);
        final extra = r.skipped > 0 ? ' (${r.skipped} já existiam)' : '';
        message = 'Playlist "${r.playlistTitle}": '
            '${r.added} adicionada(s)$extra.';
      } else {
        final track = await library.add(url);
        message = '"${track.title}" adicionada à fila.';
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  /// Baixa direto no dispositivo (sem o backend) — só vídeo único.
  Future<void> _downloadDirect() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Cole o link do vídeo.');
      return;
    }
    if (_looksLikePlaylist(url)) {
      setState(() =>
          _error = 'Download direto é só para vídeo único (não playlist).');
      return;
    }

    FocusScope.of(context).unfocus();
    final library = context.read<LibraryController>();
    setState(() {
      _loading = true;
      _direct = true;
      _directProgress = 0;
      _error = null;
    });

    try {
      final track = await library.downloadFromYoutube(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _directProgress = p);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop('"${track.title}" salva no dispositivo.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _direct = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Adicionar música',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cole um link do YouTube. "Servidor" envia pro backend (vídeo ou '
              'playlist). "No dispositivo" baixa direto aqui, sem backend.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_loading,
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                errorText: _error,
                errorMaxLines: 4,
                suffixIcon: IconButton(
                  tooltip: 'Colar da área de transferência',
                  onPressed: _loading ? null : _paste,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
            ),
            if (_direct && _loading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _directProgress > 0 ? _directProgress : null,
              ),
              const SizedBox(height: 6),
              Text(
                'Baixando no dispositivo... '
                '${(_directProgress * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _loading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: (_loading && !_direct)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Servidor'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _loading ? null : _downloadDirect,
                icon: const Icon(Icons.download_for_offline_rounded),
                label: const Text('Baixar no dispositivo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
