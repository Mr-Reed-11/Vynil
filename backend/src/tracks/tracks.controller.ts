import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  Post,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { createReadStream } from 'node:fs';
import { extname } from 'node:path';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { CreateTrackDto } from './dto/create-track.dto';
import { QueryTracksDto } from './dto/query-tracks.dto';
import { StorageService } from './storage.service';
import { Track, TrackListResponse, TrackResponse } from './track.types';
import { LibraryStats, PlaylistResult, TracksService } from './tracks.service';

const COVER_CONTENT_TYPES: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

@Controller('tracks')
export class TracksController {
  constructor(
    private readonly tracks: TracksService,
    private readonly storage: StorageService,
  ) {}

  @Post()
  async create(
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateTrackDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<TrackResponse> {
    const { track, created } = await this.tracks.create(user.userId, dto);
    res.status(created ? HttpStatus.CREATED : HttpStatus.OK);
    return track;
  }

  @Post('playlist')
  createPlaylist(
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateTrackDto,
  ): Promise<PlaylistResult> {
    return this.tracks.createFromPlaylist(user.userId, dto);
  }

  @Get()
  list(
    @CurrentUser() user: AuthUser,
    @Query() query: QueryTracksDto,
  ): TrackListResponse {
    return this.tracks.list(user.userId, query);
  }

  @Get('stats')
  stats(@CurrentUser() user: AuthUser): LibraryStats {
    return this.tracks.stats(user.userId);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string): TrackResponse {
    return this.tracks.get(user.userId, id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
  ): Promise<void> {
    await this.tracks.remove(user.userId, id);
  }

  @Post(':id/retry')
  retry(@CurrentUser() user: AuthUser, @Param('id') id: string): TrackResponse {
    return this.tracks.retry(user.userId, id);
  }

  @Get(':id/stream')
  async stream(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const track = this.tracks.getReadyTrack(user.userId, id);
    const filePath = this.storage.musicPath(track.fileName as string);

    let size: number;
    try {
      size = await this.storage.fileSize(filePath);
    } catch {
      throw new NotFoundException(
        'Arquivo de audio nao encontrado no armazenamento.',
      );
    }

    const disposition = req.query.download !== undefined ? 'attachment' : 'inline';
    const filename = this.buildFileName(track);

    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.setHeader(
      'Content-Disposition',
      this.contentDisposition(disposition, filename),
    );

    const range = req.headers.range;
    if (!range) {
      res.setHeader('Content-Length', String(size));
      if (req.method === 'HEAD') {
        res.status(HttpStatus.OK).end();
        return;
      }
      this.pipeFile(res, filePath, HttpStatus.OK);
      return;
    }

    const parsed = this.parseRange(range, size);
    if (!parsed) {
      res.setHeader('Content-Range', `bytes */${size}`);
      res.status(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE).end();
      return;
    }

    const { start, end } = parsed;
    res.setHeader('Content-Range', `bytes ${start}-${end}/${size}`);
    res.setHeader('Content-Length', String(end - start + 1));

    if (req.method === 'HEAD') {
      res.status(HttpStatus.PARTIAL_CONTENT).end();
      return;
    }

    this.pipeFile(res, filePath, HttpStatus.PARTIAL_CONTENT, start, end);
  }

  @Get(':id/cover')
  async cover(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const track = this.tracks.getEntity(user.userId, id);
    if (!track.coverFileName) {
      throw new NotFoundException('Esta faixa nao possui capa.');
    }

    const filePath = this.storage.coverPath(track.coverFileName);
    let size: number;
    try {
      size = await this.storage.fileSize(filePath);
    } catch {
      throw new NotFoundException('Arquivo de capa nao encontrado.');
    }

    const contentType =
      COVER_CONTENT_TYPES[extname(filePath).toLowerCase()] ?? 'image/jpeg';

    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Length', String(size));
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');

    if (req.method === 'HEAD') {
      res.status(HttpStatus.OK).end();
      return;
    }

    this.pipeFile(res, filePath, HttpStatus.OK);
  }

  private pipeFile(
    res: Response,
    filePath: string,
    status: number,
    start?: number,
    end?: number,
  ): void {
    res.status(status);
    const stream = createReadStream(
      filePath,
      start === undefined ? undefined : { start, end },
    );
    stream.on('error', () => {
      res.destroy();
    });
    stream.pipe(res);
  }

  private parseRange(
    header: string,
    size: number,
  ): { start: number; end: number } | null {
    const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
    if (!match || (match[1] === '' && match[2] === '')) {
      return null;
    }

    if (match[1] === '') {
      const suffix = Number(match[2]);
      if (!Number.isFinite(suffix) || suffix <= 0) {
        return null;
      }
      return { start: Math.max(size - suffix, 0), end: size - 1 };
    }

    const start = Number(match[1]);
    const requestedEnd = match[2] === '' ? size - 1 : Number(match[2]);
    if (
      !Number.isFinite(start) ||
      !Number.isFinite(requestedEnd) ||
      start > requestedEnd ||
      start >= size
    ) {
      return null;
    }

    return { start, end: Math.min(requestedEnd, size - 1) };
  }

  private buildFileName(track: Track): string {
    const name = `${track.artist} - ${track.title}`
      .replace(/[/\\?%*:|"<>\u0000-\u001f]/g, '_')
      .slice(0, 150)
      .trim();
    return `${name || track.youtubeId}.mp3`;
  }

  private contentDisposition(
    disposition: 'inline' | 'attachment',
    filename: string,
  ): string {
    const ascii = filename
      .replace(/[^\x20-\x7e]/g, '_')
      .replace(/["\\]/g, '_');
    return `${disposition}; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(filename)}`;
  }
}
