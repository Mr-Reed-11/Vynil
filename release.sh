#!/usr/bin/env bash
#
# Vynil — release standalone (sem backend). Publica o APK no GitHub Releases;
# o app checa https://api.github.com/repos/<repo>/releases/latest e se atualiza.
#
# Uso:
#   ./release.sh <versao> ["notas da versao"] [build]
#
#   <versao>  OBRIGATORIO. versionName exibido. Ex.: 1.5.0 (vira a tag v1.5.0).
#   notas     Texto das novidades (corpo do release / diálogo de atualização).
#   build     Força o buildNumber (versionCode). Padrão = build do pubspec + 1.
#             Precisa aumentar a cada release para o Android instalar por cima.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND="$ROOT/frontend"
PUBSPEC="$FRONTEND/pubspec.yaml"
REPO="Mr-Reed-11/Vynil"
# O updater prefere o asset cujo nome contém "arm64"; mantenha isso no nome.
APK_BUILT="$FRONTEND/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

# --- Toolchain -------------------------------------------------------------
export PATH="$HOME/flutter/bin:$HOME/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-$HOME/jdk21}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

# --- Argumentos ------------------------------------------------------------
VERSION="${1:-}"
NOTES="${2:-}"
if [[ -z "$VERSION" ]]; then
  echo "Uso: ./release.sh <versao> [\"notas\"] [build]" >&2
  echo "Ex.: ./release.sh 1.5.0 \"App 100% offline\"" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versão inválida: '$VERSION'. Use X.Y.Z (ex.: 1.5.0)." >&2
  exit 1
fi

CURRENT_BUILD="$(grep -E '^version:' "$PUBSPEC" | sed -E 's/.*\+([0-9]+).*/\1/' || true)"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || CURRENT_BUILD=0
BUILD="${3:-$((CURRENT_BUILD + 1))}"
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Build inválido: '$BUILD'." >&2; exit 1; }

TAG="v$VERSION"
APK_ASSET="vynil-$VERSION-arm64.apk"

echo "=========================================="
echo " Release Vynil $VERSION (build $BUILD) -> tag $TAG"
echo "=========================================="

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG já existe no GitHub. Escolha outra versão." >&2
  exit 1
fi

# --- 1. pubspec: version: X.Y.Z+BUILD --------------------------------------
tmp="$(mktemp)"
awk -v v="$VERSION+$BUILD" '/^version:/{print "version: " v; done=1; next} {print} END{if(!done) print "version: " v}' "$PUBSPEC" >"$tmp"
mv "$tmp" "$PUBSPEC"
echo "[1/5] pubspec.yaml -> version: $VERSION+$BUILD"

# --- 2. build do APK (arm64) -----------------------------------------------
echo "[2/5] Buildando APK (arm64)..."
( cd "$FRONTEND" && flutter build apk --release --split-per-abi )
[[ -f "$APK_BUILT" ]] || { echo "APK não encontrado: $APK_BUILT" >&2; exit 1; }
cp "$APK_BUILT" "/tmp/$APK_ASSET"

# --- 3. commit do bump de versão -------------------------------------------
echo "[3/5] Commitando o bump de versão..."
( cd "$ROOT" && git add "$PUBSPEC" \
  && git commit -m "release: $VERSION (build $BUILD)" \
  && git push )

# --- 4. criar o release no GitHub (cria a tag no commit atual) -------------
echo "[4/5] Publicando release $TAG no GitHub..."
gh release create "$TAG" "/tmp/$APK_ASSET" \
  --repo "$REPO" \
  --title "Vynil $VERSION" \
  --notes "${NOTES:-Atualização do Vynil $VERSION.}"

# --- 5. fim ----------------------------------------------------------------
rm -f "/tmp/$APK_ASSET"
echo "=========================================="
echo " Release $VERSION publicada em:"
echo "   https://github.com/$REPO/releases/tag/$TAG"
echo " Os apps instalados detectam na próxima abertura."
echo "=========================================="
