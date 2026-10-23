#!/usr/bin/env bash
#
# Vynil — script de release (rodar na raiz do repo, neste PC de desenvolvimento).
#
# Uso:
#   ./release.sh <versao> ["notas da versao"] [build]
#
#   <versao>  OBRIGATORIO. Você escolhe (versionName exibido). Ex.: 1.1.0
#   notas     Texto das novidades mostrado no diálogo de atualização (opcional).
#   build     Força o buildNumber (opcional). Padrão = build atual do pubspec + 1.
#             O buildNumber é o inteiro que o app compara para detectar update,
#             então ele SEMPRE precisa aumentar a cada release.
#
# A URL do servidor e a API key embutidas no APK vêm de release.env (veja
# release.env.example). Se a API key não estiver lá, cai no APP_API_KEY do
# backend/.env.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND="$ROOT/frontend"
BACKEND="$ROOT/backend"
PUBSPEC="$FRONTEND/pubspec.yaml"
ENV_FILE="$BACKEND/.env"
# APK universal: versionCode = número do build (sem o +1000*ABI do split),
# para o updater comparar corretamente.
APK_OUT="$FRONTEND/build/app/outputs/flutter-apk/app-release.apk"
RELEASE_DIR="$BACKEND/storage/releases"

# --- Toolchain (mesmos caminhos usados no setup) ---------------------------
export PATH="$HOME/flutter/bin:$HOME/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-$HOME/jdk21}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

# --- Config de conexão embutida no APK -------------------------------------
API_BASE_URL="${API_BASE_URL:-}"
API_KEY="${API_KEY:-}"
if [[ -f "$ROOT/release.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/release.env"
fi
# Fallback da chave: usa a mesma do backend.
if [[ -z "$API_KEY" && -f "$ENV_FILE" ]]; then
  API_KEY="$(grep -E '^APP_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
fi

# --- Argumentos ------------------------------------------------------------
VERSION="${1:-}"
NOTES="${2:-}"
if [[ -z "$VERSION" ]]; then
  echo "Uso: ./release.sh <versao> [\"notas\"] [build]" >&2
  echo "Ex.: ./release.sh 1.1.0 \"Modo offline + playlists\"" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versão inválida: '$VERSION'. Use o formato X.Y.Z (ex.: 1.2.0)." >&2
  exit 1
fi

CURRENT_BUILD="$(grep -E '^version:' "$PUBSPEC" | sed -E 's/.*\+([0-9]+).*/\1/' || true)"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || CURRENT_BUILD=0
BUILD="${3:-$((CURRENT_BUILD + 1))}"
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Build inválido: '$BUILD' (precisa ser inteiro)." >&2
  exit 1
fi

echo "=========================================="
echo " Release Vynil $VERSION (build $BUILD)"
echo " APK aponta para: ${API_BASE_URL:-<não definido — app usará o padrão/localhost>}"
echo "=========================================="

# --- 1. pubspec: version: X.Y.Z+BUILD --------------------------------------
tmp="$(mktemp)"
awk -v v="$VERSION+$BUILD" '/^version:/{print "version: " v; done=1; next} {print} END{if(!done) print "version: " v}' "$PUBSPEC" >"$tmp"
mv "$tmp" "$PUBSPEC"
echo "[1/5] pubspec.yaml -> version: $VERSION+$BUILD"

# --- 2. build do APK -------------------------------------------------------
echo "[2/5] Buildando APK (arm64)..."
DART_DEFINES=()
[[ -n "$API_BASE_URL" ]] && DART_DEFINES+=(--dart-define=API_BASE_URL="$API_BASE_URL")
[[ -n "$API_KEY" ]] && DART_DEFINES+=(--dart-define=API_KEY="$API_KEY")
( cd "$FRONTEND" && flutter build apk --release "${DART_DEFINES[@]}" )
[[ -f "$APK_OUT" ]] || { echo "APK não encontrado: $APK_OUT" >&2; exit 1; }

# --- 3. publicar o APK no backend ------------------------------------------
mkdir -p "$RELEASE_DIR"
cp "$APK_OUT" "$RELEASE_DIR/vynil.apk"
echo "[3/5] APK publicado -> backend/storage/releases/vynil.apk"

# --- 4. atualizar backend/.env ---------------------------------------------
touch "$ENV_FILE"
set_env() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    $0 ~ "^" k "=" { print k "=" v; found=1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$ENV_FILE" >"$tmp"
  mv "$tmp" "$ENV_FILE"
}
set_env APP_LATEST_VERSION "$VERSION"
set_env APP_LATEST_BUILD "$BUILD"
set_env APP_RELEASE_NOTES "$NOTES"
echo "[4/5] backend/.env atualizado (APP_LATEST_VERSION/BUILD/NOTES)"

# --- 5. reiniciar backend --------------------------------------------------
echo "[5/5] Reiniciando backend..."
( cd "$BACKEND" && docker compose up -d )

echo "=========================================="
echo " Release $VERSION (build $BUILD) publicada."
echo " Os apps instalados vão detectar na próxima abertura."
echo " APK local: $APK_OUT"
echo "=========================================="
