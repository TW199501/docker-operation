#!/bin/sh
set -eu

CONF="${KEEPALIVED_CONF:-/etc/keepalived/keepalived.conf}"

mkdir -p "$(dirname "$CONF")" /var/log/keepalived

if [ ! -f "$CONF" ]; then
  echo "[ERROR] 找不到 keepalived.conf，請掛載 /etc/keepalived 或設定 KEEPALIVED_CONF" >&2
  exit 1
fi

exec /usr/sbin/keepalived -n -f "$CONF" "$@"
