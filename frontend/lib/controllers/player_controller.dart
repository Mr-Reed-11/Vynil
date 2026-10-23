import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/music_api.dart';
import '../data/track.dart';

/// Controla o player (just_audio) e expõe o estado para a UI.
class PlayerController extends ChangeNotifier {
  PlayerController(this._api) {
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        _playing = state.playing;
        _notify();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        _position = position;
        _notify();
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
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Track? _current;
  bool _loading = false;
  String? _error;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  Track? get current => _current;
  bool get isLoading => _loading;
  bool get isPlaying => _playing;
  String? get error => _error;
  Duration get position => _position;
  Duration? get duration => _duration;

  Future<void> playTrack(Track track) async {
    if (!track.isReady) {
      return;
    }

    if (_current?.id == track.id) {
      await toggle();
      return;
    }

    _current = track;
    _loading = true;
    _error = null;
    _position = Duration.zero;
    _duration = track.duration;
    _notify();

    try {
      final url = _api.absoluteUrl(track.streamUrl);
      if (url == null) {
        throw StateError('Faixa sem URL de stream.');
      }
      await _player.setUrl(
        url,
        headers: _api.authHeaders.isEmpty ? null : _api.authHeaders,
      );
      await _player.play();
    } catch (error) {
      _error = 'Não foi possível tocar: $error';
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> toggle() async {
    if (_current == null) {
      return;
    }
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

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> skipBy(Duration delta) async {
    final limit = _duration ?? _current?.duration;
    var target = _position + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (limit != null && target > limit) {
      target = limit;
    }
    await _player.seek(target);
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _position = Duration.zero;
    _duration = null;
    _error = null;
    _notify();
  }

  void _notify() {
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
