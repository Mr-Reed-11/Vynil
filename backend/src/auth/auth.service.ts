import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
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
import { MailerService } from './mailer.service';
import { UsersRepository } from './users.repository';

export interface AuthResult {
  /** 'approved' = logou direto (convite); 'pending' = aguardando aprovação. */
  status: 'approved' | 'pending';
  token?: string;
  user?: { id: string; username: string };
  message?: string;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

@Injectable()
export class AuthService {
  private readonly jwtSecret: string;
  private readonly inviteKey: string;
  private readonly tokenTtlSeconds: number;
  private readonly publicBaseUrl: string;

  constructor(
    config: ConfigService,
    private readonly users: UsersRepository,
    private readonly mailer: MailerService,
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
    this.publicBaseUrl = (
      config.get<string>('PUBLIC_BASE_URL') || ''
    ).replace(/\/+$/, '');
  }

  async register(
    username: string,
    password: string,
    email?: string,
    inviteKey?: string,
  ): Promise<AuthResult> {
    await this.users.ready();
    const name = username.trim();
    const mail = (email ?? '').trim();
    if (name.length < 3) {
      throw new BadRequestException('Usuário deve ter ao menos 3 caracteres.');
    }
    if (password.length < 6) {
      throw new BadRequestException('Senha deve ter ao menos 6 caracteres.');
    }
    if (EMAIL_RE.test(mail) === false) {
      throw new BadRequestException('Informe um email válido.');
    }
    if (this.users.findByUsername(name)) {
      throw new ConflictException('Esse usuário já existe.');
    }
    if (this.users.findByEmail(mail)) {
      throw new ConflictException('Esse email já está cadastrado.');
    }

    // Com SMTP configurado: cadastro fica pendente e o dono aprova por email.
    // Sem SMTP: volta a exigir a chave de convite (aprovação na hora), senão
    // não haveria como liberar a conta.
    if (this.mailer.configured) {
      const user = this.users.create(name, hashPassword(password), mail);
      const approveUrl = `${this.publicBaseUrl}/api/auth/approve?token=${this.technicalToken(user.id, username)}`;
      const rejectUrl = `${this.publicBaseUrl}/api/auth/reject?token=${this.technicalToken(user.id, username)}`;
      void this.mailer.sendApprovalRequest(
        this.mailer.adminMail,
        name,
        mail,
        approveUrl,
        rejectUrl,
      );
      return {
        status: 'pending',
        message: 'Cadastro enviado. Você recebe um email quando for aprovado.',
      };
    }

    if (this.inviteKey && (inviteKey ?? '').trim() !== this.inviteKey) {
      throw new UnauthorizedException(
        'Servidor sem email configurado: informe a chave de convite.',
      );
    }
    const user = this.users.create(name, hashPassword(password), mail, 'active');
    return { ...this.result(user.id, user.username), status: 'approved' };
  }

  async login(username: string, password: string): Promise<AuthResult> {
    await this.users.ready();
    const user = this.users.findByUsername(username);
    if (!user || !verifyPassword(password, user.passwordHash)) {
      throw new UnauthorizedException('Usuário ou senha inválidos.');
    }
    if (user.status === 'pending') {
      throw new ForbiddenException(
        'Sua conta ainda está aguardando aprovação.',
      );
    }
    if (user.status === 'rejected') {
      throw new ForbiddenException('Este cadastro foi recusado.');
    }
    return this.result(user.id, user.username);
  }

  /** Aprova via link do email (token técnico de 7 dias). */
  async approve(token: string): Promise<{ username: string; email: string } | null> {
    const payload = this.verifyActionToken(token);
    if (!payload) return null;
    await this.users.ready();
    const user = this.users.setStatus(payload.sub, 'active');
    if (!user || user.status !== 'active') return null;
    if (user.email) this.mailer.sendApproved(user.email, user.username);
    return { username: user.username, email: user.email };
  }

  /** Recusa via link do email: remove o cadastro (pode tentar de novo). */
  async reject(token: string): Promise<{ username: string } | null> {
    const payload = this.verifyActionToken(token);
    if (!payload) return null;
    await this.users.ready();
    const user = this.users.findById(payload.sub);
    if (!user || user.status !== 'pending') return null;
    if (user.email) this.mailer.sendRejected(user.email, user.username);
    this.users.remove(user.id);
    return { username: user.username };
  }

  /** Usado pelo guard para validar o token. */
  verifyToken(token: string): JwtPayload | null {
    return verifyJwt(token, this.jwtSecret);
  }

  private technicalToken(userId: string, username: string): string {
    return signJwt({ sub: userId, username, type: 'action' }, this.jwtSecret, 7 * 86400);
  }

  private verifyActionToken(token: string): JwtPayload | null {
    const payload = verifyJwt(token, this.jwtSecret);
    if (!payload || payload.type !== 'action') return null;
    return payload;
  }

  private result(id: string, username: string): AuthResult {
    const token = signJwt({ sub: id, username }, this.jwtSecret, this.tokenTtlSeconds);
    return { status: 'approved', token, user: { id, username } };
  }
}
