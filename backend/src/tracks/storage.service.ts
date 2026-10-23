import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { constants } from 'node:fs';
import { access, mkdir, stat, unlink } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';

/**
 * Dono do layout de armazenamento em disco.
 *
 * storage/
 *   music/   -> arquivos .mp3
 *   covers/  -> capas .jpg
 *   db/      -> indice tracks.json
 */
@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger(StorageService.name);

  readonly rootDir: string;
  readonly musicDir: string;
  readonly coversDir: string;
  readonly dbDir: string;
  readonly dbFile: string;

  constructor(config: ConfigService) {
    this.rootDir = resolve(config.get<string>('STORAGE_DIR', './storage'));
    this.musicDir = join(this.rootDir, 'music');
    this.coversDir = join(this.rootDir, 'covers');
    this.dbDir = join(this.rootDir, 'db');
    this.dbFile = join(this.dbDir, 'tracks.json');
  }

  async onModuleInit(): Promise<void> {
    await this.ensureDirs();
    this.logger.log(`Armazenamento em ${this.rootDir}`);
  }

  async ensureDirs(): Promise<void> {
    await Promise.all([
      mkdir(this.musicDir, { recursive: true }),
      mkdir(this.coversDir, { recursive: true }),
      mkdir(this.dbDir, { recursive: true }),
    ]);
  }

  musicPath(fileName: string): string {
    return join(this.musicDir, basename(fileName));
  }

  coverPath(fileName: string): string {
    return join(this.coversDir, basename(fileName));
  }

  async fileSize(filePath: string): Promise<number> {
    return (await stat(filePath)).size;
  }

  async exists(filePath: string): Promise<boolean> {
    try {
      await access(filePath, constants.F_OK);
      return true;
    } catch {
      return false;
    }
  }

  async removeIfExists(filePath: string): Promise<void> {
    try {
      await unlink(filePath);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
        throw error;
      }
    }
  }

  async removeTrackFiles(fileName: string | null, coverFileName: string | null): Promise<void> {
    const paths = [
      fileName ? this.musicPath(fileName) : null,
      coverFileName ? this.coverPath(coverFileName) : null,
    ].filter((path): path is string => path !== null);

    await Promise.all(paths.map((path) => this.removeIfExists(path)));
  }

  async isWritable(): Promise<boolean> {
    try {
      await access(this.rootDir, constants.W_OK);
      return true;
    } catch {
      return false;
    }
  }
}
