import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  hashPassword,
  JwtPayload,
  signJwt,
  verifyJwt,
  verifyPassword,
} from './crypto.util';
import { UsersRepository } from './users.repository';

export interface AuthResult {
  token: string;
  user: { id: string; username: string };
}

@Injectable()
export class AuthService {
  private readonly jwtSecret: string;
  private readonly inviteKey: string;
  private readonly tokenTtlSeconds: number;

  constructor(
    config: ConfigService,
    private readonly users: UsersRepository,
  ) {
    this.jwtSecret =
      config.get<string>('JWT_SECRET')?.trim() ||
      config.get<string>('APP_API_KEY')?.trim() ||
      'vynil-dev-secret-change-me';
    this.inviteKey = (
      config.get<string>('INVITE_KEY') ||
      config.get<string>('APP_API_KEY') ||
      ''
    ).trim();
    this.tokenTtlSeconds =
      Number(config.get<string>('JWT_TTL_SECONDS', '2592000')) || 2592000;
  }

  async register(
    username: string,
    password: string,
    inviteKey?: string,
  ): Promise<AuthResult> {
    await this.users.ready();
    if (this.inviteKey && (inviteKey ?? '').trim() !== this.inviteKey) {
      throw new UnauthorizedException('Chave de convite inválida.');
    }
    const name = username.trim();
    if (name.length < 3) {
      throw new BadRequestException('Usuário deve ter ao menos 3 caracteres.');
    }
    if (password.length < 6) {
      throw new BadRequestException('Senha deve ter ao menos 6 caracteres.');
    }
    if (this.users.findByUsername(name)) {
      throw new ConflictException('Esse usuário já existe.');
    }
    const user = this.users.create(name, hashPassword(password));
    return this.result(user.id, user.username);
  }

  async login(username: string, password: string): Promise<AuthResult> {
    await this.users.ready();
    const user = this.users.findByUsername(username);
    if (!user || !verifyPassword(password, user.passwordHash)) {
      throw new UnauthorizedException('Usuário ou senha inválidos.');
    }
    return this.result(user.id, user.username);
  }

  /** Usado pelo guard para validar o token. */
  verifyToken(token: string): JwtPayload | null {
    return verifyJwt(token, this.jwtSecret);
  }

  private result(id: string, username: string): AuthResult {
    const token = signJwt({ sub: id, username }, this.jwtSecret, this.tokenTtlSeconds);
    return { token, user: { id, username } };
  }
}
