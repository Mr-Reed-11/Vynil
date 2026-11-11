# Vynil — servidor de download

Backend mínimo: **um endpoint** que baixa o áudio de um link do YouTube com
`yt-dlp` e devolve o MP3. O app Vynil chama este servidor, baixa o MP3 e salva
no dispositivo (depois toca 100% offline). Sem banco, sem login — só uma chave
compartilhada opcional.

Existe porque o YouTube bloqueia a extração feita direto no celular; o `yt-dlp`
(aqui no servidor) roda o JS de deciframento do YouTube e funciona de forma
confiável.

## Deploy no Portainer (Traefik + HTTPS)

Igual às outras stacks: **Portainer → Stacks → Add stack → Repository**, apontando
para este repo (`Mr-Reed-11/Vynil`), compose em `docker-compose.prod.yml`.

Ele sobe o serviço atrás do **Traefik** na rede externa `web`, com TLS do
Let's Encrypt. Variáveis de ambiente na stack:

| Variável | O que é |
|----------|---------|
| `DOWNLOAD_KEY` | **Obrigatória.** Senha compartilhada (a mesma vai no app). |
| `VYNIL_HOST` | Subdomínio. Padrão `vynil.nortixcode.com.br`. |
| `DOWNLOAD_TIMEOUT_MS` | Opcional (padrão 180000). |

Aponte o DNS do `VYNIL_HOST` para a VPS antes de subir (pro Let's Encrypt emitir
o certificado). Depois teste:

```bash
curl "https://vynil.nortixcode.com.br/health"   # -> {"ok":true}
```

No app: **Configurações → Servidor de download** → URL
(`https://vynil.nortixcode.com.br`) e a mesma `DOWNLOAD_KEY`.

## Cookies do YouTube (OBRIGATÓRIO em VPS)

Em IP de datacenter o YouTube exige login ("Sign in to confirm you're not a
bot"). Sem cookies, todo download dá 403. Então:

1. **Use uma conta YouTube descartável/secundária** (não a sua principal — a
   atividade pode fazer o Google sinalizar/bloquear a conta).
2. Num navegador logado nessa conta, exporte os cookies no formato Netscape
   (`cookies.txt`) — ex.: extensão "Get cookies.txt LOCALLY", na página
   `youtube.com`. Dica: exporte numa aba anônima e feche sem usar, para os
   cookies não serem rotacionados.
3. Na VPS, coloque o arquivo em **`/opt/vynil/cookies.txt`** (ou ajuste
   `COOKIES_DIR` na stack). O compose monta essa pasta como `/cookies:ro`.
4. Redeploy. Confira: `curl https://vynil.nortixcode.com.br/health` deve
   retornar `{"ok":true,"cookies":true}`.

Os cookies expiram de tempos em tempos — se os downloads voltarem a dar 403, é
só reexportar e substituir o arquivo.

### Rodar solto (sem Traefik), para testar

```bash
cd backend
cp .env.example .env            # defina DOWNLOAD_KEY
docker compose up -d --build    # expõe http://SEU_IP:3000
```

## Endpoint

```
GET /download?url=<link do YouTube>&key=<DOWNLOAD_KEY>
→ 200 audio/mpeg (stream do MP3)
  headers: X-Title, X-Artist, X-Duration, X-Video-Id, X-Thumbnail
GET /health → { ok: true }
```

Atualizar o yt-dlp: `docker compose build --no-cache && docker compose up -d`.
