import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';

/**
 * Protecao opcional por API key.
 *
 * Quando APP_API_KEY nao esta definida, o servidor fica aberto (uso local).
 * A chave pode ser enviada no header `x-api-key` ou na query `api_key`
 * (esta ultima existe para facilitar widgets de audio/imagem no Flutter).
 */
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expected = this.config.get<string>('APP_API_KEY')?.trim();
    if (!expected) {
      return true;
    }

    const request = context.switchToHttp().getRequest<Request>();
    // Endpoints publicos: health e a checagem de versao do app (para o
    // mecanismo de atualizacao funcionar mesmo sem chave configurada).
    if (request.path === '/api/health' || request.path === '/api/app/version') {
      return true;
    }

    const header = request.header('x-api-key');
    const query = typeof request.query.api_key === 'string'
      ? request.query.api_key
      : undefined;
    const provided = header ?? query;

    if (provided === expected) {
      return true;
    }

    throw new UnauthorizedException(
      'API key invalida. Envie o header x-api-key (ou ?api_key=...).',
    );
  }
}
