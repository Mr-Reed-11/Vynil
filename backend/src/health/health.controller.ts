import { Controller, Get } from '@nestjs/common';
import { StorageService } from '../tracks/storage.service';
import { YtDlpService } from '../tracks/ytdlp.service';

@Controller('health')
export class HealthController {
  constructor(
    private readonly ytdlp: YtDlpService,
    private readonly storage: StorageService,
  ) {}

  @Get()
  async check(): Promise<Record<string, unknown>> {
    const [ytdlpVersion, writable] = await Promise.all([
      this.ytdlp.getVersion(),
      this.storage.isWritable(),
    ]);

    return {
      status: 'ok',
      uptimeSeconds: Math.round(process.uptime()),
      timestamp: new Date().toISOString(),
      ytdlp: {
        available: ytdlpVersion !== null,
        version: ytdlpVersion,
      },
      storage: {
        path: this.storage.rootDir,
        writable,
      },
    };
  }
}
