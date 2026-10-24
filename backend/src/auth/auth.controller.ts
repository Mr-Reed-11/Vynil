import { Body, Controller, Get, HttpCode, HttpStatus, Header, Post, Query } from '@nestjs/common';
import { AuthResult, AuthService } from './auth.service';
import { AuthUser, CurrentUser } from './current-user.decorator';
import { LoginDto, RegisterDto } from './dto/auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  register(@Body() dto: RegisterDto): Promise<AuthResult> {
    return this.auth.register(dto.username, dto.password, dto.email, dto.inviteKey);
  }

  @Post('login')
  login(@Body() dto: LoginDto): Promise<AuthResult> {
    return this.auth.login(dto.username, dto.password);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser): AuthUser {
    return user;
  }

  /** Link "Aprovar" do email de cadastro (público, protegido pelo token). */
  @Get('approve')
  @Header('content-type', 'text/html; charset=utf-8')
  async approve(@Query('token') token: string): Promise<string> {
    const done = await this.auth.approve(token ?? '');
    if (!done) return AUTH_FAIL_PAGE('Essa aprovação expirou ou já foi usada.');
    return AUTH_OK_PAGE(`✅ Conta de <b>${done.username}</b> aprovada!`);
  }

  /** Link "Recusar" do email: remove o cadastro. */
  @Get('reject')
  @Header('content-type', 'text/html; charset=utf-8')
  async reject(@Query('token') token: string): Promise<string> {
    const done = await this.auth.reject(token ?? '');
    if (!done) return AUTH_FAIL_PAGE('Essa recusa expirou ou o cadastro já foi resolvido.');
    return AUTH_OK_PAGE(`❌ Cadastro de <b>${done.username}</b> recusado e removido.`);
  }
}

function AUTH_OK_PAGE(message: string): string {
  return `<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;text-align:center;padding:60px;font-size:20px">${message}<p style="color:#888">Pode fechar essa página.</p></body>`;
}

function AUTH_FAIL_PAGE(message: string): string {
  return `<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;text-align:center;padding:60px;font-size:20px;color:#dc2626">${message}</body>`;
}
