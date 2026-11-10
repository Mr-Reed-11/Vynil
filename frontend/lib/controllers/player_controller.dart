import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../data/offline_store.dart';
import '../data/track.dart';

/// Modo de reprodução da fila.
enum PlayMode { sequential, shuffle }

/// Controla o player (just_audio + notificação de mídia).
///
/// Usa a FILA NATIVA do just_audio (setAudioSources): isso dá os botões de
/// avançar/voltar na notificação, auto-avanço e shuffle "de graça", e integra
/// com o just_audio_background. A posição é publicada via [positionListenable]
/// (ValueNotifier) para não reconstruir a lista a cada tick.
class PlayerController extends ChangeNotifier {
  PlayerController(this._store) {
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        _playing = state.playing;
        _notify();
      }),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index != null && index >= 0 && index < _queue.length) {
          _current = _queue[index];
          _notify();
        }
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((p) => _position.value = p),
    );
    _subscriptions.add(
      _player.durationStream.listen((d) {
        if (d != null) {
          _duration = d;
          _notify();
          _persistDurationIfMissing(d);
        }
      }),
    );
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace st) {
          _error = _describeError(e);
          _loading = false;
          _notify();
        },
      ),
    );
  }

  final OfflineStore _store;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Chamado quando persistimos a duração de uma faixa (para a lista recarregar
  /// e exibir o tempo em vez de 0:00). Ligado em main.dart.
  void Function()? onTrackUpdated;

  /// Preenche a duração da faixa atual no armazenamento se ela foi salva sem
  /// (download não traz a duração; o player a descobre ao tocar).
  void _persistDurationIfMissing(Duration d) {
    final cur = _current;
    if (cur == null ||
        !cur.localOnly ||
        cur.durationSeconds > 0 ||
        d.inSeconds <= 0) {
      return;
    }
    _store.setDurationIfMissing(cur.id, d.inSeconds).then((_) {
      _current = cur.copyWith(durationSeconds: d.inSeconds);
      onTrackUpdated?.call();
    });
  }

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  ValueListenable<Duration> get positionListenable => _position;

  List<Track> _queue = const [];
  Track? _current;
  bool _loading = false;
  bool _playing = false;
  bool _shuffle = false;
  String? _error;
  Duration? _duration;

  Track? get current => _current;
  bool get isLoading => _loading;
  bool get isPlaying => _playing;
  String? get error => _error;
  Duration get position => _position.value;
  Duration? get duration => _duration;
  bool get isShuffle => _shuffle;
  PlayMode get mode => _shuffle ? PlayMode.shuffle : PlayMode.sequential;
  bool get hasQueue => _queue.length > 1;

  bool _playable(Track t) => _store.audioPath(t.id) != null;

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (!_playable(track)) return;

    final list = (queue ?? [track]).where(_playable).toList(growable: false);
    final startIndex = list.indexWhere((t) => t.id == track.id);
    if (startIndex < 0) return;

    // Mesma fila já carregada?
    final sameQueue = list.length == _queue.length &&
        List.generate(list.length, (i) => list[i].id == _queue[i].id)
            .every((x) => x);

    if (sameQueue) {
      if (_current?.id == track.id) {
        await toggle();
        return;
      }
      await _player.seek(Duration.zero, index: startIndex);
      unawaited(_player.play());
      return;
    }

    _queue = list;
    _current = track;
    _loading = true;
    _error = null;
    _position.value = Duration.zero;
    _duration = track.duration;
    _notify();

    try {
      await _player.setAudioSources(
        list.map(_sourceFor).toList(growable: false),
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );
      await _player.setShuffleModeEnabled(_shuffle);
      _loading = false;
      _notify();
      unawaited(_player.play());
    } catch (error) {
      _error = _describeError(error);
      _loading = false;
      _notify();
    }
  }

  /// Monta o AudioSource preferindo o arquivo local (offline), com o MediaItem
  /// que alimenta a notificação (título, artista, capa).
  AudioSource _sourceFor(Track track) {
    final localAudio = _store.audioPath(track.id);
    final localCover = _store.coverPath(track.id);

    Uri? artUri;
    if (localCover != null) {
      artUri = Uri.file(localCover);
    } else if (track.thumbnailUrl != null) {
      artUri = Uri.tryParse(track.thumbnailUrl!);
    }

    final mediaItem = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.durationSeconds > 0
          ? Duration(seconds: track.durationSeconds)
          : null,
      artUri: artUri,
    );

    if (localAudio == null) {
      throw StateError('Faixa sem arquivo local.');
    }
    return AudioSource.uri(Uri.file(localAudio), tag: mediaItem);
  }

  Future<void> toggle() async {
    if (_current == null) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: _player.currentIndex);
      await _player.play();
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    // Se passou de 3s, "anterior" reinicia a faixa atual.
    if (_position.value > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    if (_shuffle) await _player.shuffle();
    await _player.setShuffleModeEnabled(_shuffle);
    _notify();
  }

  void setMode(PlayMode mode) {
    if ((mode == PlayMode.shuffle) != _shuffle) toggleShuffle();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> skipBy(Duration delta) async {
    final limit = _duration ?? _current?.duration;
    var target = _position.value + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (limit != null && target > limit) target = limit;
    await _player.seek(target);
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _queue = const [];
    _position.value = Duration.zero;
    _duration = null;
    _error = null;
    _notify();
  }

  String _describeError(Object e) {
    if (e is PlayerException) {
      return 'Erro ao tocar (código ${e.code}): ${e.message ?? e}';
    }
    if (e is PlayerInterruptedException) {
      return 'Reprodução interrompida: ${e.message ?? e}';
    }
    return 'Não foi possível tocar: $e';
  }

  void _notify() => notifyListeners();

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _position.dispose();
    _player.dispose();
    super.dispose();
  }
}
