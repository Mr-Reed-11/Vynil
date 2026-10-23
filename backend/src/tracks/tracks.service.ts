import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DownloadQueueService } from './download-queue.service';
import { CreateTrackDto } from './dto/create-track.dto';
import { QueryTracksDto } from './dto/query-tracks.dto';
import { StorageService } from './storage.service';
import { Track, TrackListResponse, TrackResponse, TrackStatus } from './track.types';
import { toTrackResponse } from './track.mapper';
import { TracksRepository } from './tracks.repository';
import { YtDlpService } from './ytdlp.service';

const ALLOWED_HOSTS = new Set([
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
  'www.youtu.be',
]);

export interface CreateTrackResult {
  track: TrackResponse;
  created: boolean;
}

export interface LibraryStats {
  total: number;
  byStatus: Record<TrackStatus, number>;
  totalSizeBytes: number;
  storageDir: string;
}

export interface PlaylistResult {
  playlistTitle: string;
  total: number;
  added: number;
  skipped: number;
  items: TrackResponse[];
}

@Injectable()
export class TracksService {
  private readonly logger = new Logger(TracksService.name);
  private readonly publicBaseUrl: string;

  constructor(
    private readonly config: ConfigService,
    private readonly repository: TracksRepository,
    private readonly queue: DownloadQueueService,
    private readonly ytdlp: YtDlpService,
    private readonly storage: StorageService,
  ) {
    this.publicBaseUrl = (config.get<string>('PUBLIC_BASE_URL') ?? '').trim();
  }

  /**
   * Recebe um link, consulta os metadados e enfileira o download.
   * Idempotente por youtubeId: reenviar o mesmo link nao duplica nada.
   */
  async create(dto: CreateTrackDto): Promise<CreateTrackResult> {
    const url = this.normalizeUrl(dto.url);
    const metadata = await this.ytdlp.probe(url);

    const maxDuration = Number(this.config.get<string>('MAX_DURATION_SECONDS', '0'));
    if (
      Number.isFinite(maxDuration) &&
      maxDuration > 0 &&
      metadata.durationSeconds > maxDuration
    ) {
      throw new BadRequestException(
        `A faixa tem ${metadata.durationSeconds}s e o limite configurado e ${maxDuration}s.`,
      );
    }

    const existing = this.repository.findByYoutubeId(metadata.youtubeId);
    if (existing) {
      if (existing.status === 'error') {
        const restarted = this.repository.update(existing.id, {
          url: metadata.webpageUrl,
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          durationSeconds: metadata.durationSeconds,
          thumbnailUrl: metadata.thumbnailUrl,
          status: 'queued',
          progress: 0,
          error: null,
        });
        this.queue.enqueue(restarted.id);
        this.logger.log(`Reenfileirando faixa com erro: ${restarted.title}`);
        return { track: this.toResponse(restarted), created: false };
      }

      return { track: this.toResponse(existing), created: false };
    }

    const track = this.repository.create({
      youtubeId: metadata.youtubeId,
      url: metadata.webpageUrl,
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      durationSeconds: metadata.durationSeconds,
      thumbnailUrl: metadata.thumbnailUrl,
      status: 'queued',
      progress: 0,
      error: null,
      fileName: null,
      coverFileName: null,
      sizeBytes: null,
      downloadedAt: null,
    });

    this.queue.enqueue(track.id);
    this.logger.log(`Faixa enfileirada: ${track.artist} - ${track.title}`);

    return { track: this.toResponse(track), created: true };
  }

  /**
   * Expande uma playlist e enfileira as faixas que ainda nao existem.
   * Idempotente por youtubeId: itens ja presentes sao contados como ignorados.
   */
  async createFromPlaylist(dto: CreateTrackDto): Promise<PlaylistResult> {
    const url = this.normalizeUrl(dto.url);
    const max =
      Number(this.config.get<string>('MAX_PLAYLIST_ITEMS', '100')) || 100;
    const info = await this.ytdlp.probePlaylist(url, max);

    const items: TrackResponse[] = [];
    let added = 0;
    let skipped = 0;

    for (const entry of info.entries) {
      const existing = this.repository.findByYoutubeId(entry.youtubeId);
      if (existing) {
        skipped += 1;
        items.push(this.toResponse(existing));
        continue;
      }

      const track = this.repository.create({
        youtubeId: entry.youtubeId,
        url: entry.webpageUrl,
        title: entry.title,
        artist: entry.artist,
        album: info.title,
        durationSeconds: entry.durationSeconds,
        thumbnailUrl: entry.thumbnailUrl,
        status: 'queued',
        progress: 0,
        error: null,
        fileName: null,
        coverFileName: null,
        sizeBytes: null,
        downloadedAt: null,
      });
      this.queue.enqueue(track.id);
      items.push(this.toResponse(track));
      added += 1;
    }

    this.logger.log(
      `Playlist "${info.title}": ${added} adicionada(s), ${skipped} ja existiam.`,
    );

    return {
      playlistTitle: info.title,
      total: info.entries.length,
      added,
      skipped,
      items,
    };
  }

  list(query: QueryTracksDto): TrackListResponse {
    const { items, total } = this.repository.findAll({
      status: query.status,
      query: query.q,
      limit: query.limit,
      offset: query.offset,
    });

    return {
      items: items.map((track) => this.toResponse(track)),
      total,
      limit: query.limit,
      offset: query.offset,
    };
  }

  get(id: string): TrackResponse {
    return this.toResponse(this.repository.findByIdOrFail(id));
  }

  /** Usado pelo controller para servir arquivos (capa/audio). */
  getEntity(id: string): Track {
    return this.repository.findByIdOrFail(id);
  }

  getReadyTrack(id: string): Track {
    const track = this.repository.findByIdOrFail(id);
    if (track.status !== 'ready' || !track.fileName) {
      throw new ConflictException(
        `A faixa ainda nao esta pronta (status: ${track.status}).`,
      );
    }
    return track;
  }

  async remove(id: string): Promise<void> {
    const track = this.repository.findByIdOrFail(id);
    if (track.status === 'downloading') {
      throw new ConflictException(
        'A faixa esta sendo baixada. Aguarde terminar para excluir.',
      );
    }

    this.repository.delete(id);
    await this.storage.removeTrackFiles(track.fileName, track.coverFileName);
    this.logger.log(`Faixa removida: ${track.title}`);
  }

  retry(id: string): TrackResponse {
    const track = this.repository.findByIdOrFail(id);
    if (track.status !== 'error') {
      throw new ConflictException(
        'Somente faixas com erro podem ser reprocessadas.',
      );
    }

    const updated = this.repository.update(id, {
      status: 'queued',
      progress: 0,
      error: null,
    });
    this.queue.enqueue(id);
    return this.toResponse(updated);
  }

  stats(): LibraryStats {
    const byStatus = this.repository.countByStatus();
    const total = Object.values(byStatus).reduce((sum, value) => sum + value, 0);

    return {
      total,
      byStatus,
      totalSizeBytes: this.repository.totalSizeBytes(),
      storageDir: this.storage.rootDir,
    };
  }

  private toResponse(track: Track): TrackResponse {
    return toTrackResponse(track, this.publicBaseUrl);
  }

  private normalizeUrl(value: string): string {
    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      throw new BadRequestException('URL invalida.');
    }

    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      throw new BadRequestException('Use um link http(s) do YouTube.');
    }

    if (!ALLOWED_HOSTS.has(parsed.hostname.toLowerCase())) {
      throw new BadRequestException(
        'Apenas links do YouTube sao aceitos (youtube.com, youtu.be, music.youtube.com).',
      );
    }

    return parsed.toString();
  }
}
