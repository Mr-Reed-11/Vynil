import {
  Controller,
  Get,
  Header,
  NotFoundException,
  Res,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Response } from 'express';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';

export interface AppVersionInfo {
  /** Versao legivel da release mais recente (ex.: "1.1.0"). */
  version: string;
  /** Codigo de build incremental; o app compara com o seu. */
  buildNumber: number;
  /** URL para baixar o APK mais recente (null se nao configurada). */
  downloadUrl: string | null;
  /** Notas da versao, em texto. */
  notes: string | null;
  /** Se true, o app deve exigir a atualizacao. */
  mandatory: boolean;
}

/**
 * Informa a versao mais recente do app e serve o APK para o mecanismo de
 * atualizacao in-app (APK sideloaded nao recebe updates da loja).
 *
 * Configurado por variaveis de ambiente — o mantenedor as atualiza ao
 * publicar um novo APK:
 *   APP_LATEST_VERSION   ex.: "1.1.0"
 *   APP_LATEST_BUILD     ex.: "2"  (o app compara com o seu buildNumber)
 *   APP_APK_FILE         caminho do .apk servido em /api/app/apk (ex.: /data/releases/vynil.apk)
 *   APP_APK_URL          alternativa: URL externa do APK (tem prioridade sobre APP_APK_FILE)
 *   APP_RELEASE_NOTES    texto das novidades
 *   APP_UPDATE_MANDATORY "true" para forcar
 */
@Controller('app')
export class AppInfoController {
  constructor(private readonly config: ConfigService) {}

  @Get('version')
  version(): AppVersionInfo {
    const build = Number(this.config.get<string>('APP_LATEST_BUILD', '1'));
    const externalUrl = this.config.get<string>('APP_APK_URL', '').trim();
    const apkFile = this.config.get<string>('APP_APK_FILE', '').trim();
    const notes = this.config.get<string>('APP_RELEASE_NOTES', '').trim();
    const base = this.config
      .get<string>('PUBLIC_BASE_URL', '')
      .trim()
      .replace(/\/+$/, '');

    let downloadUrl: string | null = null;
    if (externalUrl) {
      downloadUrl = externalUrl;
    } else if (apkFile) {
      downloadUrl = `${base}/api/app/apk`;
    }

    return {
      version: this.config.get<string>('APP_LATEST_VERSION', '1.0.0').trim(),
      buildNumber: Number.isFinite(build) && build > 0 ? Math.floor(build) : 1,
      downloadUrl,
      notes: notes || null,
      mandatory:
        this.config.get<string>('APP_UPDATE_MANDATORY', 'false').trim() ===
        'true',
    };
  }

  @Get('apk')
  @Header('Content-Type', 'application/vnd.android.package-archive')
  @Header('Content-Disposition', 'attachment; filename="vynil.apk"')
  async apk(@Res() res: Response): Promise<void> {
    const file = this.config.get<string>('APP_APK_FILE', '').trim();
    if (!file) {
      throw new NotFoundException('Nenhum APK publicado no servidor.');
    }

    let size: number;
    try {
      size = (await stat(file)).size;
    } catch {
      throw new NotFoundException('Arquivo de APK nao encontrado.');
    }

    res.setHeader('Content-Length', String(size));
    const stream = createReadStream(file);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  }
}
