import {
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { StorageService } from './storage.service';
import { TracksRepository } from './tracks.repository';
import { YtDlpService } from './ytdlp.service';

/**
 * Fila de downloads em memoria, com concorrencia configuravel.
 *
 * Ao subir, retoma downloads que ficaram pendentes (status queued ou
 * downloading) de uma execucao anterior.
 */
@Injectable()
export class DownloadQueueService implements OnModuleInit {
  private readonly logger = new Logger(DownloadQueueService.name);
  private readonly concurrency: number;
  private readonly pending: string[] = [];
  private readonly known = new Set<string>();
  private active = 0;

  constructor(
    private readonly config: ConfigService,
    private readonly repository: TracksRepository,
    private readonly ytdlp: YtDlpService,
    private readonly storage: StorageService,
  ) {
    const configured = Number(config.get<string>('DOWNLOAD_CONCURRENCY', '1'));
    this.concurrency = Number.isFinite(configured)
      ? Math.max(1, Math.min(4, Math.floor(configured)))
      : 1;
  }

  async onModuleInit(): Promise<void> {
    await this.repository.ready();

    const resumable = this.repository
      .all()
      .filter(
        (track) => track.status === 'queued' || track.status === 'downloading',
      );

    for (const track of resumable) {
      if (track.status === 'downloading') {
        this.repository.update(track.id, {
          status: 'queued',
          progress: 0,
          error: null,
        });
      }
      this.enqueue(track.id);
    }

    if (resumable.length > 0) {
      this.logger.log(`${resumable.length} download(s) pendente(s) reenfileirado(s)`);
    }
    this.logger.log(`Fila de downloads com concorrencia ${this.concurrency}`);
  }

  enqueue(trackId: string): void {
    if (this.known.has(trackId)) {
      return;
    }
    this.known.add(trackId);
    this.pending.push(trackId);
    this.pump();
  }

  private pump(): void {
    while (this.active < this.concurrency && this.pending.length > 0) {
      const trackId = this.pending.shift();
      if (!trackId) {
        return;
      }
      this.known.delete(trackId);
      this.active += 1;
      void this.process(trackId).finally(() => {
        this.active -= 1;
        this.pump();
      });
    }
  }

  private async process(trackId: string): Promise<void> {
    const track = this.repository.findById(trackId);
    if (!track || track.status === 'ready') {
      return;
    }

    this.repository.update(trackId, {
      status: 'downloading',
      progress: 0,
      error: null,
    });

    let lastProgress = -10;
    let lastWriteAt = 0;

    try {
      const result = await this.ytdlp.download(
        track.url,
        track.id,
        (percent) => {
          const now = Date.now();
          if (
            percent < 100 &&
            percent - lastProgress < 5 &&
            now - lastWriteAt < 1_000
          ) {
            return;
          }
          lastProgress = percent;
          lastWriteAt = now;
          this.repository.update(trackId, {
            progress: Math.round(percent),
          });
        },
      );

      const sizeBytes = await this.storage.fileSize(
        this.storage.musicPath(result.fileName),
      );

      this.repository.update(trackId, {
        status: 'ready',
        progress: 100,
        error: null,
        fileName: result.fileName,
        coverFileName: result.coverFileName,
        sizeBytes,
        downloadedAt: new Date().toISOString(),
      });

      this.logger.log(`Faixa pronta: ${track.artist} - ${track.title}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);

      // A faixa pode ter sido removida enquanto baixava.
      if (!this.repository.findById(trackId)) {
        return;
      }

      this.repository.update(trackId, {
        status: 'error',
        progress: 0,
        error: message,
      });
      this.logger.error(`Falha ao baixar ${track.youtubeId}: ${message}`);
    }
  }
}
