#!/usr/bin/env bash
set -euo pipefail

# 初次掛載空白 volume 時，從 /opt/seed/etc-nginx 複製預設配置
if [ ! -f /etc/nginx/nginx.conf ] && [ -d /opt/seed/etc-nginx ]; then
  cp -a /opt/seed/etc-nginx/. /etc/nginx/
fi

# 若有 keepalived 映射目錄，將安裝腳本同步一份過去，方便在宿主機執行
if [ -d /opt/keepalived ] && [ -f /opt/keepalived-install.sh ]; then
  cp -f /opt/keepalived-install.sh /opt/keepalived/keepalived-install.sh || true
fi

# 如果有 nginx 指令，先調整檔案描述符上限並驗證設定，失敗就直接顯示錯誤並退出
if command -v nginx >/dev/null 2>&1; then
  ulimit -n 65535 || true
  nginx -t
fi

if command -v cron >/dev/null 2>&1; then
  cron
fi

# 以前景模式啟動 Nginx，讓容器主行程就是 nginx
exec nginx -g "daemon off;" "$@"
