#!/usr/bin/env bash
#
# Envia o APK arm64 já buildado para o servidor e atualiza a versão anunciada
# pelo updater. Rodar DESTE PC (usa SSH por senha para o servidor).
#
# Uso:   ./deploy.sh
# Server: export VYNIL_SERVER="usuario@ip" para mudar (padrão abaixo).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="${VYNIL_SERVER:-reed@100.125.20.50}"
APK="$ROOT/frontend/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
AAPT2="$(ls "$HOME"/Android/Sdk/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"

[[ -f "$APK" ]] || { echo "APK não encontrado (rode o build antes): $APK" >&2; exit 1; }
[[ -x "$AAPT2" ]] || { echo "aapt2 não encontrado no Android SDK." >&2; exit 1; }

VC="$("$AAPT2" dump badging "$APK" | grep -oE "versionCode='[0-9]+'" | grep -oE '[0-9]+' | head -1)"
VN="$("$AAPT2" dump badging "$APK" | grep -oE "versionName='[^']+'" | sed "s/versionName='//; s/'//" | head -1)"

SSH_OPTS=(-o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
SIZE="$(du -h "$APK" | cut -f1)"

echo "Deploy Vynil $VN (build $VC) -> $SERVER"
echo "→ [1/3] Copiando APK ($SIZE) para o servidor..."
scp "${SSH_OPTS[@]}" "$APK" "$SERVER:~/Vynil/backend/storage/releases/vynil.apk"
echo "   APK copiado."

echo "→ [2/3] Atualizando versão no .env (APP_LATEST_BUILD=$VC)..."
ssh "${SSH_OPTS[@]}" "$SERVER" \
  "cd ~/Vynil/backend && sed -i 's/^APP_LATEST_VERSION=.*/APP_LATEST_VERSION=$VN/; s/^APP_LATEST_BUILD=.*/APP_LATEST_BUILD=$VC/' .env"
echo "   .env atualizado."

echo "→ [3/3] Atualizando código + backend no servidor..."
ssh "${SSH_OPTS[@]}" "$SERVER" \
  "cd ~/Vynil && git pull --ff-only 2>/dev/null; cd backend && docker compose up -d --build && echo '   servidor atualizado' && curl -s http://localhost:3000/api/app/version; echo"

echo "Pronto. No app: Configurações -> Verificar atualizações -> $VN."
