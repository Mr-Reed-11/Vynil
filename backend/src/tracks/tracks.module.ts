import { Module } from '@nestjs/common';
import { DownloadQueueService } from './download-queue.service';
import { StorageService } from './storage.service';
import { TracksController } from './tracks.controller';
import { TracksRepository } from './tracks.repository';
import { TracksService } from './tracks.service';
import { YtDlpService } from './ytdlp.service';

@Module({
  controllers: [TracksController],
  providers: [
    StorageService,
    TracksRepository,
    YtDlpService,
    DownloadQueueService,
    TracksService,
  ],
  exports: [StorageService, YtDlpService, TracksService],
})
export class TracksModule {}
