import { Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { Track, TrackStatus } from './track.types';
import { StorageService } from './storage.service';

interface DatabaseFile {
  version: 1;
  tracks: Track[];
}

export interface TrackFilters {
  userId: string;
  status?: TrackStatus;
  query?: string;
  limit: number;
  offset: number;
}

/**
 * Persistencia simples em JSON, com escrita atomica (tmp + rename).
 *
 * O volume de dados de uma biblioteca pessoal e pequeno; isso evita
 * dependencias nativas (SQLite/ORM) e mantem o deploy trivial.
 * A interface permite trocar por Postgres/SQLite mais tarde sem mexer
 * no restante da aplicacao.
 */
@Injectable()
export class TracksRepository implements OnModuleInit {
  private readonly logger = new Logger(TracksRepository.name);
  private readonly tracks = new Map<string, Track>();
  private writeChain: Promise<void> = Promise.resolve();
  private initPromise: Promise<void> | null = null;

  constructor(private readonly storage: StorageService) {}

  onModuleInit(): Promise<void> {
    return this.ready();
  }

  /** Garante que o indice foi carregado (idempotente). */
  ready(): Promise<void> {
    this.initPromise ??= this.load();
    return this.initPromise;
  }

  private async load(): Promise<void> {
    await this.storage.ensureDirs();

    try {
      const raw = await readFile(this.storage.dbFile, 'utf8');
      const parsed = JSON.parse(raw) as DatabaseFile | Track[];
      const tracks = Array.isArray(parsed) ? parsed : parsed.tracks ?? [];
      for (const track of tracks) {
        this.tracks.set(track.id, track);
      }
      this.logger.log(`${this.tracks.size} faixa(s) carregada(s) do indice`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        await this.persist();
        return;
      }
      this.logger.error(
        `Falha ao ler ${this.storage.dbFile}: ${(error as Error).message}`,
      );
      throw error;
    }
  }

  findAll(filters: TrackFilters): { items: Track[]; total: number } {
    const query = filters.query?.trim().toLowerCase();

    const filtered = [...this.tracks.values()]
      .filter((track) => track.userId === filters.userId)
      .filter((track) => !filters.status || track.status === filters.status)
      .filter((track) => {
        if (!query) {
          return true;
        }
        return (
          track.title.toLowerCase().includes(query) ||
          track.artist.toLowerCase().includes(query)
        );
      })
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

    return {
      total: filtered.length,
      items: filtered.slice(filters.offset, filters.offset + filters.limit),
    };
  }

  /** Todas as faixas, de todos os usuarios (usado pela fila ao retomar). */
  all(): Track[] {
    return [...this.tracks.values()];
  }

  findById(id: string): Track | undefined {
    return this.tracks.get(id);
  }

  findByIdOrFail(id: string): Track {
    const track = this.findById(id);
    if (!track) {
      throw new NotFoundException(`Faixa ${id} nao encontrada.`);
    }
    return track;
  }

  findByYoutubeId(userId: string, youtubeId: string): Track | undefined {
    for (const track of this.tracks.values()) {
      if (track.userId === userId && track.youtubeId === youtubeId) {
        return track;
      }
    }
    return undefined;
  }

  countByStatus(userId: string): Record<TrackStatus, number> {
    const counts: Record<TrackStatus, number> = {
      queued: 0,
      downloading: 0,
      ready: 0,
      error: 0,
    };
    for (const track of this.tracks.values()) {
      if (track.userId === userId) {
        counts[track.status] += 1;
      }
    }
    return counts;
  }

  totalSizeBytes(userId: string): number {
    let total = 0;
    for (const track of this.tracks.values()) {
      if (track.userId === userId) {
        total += track.sizeBytes ?? 0;
      }
    }
    return total;
  }

  create(input: Omit<Track, 'id' | 'createdAt' | 'updatedAt'>): Track {
    const now = new Date().toISOString();
    const track: Track = {
      ...input,
      id: randomUUID(),
      createdAt: now,
      updatedAt: now,
    };
    this.tracks.set(track.id, track);
    void this.persist();
    return track;
  }

  update(id: string, patch: Partial<Omit<Track, 'id' | 'createdAt'>>): Track {
    const current = this.findByIdOrFail(id);
    const updated: Track = {
      ...current,
      ...patch,
      updatedAt: new Date().toISOString(),
    };
    this.tracks.set(id, updated);
    void this.persist();
    return updated;
  }

  delete(id: string): Track | undefined {
    const track = this.tracks.get(id);
    if (!track) {
      return undefined;
    }
    this.tracks.delete(id);
    void this.persist();
    return track;
  }

  private persist(): Promise<void> {
    const snapshot: DatabaseFile = {
      version: 1,
      tracks: [...this.tracks.values()],
    };
    const payload = JSON.stringify(snapshot, null, 2);
    const tmpFile = `${this.storage.dbFile}.tmp`;

    this.writeChain = this.writeChain
      .then(async () => {
        await writeFile(tmpFile, payload, 'utf8');
        await rename(tmpFile, this.storage.dbFile);
      })
      .catch((error: Error) => {
        this.logger.error(`Falha ao gravar o indice: ${error.message}`);
      });

    return this.writeChain;
  }
}
