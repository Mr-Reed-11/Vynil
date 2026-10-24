import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { StorageService } from '../tracks/storage.service';

export type UserStatus = 'pending' | 'active' | 'rejected';

export interface User {
  id: string;
  username: string;
  usernameLower: string;
  /** Email informado no cadastro; usuários antigos podem ter vazio. */
  email: string;
  /** pending = aguardando aprovação; active = liberado. */
  status: UserStatus;
  passwordHash: string;
  createdAt: string;
}

interface DatabaseFile {
  version: 1;
  users: User[];
}

@Injectable()
export class UsersRepository implements OnModuleInit {
  private readonly logger = new Logger(UsersRepository.name);
  private readonly users = new Map<string, User>();
  private writeChain: Promise<void> = Promise.resolve();
  private initPromise: Promise<void> | null = null;

  constructor(private readonly storage: StorageService) {}

  private get file(): string {
    return join(this.storage.dbDir, 'users.json');
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
      const parsed = JSON.parse(raw) as DatabaseFile;
      for (const u of parsed.users ?? []) {
        this.users.set(u.id, this.migrate(u));
      }
      this.logger.log(`${this.users.size} usuario(s) carregado(s)`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        await this.persist();
        return;
      }
      throw error;
    }
  }

  get count(): number {
    return this.users.size;
  }

  findById(id: string): User | undefined {
    return this.users.get(id);
  }

  findByUsername(username: string): User | undefined {
    const lower = username.trim().toLowerCase();
    for (const u of this.users.values()) {
      if (u.usernameLower === lower) return u;
    }
    return undefined;
  }

  findByEmail(email: string): User | undefined {
    const lower = email.trim().toLowerCase();
    for (const u of this.users.values()) {
      if (u.email.toLowerCase() === lower) return u;
    }
    return undefined;
  }

  countPending(): number {
    return [...this.users.values()].filter((u) => u.status === 'pending')
      .length;
  }

  create(
    username: string,
    passwordHash: string,
    email: string,
    status: UserStatus = 'pending',
  ): User {
    const user: User = {
      id: randomUUID(),
      username: username.trim(),
      usernameLower: username.trim().toLowerCase(),
      email: email.trim(),
      status,
      passwordHash,
      createdAt: new Date().toISOString(),
    };
    this.users.set(user.id, user);
    void this.persist();
    return user;
  }

  setStatus(id: string, status: UserStatus): User | undefined {
    const user = this.users.get(id);
    if (!user) return undefined;
    user.status = status;
    void this.persist();
    return user;
  }

  remove(id: string): void {
    if (this.users.delete(id)) void this.persist();
  }

  private migrate(raw: User): User {
    // Usuários criados antes do fluxo de aprovação: já eram convidados → ativos.
    return {
      ...raw,
      email: raw.email || '',
      status: raw.status || 'active',
    };
  }

  private persist(): Promise<void> {
    const snapshot: DatabaseFile = {
      version: 1,
      users: [...this.users.values()],
    };
    const payload = JSON.stringify(snapshot, null, 2);
    const tmp = `${this.file}.tmp`;
    this.writeChain = this.writeChain
      .then(async () => {
        await writeFile(tmp, payload, 'utf8');
        await rename(tmp, this.file);
      })
      .catch((error: Error) => {
        this.logger.error(`Falha ao gravar usuarios: ${error.message}`);
      });
    return this.writeChain;
  }
}
