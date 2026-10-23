import { IsString, IsUrl, MaxLength } from 'class-validator';

export class CreateTrackDto {
  /** Link do YouTube (video, shorts ou music.youtube.com). */
  @IsString()
  @MaxLength(2048)
  @IsUrl(
    { protocols: ['http', 'https'], require_protocol: true },
    { message: 'url deve ser um link valido com http(s)' },
  )
  url!: string;
}
