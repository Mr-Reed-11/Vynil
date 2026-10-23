import 'package:flutter_test/flutter_test.dart';
import 'package:music_server_app/core/format.dart';
import 'package:music_server_app/data/track.dart';

void main() {
  group('Track.fromJson', () {
    test('interpreta uma faixa pronta', () {
      final track = Track.fromJson({
        'id': 'abc',
        'youtubeId': 'dQw4w9WgXcQ',
        'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'title': 'Never Gonna Give You Up',
        'artist': 'Rick Astley',
        'durationSeconds': 213,
        'thumbnailUrl': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        'status': 'ready',
        'progress': 100,
        'error': null,
        'sizeBytes': 3400000,
        'streamUrl': '/api/tracks/abc/stream',
        'downloadUrl': '/api/tracks/abc/stream?download=1',
        'coverUrl': '/api/tracks/abc/cover',
      });

      expect(track.id, 'abc');
      expect(track.title, 'Never Gonna Give You Up');
      expect(track.artist, 'Rick Astley');
      expect(track.duration, const Duration(seconds: 213));
      expect(track.status, TrackStatus.ready);
      expect(track.isReady, isTrue);
      expect(track.progress, 100);
      expect(track.sizeBytes, 3400000);
      expect(track.streamUrl, '/api/tracks/abc/stream');
      expect(track.coverUrl, '/api/tracks/abc/cover');
    });

    test('preenche valores padrão quando campos faltam', () {
      final track = Track.fromJson({'id': 'xyz'});

      expect(track.youtubeId, '');
      expect(track.url, '');
      expect(track.title, 'Sem título');
      expect(track.artist, 'Desconhecido');
      expect(track.durationSeconds, 0);
      expect(track.progress, 0);
      expect(track.status, TrackStatus.error);
      expect(track.isReady, isFalse);
    });

    test('faixa baixando não está pronta', () {
      final track = Track.fromJson({
        'id': 'abc',
        'status': 'downloading',
        'progress': 42,
      });

      expect(track.status, TrackStatus.downloading);
      expect(track.status.isBusy, isTrue);
      expect(track.isReady, isFalse);
      expect(track.progress, 42);
    });

    test('status desconhecido é tratado como erro', () {
      final track = Track.fromJson({'id': 'abc', 'status': 'qualquer'});

      expect(track.status, TrackStatus.error);
    });
  });

  group('formatação', () {
    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 75)), '1:15');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
