export type TrackStatus = 'queued' | 'downloading' | 'ready' | 'error';

export interface Track {
  /** Identificador interno (UUID). */
  id: string;
  /** Dono da faixa (usuario). */
  userId: string;
  /** ID do video no YouTube. */
  youtubeId: string;
  /** URL original compartilhada pelo usuario. */
  url: string;
  title: string;
  artist: string;
  /** Nome do album (tag), quando disponivel nos metadados. */
  album: string | null;
  durationSeconds: number;
  thumbnailUrl: string | null;
  status: TrackStatus;
  /** Progresso do download, de 0 a 100. */
  progress: number;
  error: string | null;
  /** Nome do arquivo de audio dentro de STORAGE_DIR/music. */
  fileName: string | null;
  /** Nome da capa dentro de STORAGE_DIR/covers. */
  coverFileName: string | null;
  sizeBytes: number | null;
  createdAt: string;
  updatedAt: string;
  downloadedAt: string | null;
}

/** Track enriquecida com URLs prontas para o player. */
export interface TrackResponse
  extends Omit<Track, 'fileName' | 'coverFileName' | 'userId'> {
  streamUrl: string | null;
  downloadUrl: string | null;
  coverUrl: string | null;
}

export interface TrackListResponse {
  items: TrackResponse[];
  total: number;
  limit: number;
  offset: number;
}
