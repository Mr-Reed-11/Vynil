import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { TrackStatus } from '../track.types';

const STATUSES: TrackStatus[] = ['queued', 'downloading', 'ready', 'error'];

export class QueryTracksDto {
  @IsOptional()
  @IsIn(STATUSES)
  status?: TrackStatus;

  /** Busca por titulo ou artista. */
  @IsOptional()
  @IsString()
  @MaxLength(200)
  q?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 50;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset: number = 0;
}
