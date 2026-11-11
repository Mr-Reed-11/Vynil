# Vynil — servidor de download

Backend mínimo: **um endpoint** que baixa o áudio de um link do YouTube com
`yt-dlp` e devolve o MP3. O app Vynil chama este servidor, baixa o MP3 e salva
no dispositivo (depois toca 100% offline). Sem banco, sem login — só uma chave
compartilhada opcional.

Existe porque o YouTube bloqueia a extração feita direto no celular; o `yt-dlp`
(aqui no servidor) roda o JS de deciframento do YouTube e funciona de forma
confiável.

## Rodar na VPS (Docker)

```bash
cd backend
cp .env.example .env            # defina DOWNLOAD_KEY (uma senha qualquer)
docker compose up -d --build
```

Fica em `http://SEU_IP:3000`. Teste:

```bash
curl "http://SEU_IP:3000/health"
```

> **Exponha com cuidado:** sempre use `DOWNLOAD_KEY` (senão qualquer um pode usar
> seu servidor para baixar). Idealmente ponha atrás de HTTPS (Caddy/Nginx) ou só
> acessível na sua rede/VPN.

No app: **Configurações → Servidor de download** → URL (`http://SEU_IP:3000`) e a
mesma chave.

## Endpoint

```
GET /download?url=<link do YouTube>&key=<DOWNLOAD_KEY>
→ 200 audio/mpeg (stream do MP3)
  headers: X-Title, X-Artist, X-Duration, X-Video-Id, X-Thumbnail
GET /health → { ok: true }
```

Atualizar o yt-dlp: `docker compose build --no-cache && docker compose up -d`.
