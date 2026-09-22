#!/bin/bash
# 构建前端并将产物复制到 Go embed 目录
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/web"

if [ ! -d node_modules ]; then
  npm ci
fi

npm run build

rm -rf "$ROOT/internal/web/dist"
cp -r dist "$ROOT/internal/web/dist"

echo "Frontend built to internal/web/dist"
