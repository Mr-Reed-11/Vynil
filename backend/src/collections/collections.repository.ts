import { Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { StorageService } from '../tracks/storage.service';
import { Collection } from './collection.types';

interface DatabaseFile {
  version: 1;
  collections: Collection[];
}

/**
 * Persistencia das colecoes (playlists) em JSON, com escrita atomica.
 * Mesmo padrao do indice de faixas.
 */
@Injectable()
export class CollectionsRepository implements OnModuleInit {
  private readonly logger = new Logger(CollectionsRepository.name);
  private readonly collections = new Map<string, Collection>();
  private writeChain: Promise<void> = Promise.resolve();
  private initPromise: Promise<void> | null = null;

  constructor(private readonly storage: StorageService) {}

  private get file(): string {
    return join(this.storage.dbDir, 'collections.json');
  }

  onModuleInit(): Promise<void> {
    return this.ready();
  }

  ready(): Promise<void> {
    this.initPromise ??= this.load();
    return this.initPromise;
  }

  private async load(): Promise<void> {
    await this.storage.ensureDirs();
    try {
      const raw = await readFile(this.file, 'utf8');
      const parsed = JSON.parse(raw) as DatabaseFile | Collection[];
      const list = Array.isArray(parsed) ? parsed : parsed.collections ?? [];
      for (const c of list) {
        this.collections.set(c.id, c);
      }
      this.logger.log(`${this.collections.size} colecao(oes) carregada(s)`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        await this.persist();
        return;
      }
      this.logger.error(`Falha ao ler ${this.file}: ${(error as Error).message}`);
      throw error;
    }
  }

  findAll(): Collection[] {
    return [...this.collections.values()].sort((a, b) =>
      b.updatedAt.localeCompare(a.updatedAt),
    );
  }

  findById(id: string): Collection | undefined {
    return this.collections.get(id);
  }

  findByIdOrFail(id: string): Collection {
    const c = this.findById(id);
    if (!c) {
      throw new NotFoundException(`Playlist ${id} nao encontrada.`);
    }
    return c;
  }

  create(name: string, trackIds: string[]): Collection {
    const now = new Date().toISOString();
    const collection: Collection = {
      id: randomUUID(),
      name,
      trackIds: [...new Set(trackIds)],
      createdAt: now,
      updatedAt: now,
    };
    this.collections.set(collection.id, collection);
    void this.persist();
    return collection;
  }

  update(
    id: string,
    patch: Partial<Pick<Collection, 'name' | 'trackIds'>>,
  ): Collection {
    const current = this.findByIdOrFail(id);
    const updated: Collection = {
      ...current,
      ...patch,
      trackIds: patch.trackIds ? [...new Set(patch.trackIds)] : current.trackIds,
      updatedAt: new Date().toISOString(),
    };
    this.collections.set(id, updated);
    void this.persist();
    return updated;
  }

  delete(id: string): void {
    this.findByIdOrFail(id);
    this.collections.delete(id);
    void this.persist();
  }

  private persist(): Promise<void> {
    const snapshot: DatabaseFile = {
      version: 1,
      collections: [...this.collections.values()],
    };
    const payload = JSON.stringify(snapshot, null, 2);
    const tmp = `${this.file}.tmp`;
    this.writeChain = this.writeChain
      .then(async () => {
        await writeFile(tmp, payload, 'utf8');
        await rename(tmp, this.file);
      })
      .catch((error: Error) => {
        this.logger.error(`Falha ao gravar colecoes: ${error.message}`);
      });
    return this.writeChain;
  }
}
