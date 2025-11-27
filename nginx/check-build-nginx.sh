#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-build-nginx.sh}"

if [ ! -f "$SCRIPT" ]; then
  echo "找不到腳本: $SCRIPT" >&2
  exit 1
fi

echo ">> 檢查語法: $SCRIPT"
if bash -n "$SCRIPT"; then
  echo "✓ 語法 OK"
else
  echo "✗ 語法有錯，請看上面的錯誤訊息" >&2
  exit 1
fi
