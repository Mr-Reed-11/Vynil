import { Module } from '@nestjs/common';
import { TracksModule } from '../tracks/tracks.module';
import { HealthController } from './health.controller';

@Module({
  imports: [TracksModule],
  controllers: [HealthController],
})
export class HealthModule {}
