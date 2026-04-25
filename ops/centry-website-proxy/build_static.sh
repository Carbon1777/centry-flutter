#!/usr/bin/env bash
# Собирает то, что должно лежать на VPS в /var/www/centry.website
# centry.website — это ТОЛЬКО статика (public/), как и на Vercel сейчас.
# Никакого Flutter Web билда не нужно.
#
# Результат: ops/centry-website-proxy/dist/

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIST="$HERE/dist"
WEBSITE_REPO="${WEBSITE_REPO:-/Users/jcat/Documents/Doc/centry-website}"

if [[ ! -d "$WEBSITE_REPO/public" ]]; then
  echo "❌ Не найден $WEBSITE_REPO/public"
  exit 1
fi

echo "→ Очищаю $DIST"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "→ Копирую public/* → dist/"
cp -R "$WEBSITE_REPO/public/." "$DIST/"

echo "→ apple-app-site-association в /.well-known/ и в корень"
mkdir -p "$DIST/.well-known"
cp "$WEBSITE_REPO/apple-app-site-association" "$DIST/.well-known/apple-app-site-association"
cp "$WEBSITE_REPO/apple-app-site-association" "$DIST/apple-app-site-association"

echo
echo "✓ Готово:"
ls -la "$DIST"
echo
echo "Залить:"
echo "  rsync -avz --delete -e 'ssh -i ~/.ssh/centry_vps_ed25519' \\"
echo "    \"$DIST/\" root@147.45.185.143:/var/www/centry.website/"
