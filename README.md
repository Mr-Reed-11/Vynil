# Vynil

Servidor pessoal de música: recebe um link do YouTube, baixa o áudio em **MP3**
(com metadados e capa embutidos) e serve as faixas para um app **Flutter** que
lista, baixa e reproduz as músicas.

> ⚠️ **Uso responsável:** baixe apenas conteúdo que você tem direito de usar.
> Este é um projeto pessoal de estudo; respeite os Termos de Serviço do YouTube e
> a legislação de direitos autorais do seu país.

## Monorepo

| Pasta | O que é | Stack |
|-------|---------|-------|
| [`backend/`](backend/) | API que baixa e serve as faixas | NestJS 12 + TypeScript, yt-dlp, ffmpeg |
| [`frontend/`](frontend/) | App player | Flutter + just_audio + provider |

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
                └─ status = ready + URLs de stream/download
```

O app acompanha o status com `GET /api/tracks/:id` (polling) e toca
`GET /api/tracks/:id/stream`, que suporta **HTTP Range** (seek/streaming).

## Começando

Backend:

```bash
cd backend
cp .env.example .env
npm install
npm run start:dev      # requer yt-dlp e ffmpeg no PATH
```

Ou via Docker: `cd backend && docker compose up --build`.

Frontend:

```bash
cd frontend
flutter pub get
flutter run
```

Veja os READMEs de cada pasta para detalhes de configuração.

## Licença

MIT
