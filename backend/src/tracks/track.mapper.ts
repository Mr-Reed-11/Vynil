import { Track, TrackResponse } from './track.types';

export function toTrackResponse(track: Track, publicBaseUrl = ''): TrackResponse {
  const base = publicBaseUrl.replace(/\/+$/, '');
  const resource = `${base}/api/tracks/${track.id}`;
  const ready = track.status === 'ready' && track.fileName !== null;

  return {
    id: track.id,
    youtubeId: track.youtubeId,
    url: track.url,
    title: track.title,
    artist: track.artist,
    durationSeconds: track.durationSeconds,
    thumbnailUrl: track.thumbnailUrl,
    status: track.status,
    progress: track.progress,
    error: track.error,
    sizeBytes: track.sizeBytes,
    createdAt: track.createdAt,
    updatedAt: track.updatedAt,
    downloadedAt: track.downloadedAt,
    streamUrl: ready ? `${resource}/stream` : null,
    downloadUrl: ready ? `${resource}/stream?download=1` : null,
    coverUrl: track.coverFileName ? `${resource}/cover` : null,
  };
}
