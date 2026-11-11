FROM node:20-slim

# ffmpeg (conversão p/ mp3), python3 (yt-dlp é zipapp), unzip (p/ o Deno).
RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl python3 unzip \
  && rm -rf /var/lib/apt/lists/*

# yt-dlp (binário standalone, auto-atualizado no build).
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
       -o /usr/local/bin/yt-dlp \
  && chmod a+rx /usr/local/bin/yt-dlp

# Deno: runtime JS que o yt-dlp usa para decifrar os desafios do YouTube.
# Sem ele o extractor falha com "No supported JavaScript runtime could be found".
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) deno_arch="x86_64-unknown-linux-gnu" ;; \
    arm64) deno_arch="aarch64-unknown-linux-gnu" ;; \
    *) echo "arch não suportada: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/denoland/deno/releases/latest/download/deno-${deno_arch}.zip" -o /tmp/deno.zip; \
  unzip /tmp/deno.zip -d /usr/local/bin; \
  chmod a+rx /usr/local/bin/deno; \
  rm /tmp/deno.zip; \
  deno --version

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./

EXPOSE 3000
CMD ["node", "server.js"]
