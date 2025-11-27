#!/usr/bin/env bash
set -euo pipefail

KEEPALIVED_CONF=${KEEPALIVED_CONF:-/etc/keepalived/keepalived.conf}
KEEPALIVED_BIN=${KEEPALIVED_BIN:-/usr/sbin/keepalived}
NGINX_BIN=${NGINX_BIN:-/usr/sbin/nginx}

if [ ! -f "$KEEPALIVED_CONF" ]; then
  echo "[WARN] 找不到 $KEEPALIVED_CONF，skip 啟動 keepalived" >&2
else
  if [ ! -x "$KEEPALIVED_BIN" ]; then
    echo "[WARN] 找不到 keepalived 執行檔，skip 啟動" >&2
  else
    echo ">> 啟動 keepalived (config: $KEEPALIVED_CONF)"
    "$KEEPALIVED_BIN" -n -f "$KEEPALIVED_CONF" "$@" &
    KEEPALIVED_PID=$!
    trap 'echo "捕捉信號，停止 keepalived"; kill "$KEEPALIVED_PID" 2>/dev/null || true' TERM INT
  fi
fi

echo ">> 以前景模式啟動 nginx"
exec $NGINX_BIN -g 'daemon off;'
