import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

@Injectable()
export class MailerService {
  private readonly logger = new Logger(MailerService.name);
  private readonly transport: nodemailer.Transporter | null;
  private readonly adminEmail: string;
  private readonly from: string;

  constructor(config: ConfigService) {
    const host = config.get<string>('SMTP_HOST')?.trim() || '';
    const user = config.get<string>('SMTP_USER')?.trim() || '';
    const pass = config.get<string>('SMTP_PASS')?.trim() || '';
    const port = Number(config.get<string>('SMTP_PORT', '587')) || 587;
    this.adminEmail = (
      config.get<string>('ADMIN_EMAIL') || user
    ).trim();
    this.from = (config.get<string>('SMTP_FROM') || user).trim();

    if (host && user && pass) {
      this.transport = nodemailer.createTransport({
        host,
        port,
        secure: port === 465,
        auth: { user, pass },
      });
      this.logger.log(`SMTP configurado (${host}:${port} -> ${this.adminEmail}).`);
    } else {
      this.transport = null;
      this.logger.warn(
        'SMTP não configurado (SMTP_HOST/SMTP_USER/SMTP_PASS): emails desativados.',
      );
    }
  }

  get configured(): boolean {
    return this.transport !== null && this.adminEmail !== '';
  }

  get adminMail(): string {
    return this.adminEmail;
  }

  /** Envia e resolve; falha é logada, não propaga (não deve travar o fluxo). */
  private async send(to: string, subject: string, html: string): Promise<void> {
    if (!this.transport) {
      this.logger.warn(`Email (não enviado, SMTP ausente) para ${to}: ${subject}`);
      return;
    }
    try {
      await this.transport.sendMail({ from: this.from, to, subject, html });
      this.logger.log(`Email enviado para ${to}: ${subject}`);
    } catch (error) {
      this.logger.error(
        `Falha ao enviar email para ${to}: ${(error as Error).message}`,
      );
    }
  }

  sendApprovalRequest(
    adminEmail: string,
    username: string,
    email: string,
    approveUrl: string,
    rejectUrl: string,
  ): Promise<void> {
    return this.send(
      adminEmail,
      `[Vynil] Novo cadastro: ${username}`,
      `<p><b>${username}</b> (<a href="mailto:${email}">${email}</a>) pediu acesso ao Vynil.</p>
       <p>
         <a href="${approveUrl}" style="padding:10px 18px;background:#16a34a;color:#fff;border-radius:8px;text-decoration:none">Aprovar</a>
         &nbsp;
         <a href="${rejectUrl}" style="padding:10px 18px;background:#dc2626;color:#fff;border-radius:8px;text-decoration:none">Recusar</a>
       </p>`,
    );
  }

  sendApproved(email: string, username: string): Promise<void> {
    return this.send(
      email,
      '[Vynil] Sua conta foi aprovada',
      `<p>Oi, ${username}! Sua conta no Vynil foi aprovada — já pode entrar no app.</p>`,
    );
  }

  sendRejected(email: string, username: string): Promise<void> {
    return this.send(
      email,
      '[Vynil] Seu cadastro foi recusado',
      `<p>Oi, ${username}. Seu cadastro no Vynil não foi aprovado. Se acha que é um erro, fale com quem administra o servidor.</p>`,
    );
  }
}
