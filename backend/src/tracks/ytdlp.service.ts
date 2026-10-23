import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { execFile, spawn } from 'node:child_process';
import { rename } from 'node:fs/promises';
import { join } from 'node:path';
import { StorageService } from './storage.service';

export interface VideoMetadata {
  youtubeId: string;
  title: string;
  artist: string;
  durationSeconds: number;
  thumbnailUrl: string | null;
  webpageUrl: string;
}

export interface DownloadResult {
  fileName: string;
  coverFileName: string | null;
}

/**
 * Camada fina em cima do yt-dlp.
 *
 * Responsabilidades:
 *  - consultar metadados antes de enfileirar (falha cedo se o link e invalido);
 *  - baixar o audio em mp3 com tags e capa embutidas;
 *  - reportar progresso.
 */
@Injectable()
export class YtDlpService {
  private readonly logger = new Logger(YtDlpService.name);
  private readonly binary: string;
  private readonly ffmpegLocation?: string;
  private readonly cookiesFile?: string;
  private versionCache: string | null | undefined;

  constructor(
    config: ConfigService,
    private readonly storage: StorageService,
  ) {
    this.binary = config.get<string>('YTDLP_PATH')?.trim() || 'yt-dlp';
    this.ffmpegLocation = config.get<string>('FFMPEG_PATH')?.trim() || undefined;
    this.cookiesFile = config.get<string>('YTDLP_COOKIES_FILE')?.trim() || undefined;
  }

  /** Versao do yt-dlp (cacheada). `null` quando o binario nao esta disponivel. */
  async getVersion(): Promise<string | null> {
    if (this.versionCache !== undefined) {
      return this.versionCache;
    }
    try {
      const { stdout } = await this.exec(['--version'], 15_000);
      this.versionCache = stdout.trim() || null;
    } catch {
      this.versionCache = null;
    }
    return this.versionCache;
  }

  async probe(url: string): Promise<VideoMetadata> {
    const { stdout } = await this.exec(
      [
        '--dump-single-json',
        '--no-playlist',
        '--no-warnings',
        '--no-color',
        '--skip-download',
        '--socket-timeout',
        '30',
        ...this.cookieArgs(),
        url,
      ],
      120_000,
    );

    let info: Record<string, any>;
    try {
      info = JSON.parse(stdout) as Record<string, any>;
    } catch {
      throw new BadGatewayException(
        'Nao foi possivel interpretar os metadados retornados pelo yt-dlp.',
      );
    }

    if (info._type === 'playlist') {
      throw new BadRequestException(
        'Envie o link de uma musica/video, nao de uma playlist.',
      );
    }
    if (info.is_live) {
      throw new BadRequestException('Transmissoes ao vivo nao sao suportadas.');
    }
    if (!info.id) {
      throw new BadGatewayException(
        'O yt-dlp nao retornou o ID do video. Verifique o link.',
      );
    }

    const duration = Number(info.duration);
    const artist =
      this.cleanArtist(info.artist) ||
      this.cleanArtist(info.creator) ||
      this.cleanArtist(info.uploader) ||
      this.cleanArtist(info.channel) ||
      'Desconhecido';

    return {
      youtubeId: String(info.id),
      title: String(info.track || info.title || 'Sem titulo').trim(),
      artist,
      durationSeconds: Number.isFinite(duration) ? Math.round(duration) : 0,
      thumbnailUrl: typeof info.thumbnail === 'string' ? info.thumbnail : null,
      webpageUrl:
        typeof info.webpage_url === 'string' ? info.webpage_url : url,
    };
  }

  /**
   * Baixa o audio e move a capa para covers/.
   * `onProgress` recebe valores de 0 a 100.
   */
  async download(
    url: string,
    youtubeId: string,
    onProgress: (percent: number) => void,
  ): Promise<DownloadResult> {
    const outputTemplate = join(this.storage.musicDir, '%(id)s.%(ext)s');

    const args = [
      '--no-playlist',
      '--no-warnings',
      '--no-color',
      '--newline',
      '--progress-template',
      'download:%(progress._percent_str)s',
      '--socket-timeout',
      '30',
      '--retries',
      '3',
      '--fragment-retries',
      '3',
      '--no-mtime',
      '-f',
      'bestaudio/best',
      '-x',
      '--audio-format',
      'mp3',
      '--audio-quality',
      '0',
      '--embed-metadata',
      '--embed-thumbnail',
      '--convert-thumbnails',
      'jpg',
      '--write-thumbnail',
      '-o',
      outputTemplate,
      ...this.cookieArgs(),
      url,
    ];

    if (this.ffmpegLocation) {
      args.unshift('--ffmpeg-location', this.ffmpegLocation);
    }

    this.logger.log(`Iniciando download de ${youtubeId} (${url})`);
    await this.spawnDownload(args, onProgress);

    const fileName = `${youtubeId}.mp3`;
    const audioPath = this.storage.musicPath(fileName);
    if (!(await this.storage.exists(audioPath))) {
      throw new BadGatewayException(
        'O download terminou, mas o arquivo mp3 nao foi encontrado no armazenamento.',
      );
    }

    let coverFileName: string | null = null;
    const thumbnailSource = this.storage.musicPath(`${youtubeId}.jpg`);
    if (await this.storage.exists(thumbnailSource)) {
      coverFileName = `${youtubeId}.jpg`;
      await rename(thumbnailSource, this.storage.coverPath(coverFileName));
    }

    return { fileName, coverFileName };
  }

  private spawnDownload(
    args: string[],
    onProgress: (percent: number) => void,
  ): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const child = spawn(this.binary, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
      });

      let buffer = '';
      let stderr = '';
      let settled = false;

      const fail = (error: Error): void => {
        if (!settled) {
          settled = true;
          reject(error);
        }
      };

      child.stdout.setEncoding('utf8');
      child.stdout.on('data', (chunk: string) => {
        buffer += chunk;
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          // O prefixo "download:" e o seletor de tipo do --progress-template,
          // entao a linha chega apenas como "  42.0%".
          const match = /^(?:download:)?\s*([\d.]+)%\s*$/.exec(line);
          if (match) {
            const percent = Number(match[1]);
            if (Number.isFinite(percent)) {
              onProgress(Math.max(0, Math.min(100, percent)));
            }
          }
        }
      });

      child.stderr.setEncoding('utf8');
      child.stderr.on('data', (chunk: string) => {
        stderr = (stderr + chunk).slice(-16_000);
      });

      child.on('error', (error) => {
        fail(
          new BadGatewayException(
            `Nao foi possivel executar o yt-dlp (${this.binary}): ${error.message}`,
          ),
        );
      });

      child.on('close', (code) => {
        if (settled) {
          return;
        }
        if (code === 0) {
          settled = true;
          resolve();
          return;
        }
        fail(
          new BadGatewayException(this.humanizeError(stderr, code ?? undefined)),
        );
      });
    });
  }

  private exec(
    args: string[],
    timeoutMs: number,
  ): Promise<{ stdout: string; stderr: string }> {
    return new Promise((resolve, reject) => {
      execFile(
        this.binary,
        args,
        { timeout: timeoutMs, maxBuffer: 32 * 1024 * 1024, windowsHide: true },
        (error, stdout, stderr) => {
          if (error) {
            reject(
              new BadGatewayException(
                this.humanizeError(
                  String(stderr ?? ''),
                  typeof error.code === 'number' ? error.code : undefined,
                ),
              ),
            );
            return;
          }
          resolve({ stdout: String(stdout), stderr: String(stderr) });
        },
      );
    });
  }

  private cookieArgs(): string[] {
    return this.cookiesFile ? ['--cookies', this.cookiesFile] : [];
  }

  private cleanArtist(value: unknown): string {
    if (typeof value !== 'string') {
      return '';
    }
    return value.replace(/\s*-\s*Topic\s*$/i, '').trim();
  }

  private humanizeError(stderr: string, code?: number | string): string {
    const raw = stderr
      .trim()
      .split('\n')
      .slice(-6)
      .join(' | ')
      .replace(/\u001b\[[0-9;]*m/g, '');

    if (/sign in to confirm|not a bot|confirm you.?re not a bot/i.test(stderr)) {
      return 'O YouTube pediu verificacao anti-bot. Atualize o yt-dlp ou configure YTDLP_COOKIES_FILE com cookies do navegador.';
    }
    if (/private video/i.test(stderr)) {
      return 'Este video e privado.';
    }
    if (/video unavailable|this video is unavailable/i.test(stderr)) {
      return 'Video indisponivel no YouTube.';
    }
    if (/requested format is not available/i.test(stderr)) {
      return 'Formato de audio indisponivel para este video.';
    }
    if (/timed out/i.test(stderr)) {
      return 'O yt-dlp excedeu o tempo limite. Tente novamente.';
    }
    return `yt-dlp falhou${code !== undefined ? ` (codigo ${code})` : ''}: ${
      raw || 'erro desconhecido'
    }`;
  }
}
