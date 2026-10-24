import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from './auth.service';
import { AuthUser } from './current-user.decorator';

const PUBLIC_PATHS = new Set<string>([
  '/api/health',
  '/api/app/version',
  '/api/app/apk',
  '/api/auth/login',
  '/api/auth/register',
]);

/**
 * Exige um JWT válido em todas as rotas, exceto as públicas (health, versão,
 * login, registro). O token pode vir no header Authorization: Bearer <token>
 * ou na query ?token=... (para áudio/capa, que não enviam headers).
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context
      .switchToHttp()
      .getRequest<Request & { user?: AuthUser }>();

    if (PUBLIC_PATHS.has(request.path)) {
      return true;
    }

    const token = this.extractToken(request);
    const payload = token ? this.auth.verifyToken(token) : null;
    if (!payload) {
      throw new UnauthorizedException('Autenticação necessária.');
    }

    request.user = { userId: payload.sub, username: payload.username };
    return true;
  }

  private extractToken(request: Request): string | null {
    const header = request.header('authorization');
    if (header && header.startsWith('Bearer ')) {
      return header.slice(7).trim();
    }
    const query = request.query.token;
    return typeof query === 'string' ? query : null;
  }
}
