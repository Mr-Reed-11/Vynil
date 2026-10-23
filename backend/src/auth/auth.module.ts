import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { TracksModule } from '../tracks/tracks.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { UsersRepository } from './users.repository';

@Module({
  imports: [TracksModule], // StorageService (para o users.json)
  controllers: [AuthController],
  providers: [
    UsersRepository,
    AuthService,
    { provide: APP_GUARD, useClass: JwtAuthGuard },
  ],
  exports: [AuthService],
})
export class AuthModule {}
