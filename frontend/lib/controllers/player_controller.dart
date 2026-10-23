import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../data/music_api.dart';
import '../data/offline_store.dart';
import '../data/track.dart';

/// Modo de reprodução da fila.
enum PlayMode { sequential, shuffle }

/// Controla o player (just_audio + notificação de mídia) e expõe o estado.
///
/// Performance: a POSIÇÃO é publicada via [positionListenable] (ValueNotifier),
/// NÃO via notifyListeners — assim os ~5 ticks/seg não reconstroem a lista nem
/// o fundo desfocado. notifyListeners só dispara em troca de faixa, play/pause,
/// loading e duração (eventos raros).
class PlayerController extends ChangeNotifier {
  PlayerController(this._api, this._store) {
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        _playing = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _onCompleted();
        }
        _notify();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        // Só o ValueNotifier — sem notifyListeners.
        _position.value = position;
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (duration != null) {
          _duration = duration;
          _notify();
        }
      }),
    );
  }

  final MusicApi _api;
  final OfflineStore _store;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Random _random = Random();

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  ValueListenable<Duration> get positionListenable => _position;

  Track? _current;
  List<Track> _queue = const [];
  PlayMode _mode = PlayMode.sequential;
  bool _loading = false;
  String? _error;
  bool _playing = false;
  Duration? _duration;
  int _loadToken = 0;

  Track? get current => _current;
  bool get isLoading => _loading;
  bool get isPlaying => _playing;
  String? get error => _error;
  Duration get position => _position.value;
  Duration? get duration => _duration;
  PlayMode get mode => _mode;
  bool get isShuffle => _mode == PlayMode.shuffle;
  bool get hasQueue => _queue.length > 1;

  int get _currentIndex =>
      _current == null ? -1 : _queue.indexWhere((t) => t.id == _current!.id);

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (!track.isReady && _store.audioPath(track.id) == null) {
      return;
    }

    if (queue != null) {
      final playable = queue
          .where((t) => t.isReady || _store.audioPath(t.id) != null)
          .toList(growable: false);
      _queue = playable.any((t) => t.id == track.id) ? playable : [track];
    } else if (!_queue.any((t) => t.id == track.id)) {
      _queue = [track];
    }

    if (_current?.id == track.id) {
      await toggle();
      return;
    }

    await _load(track);
  }

  /// Monta o AudioSource preferindo o arquivo local (offline), com o MediaItem
  /// que alimenta a notificação (título, artista, capa).
  AudioSource _sourceFor(Track track) {
    final localAudio = _store.audioPath(track.id);
    final localCover = _store.coverPath(track.id);

    Uri? artUri;
    if (localCover != null) {
      artUri = Uri.file(localCover);
    } else {
      final art = _api.artworkUrl(track.coverUrl) ?? track.thumbnailUrl;
      if (art != null) artUri = Uri.tryParse(art);
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

    if (localAudio != null) {
      return AudioSource.uri(Uri.file(localAudio), tag: mediaItem);
    }
    final url = _api.absoluteUrl(track.streamUrl);
    if (url == null) {
      throw StateError('Faixa sem URL de stream.');
    }
    return AudioSource.uri(
      Uri.parse(url),
      headers: _api.authHeaders.isEmpty ? null : _api.authHeaders,
      tag: mediaItem,
    );
  }

  Future<void> _load(Track track) async {
    _current = track;
    _loading = true;
    _error = null;
    _position.value = Duration.zero;
    _duration = track.duration;
    final token = ++_loadToken;
    _notify();

    try {
      final source = _sourceFor(track);
      // Para a fonte anterior antes de trocar (senão o áudio antigo continua).
      await _player.stop();
      if (token != _loadToken) return;
      await _player.setAudioSource(source);
      if (token != _loadToken) return;
      _loading = false;
      _notify();
      unawaited(_player.play());
    } catch (error) {
      if (token != _loadToken) return;
      _error = 'Não foi possível tocar: $error';
      _loading = false;
      _notify();
    }
  }

  Future<void> toggle() async {
    if (_current == null) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
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
    final track = _pick(1);
    if (track != null) await _load(track);
  }

  Future<void> previous() async {
    if (_position.value > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    final track = _pick(-1);
    if (track != null) await _load(track);
  }

  Track? _pick(int dir) {
    if (_queue.isEmpty) return null;
    if (_queue.length == 1) return _queue.first;
    final index = _currentIndex;
    if (_mode == PlayMode.shuffle) {
      int r;
      do {
        r = _random.nextInt(_queue.length);
      } while (r == index);
      return _queue[r];
    }
    if (index < 0) return _queue.first;
    final n = (index + dir) % _queue.length;
    return _queue[(n + _queue.length) % _queue.length];
  }

  void _onCompleted() {
    if (_queue.isEmpty || _loading) return;
    if (_mode == PlayMode.shuffle) {
      final track = _pick(1);
      if (track != null) unawaited(_load(track));
      return;
    }
    final index = _currentIndex;
    if (index >= 0 && index < _queue.length - 1) {
      unawaited(_load(_queue[index + 1]));
    }
  }

  void setMode(PlayMode mode) {
    _mode = mode;
    _notify();
  }

  void toggleShuffle() {
    setMode(isShuffle ? PlayMode.sequential : PlayMode.shuffle);
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
    _loadToken++;
    await _player.stop();
    _current = null;
    _queue = const [];
    _position.value = Duration.zero;
    _duration = null;
    _error = null;
    _notify();
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
