enum TrackStatus {
  queued,
  downloading,
  ready,
  error;

  static TrackStatus fromString(String? value) {
    return switch (value) {
      'queued' => TrackStatus.queued,
      'downloading' => TrackStatus.downloading,
      'ready' => TrackStatus.ready,
      'error' => TrackStatus.error,
      _ => TrackStatus.error,
    };
  }

  String get label => switch (this) {
        TrackStatus.queued => 'Na fila',
        TrackStatus.downloading => 'Baixando',
        TrackStatus.ready => 'Pronta',
        TrackStatus.error => 'Erro',
      };

  bool get isBusy =>
      this == TrackStatus.queued || this == TrackStatus.downloading;
}

class Track {
  const Track({
    required this.id,
    required this.youtubeId,
    required this.url,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.status,
    required this.progress,
    this.album,
    this.thumbnailUrl,
    this.error,
    this.sizeBytes,
    this.streamUrl,
    this.downloadUrl,
    this.coverUrl,
  });

  final String id;
  final String youtubeId;
  final String url;
  final String title;
  final String artist;
  final int durationSeconds;
  final String? album;
  final String? thumbnailUrl;
  final TrackStatus status;
  final double progress;
  final String? error;
  final int? sizeBytes;
  final String? streamUrl;
  final String? downloadUrl;
  final String? coverUrl;

  bool get isReady => status == TrackStatus.ready && streamUrl != null;

  Duration get duration => Duration(seconds: durationSeconds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'youtubeId': youtubeId,
        'url': url,
        'title': title,
        'artist': artist,
        'album': album,
        'durationSeconds': durationSeconds,
        'thumbnailUrl': thumbnailUrl,
        'status': status.name,
        'progress': progress,
        'error': error,
        'sizeBytes': sizeBytes,
        'streamUrl': streamUrl,
        'downloadUrl': downloadUrl,
        'coverUrl': coverUrl,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      youtubeId: json['youtubeId'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? 'Sem título',
      artist: json['artist'] as String? ?? 'Desconhecido',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      album: (json['album'] as String?)?.trim().isNotEmpty == true
          ? (json['album'] as String).trim()
          : null,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      status: TrackStatus.fromString(json['status'] as String?),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      error: json['error'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      streamUrl: json['streamUrl'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
    );
  }
}
