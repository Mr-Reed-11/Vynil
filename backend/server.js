'use strict';

// Backend mínimo do Vynil: um endpoint que baixa o áudio de um link do YouTube
// com yt-dlp (que roda o JS de deciframento do YouTube — o que o app sozinho
// não consegue) e devolve o MP3. Sem banco, sem login. Só uma chave opcional.

const express = require('express');
const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const KEY = (process.env.DOWNLOAD_KEY || '').trim();
const TIMEOUT_MS = Number(process.env.DOWNLOAD_TIMEOUT_MS || 180000);

const YT_RE =
  /^(https?:\/\/)?(www\.|m\.|music\.)?(youtube\.com|youtu\.be)\//i;

function cleanup(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch (_) {}
}

function checkKey(req, res, next) {
  if (!KEY) return next();
  const k = (req.query.key || req.get('x-api-key') || '').trim();
  if (k !== KEY) return res.status(401).json({ error: 'unauthorized' });
  next();
}

app.get('/health', (_req, res) => res.json({ ok: true }));

// GET /download?url=<link do YouTube>&key=<chave>
// -> stream do MP3, com metadados nos headers X-*.
app.get('/download', checkKey, (req, res) => {
  const url = String(req.query.url || '').trim();
  if (!YT_RE.test(url)) {
    return res.status(400).json({ error: 'URL do YouTube inválida.' });
  }

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vynil-'));
  const outTmpl = path.join(dir, 'a.%(ext)s');
  const args = [
    '-x',
    '--audio-format', 'mp3',
    '--audio-quality', '0',
    '--no-playlist',
    '--no-progress',
    '--write-info-json',
    '-o', outTmpl,
    url,
  ];

  execFile(
    'yt-dlp',
    args,
    { timeout: TIMEOUT_MS, maxBuffer: 1024 * 1024 * 16 },
    (err, _stdout, stderr) => {
      const mp3 = path.join(dir, 'a.mp3');
      const infoPath = path.join(dir, 'a.info.json');

      if (err || !fs.existsSync(mp3)) {
        cleanup(dir);
        // Prioriza as linhas ERROR: do yt-dlp (o motivo real); senão o stderr.
        const errLines = String(stderr || '')
          .split('\n')
          .filter((l) => l.startsWith('ERROR'))
          .join(' | ');
        const detail = (errLines || String(stderr || err || '')).slice(0, 1200);
        console.error('[download] falhou:', detail);
        return res
          .status(500)
          .json({ error: 'Falha ao baixar.', detail });
      }

      let info = {};
      try {
        info = JSON.parse(fs.readFileSync(infoPath, 'utf8'));
      } catch (_) {}

      const size = fs.statSync(mp3).size;
      res.setHeader('Content-Type', 'audio/mpeg');
      res.setHeader('Content-Length', String(size));
      res.setHeader('X-Video-Id', info.id || '');
      res.setHeader('X-Title', encodeURIComponent(info.title || ''));
      res.setHeader(
        'X-Artist',
        encodeURIComponent(info.uploader || info.channel || info.artist || ''),
      );
      res.setHeader('X-Duration', String(Math.round(info.duration || 0)));
      res.setHeader('X-Thumbnail', encodeURIComponent(info.thumbnail || ''));
      res.setHeader('Access-Control-Expose-Headers',
        'X-Video-Id, X-Title, X-Artist, X-Duration, X-Thumbnail');

      const stream = fs.createReadStream(mp3);
      stream.pipe(res);
      stream.on('close', () => cleanup(dir));
      stream.on('error', () => cleanup(dir));
      res.on('close', () => cleanup(dir));
    },
  );
});

app.listen(PORT, () => {
  console.log(`Vynil download server ouvindo na porta ${PORT}` +
    (KEY ? ' (com chave)' : ' (sem chave — defina DOWNLOAD_KEY!)'));
});
