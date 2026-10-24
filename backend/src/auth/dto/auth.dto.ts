import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterDto {
  @IsString()
  @MinLength(3)
  @MaxLength(40)
  username!: string;

  @IsString()
  @MinLength(6)
  @MaxLength(200)
  password!: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  inviteKey?: string;
}

export class LoginDto {
  @IsString()
  @MaxLength(40)
  username!: string;

  @IsString()
  @MaxLength(200)
  password!: string;
}
