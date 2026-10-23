import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppInfoModule } from './app-info/app-info.module';
import { AuthModule } from './auth/auth.module';
import { CollectionsModule } from './collections/collections.module';
import { HealthModule } from './health/health.module';
import { TracksModule } from './tracks/tracks.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      envFilePath: ['.env.local', '.env'],
    }),
    AuthModule,
    TracksModule,
    HealthModule,
    AppInfoModule,
    CollectionsModule,
  ],
})
export class AppModule {}
