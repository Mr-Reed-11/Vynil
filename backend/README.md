# music-server — backend

Backend em **NestJS + TypeScript** que recebe um link do YouTube, baixa o áudio em **MP3** (com metadados e capa embutidos) e serve os arquivos para o app **Flutter** em [`../frontend/`](../frontend/), que lista, baixa e reproduz as músicas.

> ⚠️ **Uso responsável:** baixe apenas conteúdo que você tem direito de usar. O projeto é uma ferramenta pessoal de armazenamento; respeite os Termos de Serviço do YouTube e a legislação de direitos autorais do seu país.

---

## Como funciona

```
POST /api/tracks { url }
        │
        ├─ valida o link (somente domínios do YouTube)
        ├─ yt-dlp consulta metadados (título, artista, duração, capa)
        ├─ cria a faixa no índice (status = queued)
        └─ enfileira o download
                │
                ├─ yt-dlp + ffmpeg baixam e convertem para MP3
                ├─ tags ID3 + capa embutidas
                ├─ arquivo salvo em storage/music, capa em storage/covers
                └─ status = ready + URLs de stream/download
```

O app Flutter acompanha o status com `GET /api/tracks/:id` (polling) e toca
`GET /api/tracks/:id/stream`, que suporta **HTTP Range** (seek/streaming).

## Stack

- **NestJS 12** + TypeScript
- **yt-dlp** para download e metadados
- **ffmpeg** para converter em MP3, embutir tags e capa
- Índice em **JSON com escrita atômica** (sem banco por enquanto)
- **Docker / docker-compose** com volume de armazenamento
- Node >= 22 (testado com Node 26)

## Estrutura

```
music-server/
├── backend/               # este projeto
│   ├── src/
│   │   ├── main.ts
│   │   ├── app.module.ts
│   │   ├── common/            # guard de API key + filtro de erros
│   │   ├── health/            # GET /api/health
│   │   └── tracks/
│   │       ├── tracks.controller.ts
│   │       ├── tracks.service.ts
│   │       ├── tracks.repository.ts   # índice JSON
│   │       ├── storage.service.ts     # layout de pastas
│   │       ├── ytdlp.service.ts       # wrapper do yt-dlp
│   │       ├── download-queue.service.ts
│   │       └── dto/
│   ├── storage/               # dados (não versionados)
│   │   ├── music/             # .mp3
│   │   ├── covers/            # .jpg
│   │   └── db/tracks.json     # índice
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
└── frontend/              # app Flutter (lista + player)
```

## Rodando localmente

Pré-requisitos: Node 22+, `yt-dlp` e `ffmpeg`.

Execute os comandos abaixo dentro da pasta `backend/`:

```bash
cp .env.example .env
npm install
npm run start:dev
```

A API sobe em `http://localhost:3000/api`.

### Instalando as ferramentas

**Arch/CachyOS:**

```bash
sudo pacman -S ffmpeg yt-dlp npm   # ou: yay -S yt-dlp
```

**Sem sudo (binário):**

```bash
mkdir -p ~/.local/bin
curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux \
  -o ~/.local/bin/yt-dlp
chmod +x ~/.local/bin/yt-dlp
export PATH="$HOME/.local/bin:$PATH"
```

Se o `yt-dlp` não estiver no `PATH`, aponte o caminho em `YTDLP_PATH` no `.env`.

> Neste ambiente já deixei `npm` e `yt-dlp` em `~/.local/bin`, com o `PATH` configurado no `~/.zshrc`, e um `.env` local apontando para eles.

## Rodando com Docker

> O Docker **não está instalado neste ambiente**, então o `docker compose` não foi executado aqui. O fluxo local foi validado com download real.

```bash
cd backend
cp .env.example .env
docker compose up -d --build
```

- API: `http://localhost:3000/api`
- Os arquivos ficam em `./storage` no host (bind mount) e em `/data` no container.
- Para usar um volume gerenciado pelo Docker, troque o volume no `docker-compose.yml` (opção comentada).
- O container roda como usuário `node` (UID 1000). Se o seu usuário tiver outro UID, ajuste `user:` no compose ou dê permissão a `./storage`.
- O binário do `yt-dlp` é embutido na imagem. Ele quebra com frequência quando o YouTube muda; para atualizar:

```bash
docker compose build --no-cache
docker compose up -d
```

## App Flutter

O app fica em [`../frontend/`](../frontend/) e já implementa biblioteca, adição
de links, progresso dos downloads e player (`just_audio`).

```bash
cd ../frontend
flutter pub get
flutter run -d chrome
```

- Web/desktop/iOS Simulator usam `http://localhost:3000` por padrão.
- Emulador Android usa `http://10.0.2.2:3000`.
- Celular físico ou servidor remoto:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000
```

- Com `APP_API_KEY`: adicione `--dart-define=API_KEY=minha-chave`.

Detalhes, estrutura e limitações em [`../frontend/README.md`](../frontend/README.md).

## Configuração (`.env`)

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `PORT` | `3000` | Porta HTTP |
| `STORAGE_DIR` | `./storage` | Raiz do armazenamento (`/data` no Docker) |
| `DOWNLOAD_CONCURRENCY` | `1` | Downloads simultâneos (1–4) |
| `MAX_DURATION_SECONDS` | `0` | Duração máxima aceita (0 = sem limite) |
| `YTDLP_PATH` | `yt-dlp` | Binário do yt-dlp |
| `FFMPEG_PATH` | `ffmpeg` | Binário do ffmpeg (opcional) |
| `YTDLP_COOKIES_FILE` | — | Cookies Netscape p/ contornar anti-bot (opcional) |
| `PUBLIC_BASE_URL` | — | Prefixo absoluto das URLs retornadas (ex.: `http://192.168.0.10:3000`) |
| `APP_API_KEY` | — | Se definido, exige `x-api-key` (ou `?api_key=`) |

## API

Base: `/api`. Todas as respostas são JSON, exceto `stream` (áudio) e `cover` (imagem).

| Método | Rota | Descrição |
| --- | --- | --- |
| `GET` | `/health` | Status do serviço, yt-dlp e armazenamento |
| `POST` | `/tracks` | Enfileira um link (`{ "url": "..." }`) |
| `GET` | `/tracks` | Lista faixas (`status`, `q`, `limit`, `offset`) |
| `GET` | `/tracks/stats` | Totais por status e tamanho em disco |
| `GET` | `/tracks/:id` | Detalhe/status de uma faixa |
| `POST` | `/tracks/:id/retry` | Reprocessa uma faixa com erro |
| `DELETE` | `/tracks/:id` | Remove faixa, MP3 e capa |
| `GET` | `/tracks/:id/stream` | Áudio com suporte a `Range` e `?download=1` |
| `GET` | `/tracks/:id/cover` | Capa em JPEG |

### Exemplos

```bash
# Adicionar uma música
curl -X POST http://localhost:3000/api/tracks \
  -H 'content-type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=VIDEO_ID"}'

# Acompanhar o download
curl http://localhost:3000/api/tracks/<id>

# Listar prontas, buscando por "daft punk"
curl 'http://localhost:3000/api/tracks?status=ready&q=daft%20punk'

# Tocar / baixar
curl -I http://localhost:3000/api/tracks/<id>/stream
curl -OJ 'http://localhost:3000/api/tracks/<id>/stream?download=1'

# Com API key
curl -H 'x-api-key: MINHA_CHAVE' http://localhost:3000/api/tracks
```

### Resposta de uma faixa

```json
{
  "id": "e388506e-ae04-4d03-b0c2-9c4d542a75fd",
  "youtubeId": "aqz-KE-bpKQ",
  "url": "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
  "title": "Big Buck Bunny",
  "artist": "Blender",
  "durationSeconds": 635,
  "thumbnailUrl": "https://i.ytimg.com/...",
  "status": "ready",
  "progress": 100,
  "error": null,
  "sizeBytes": 19108215,
  "createdAt": "2026-10-22T23:18:42.745Z",
  "updatedAt": "2026-10-22T23:19:21.531Z",
  "downloadedAt": "2026-10-22T23:19:21.531Z",
  "streamUrl": "/api/tracks/<id>/stream",
  "downloadUrl": "/api/tracks/<id>/stream?download=1",
  "coverUrl": "/api/tracks/<id>/cover"
}
```

Status possíveis: `queued` → `downloading` → `ready` | `error`.

`POST /tracks` é **idempotente por vídeo**: reenviar o mesmo link retorna `200` com a faixa existente; uma faixa nova retorna `201`.

## Integrando com o player Flutter

- **`just_audio`**: use a URL absoluta (`PUBLIC_BASE_URL` ajuda) e envie a API key via headers:

```dart
await player.setUrl(
  '$baseUrl/api/tracks/$id/stream',
  headers: {'x-api-key': apiKey},
);
```

- **Seek**: o endpoint `stream` responde `206 Partial Content` com `Content-Range`, então o player consegue buscar posição.
- **Capa**: `Image.network('$baseUrl/api/tracks/$id/cover', headers: {...})`.
- **Download offline**: use `downloadUrl` (resposta com `Content-Disposition: attachment`) e salve no dispositivo.
- **Progresso**: enquanto `status` for `queued`/`downloading`, faça polling de `GET /api/tracks/:id` a cada 1–2 s (SSE ainda não implementado).

## Decisões e limitações atuais

- **Single instance**: a fila é em memória; reiniciar retoma downloads pendentes, mas não escala para múltiplas réplicas.
- **Sem playlists nem lives**: apenas um vídeo por link.
- **Sem autenticação de usuários**: existe só a API key opcional.
- **Índice JSON**: suficiente para uma biblioteca pessoal; a interface do repositório permite migrar para SQLite/Postgres.
- **Anti-bot do YouTube**: se aparecer erro de verificação, atualize o `yt-dlp` e/ou configure `YTDLP_COOKIES_FILE`.

## Próximos passos sugeridos

1. SSE/WebSocket para progresso em tempo real.
2. Playlists e download em lote.
3. Metadados editáveis (título/artista/álbum).
4. Migrar o índice para SQLite (Node 26 já tem `node:sqlite` embutido).
5. Testes e2e (`supertest`) e CI.
6. App Flutter: cache offline, reprodução em segundo plano e controle de fila.
