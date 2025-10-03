# 存檔並執行
sudo tee /root/nginx-preflight.sh >/dev/null <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# 取得可用的 nologin 路徑
choose_nologin() {
  for p in /usr/sbin/nologin /usr/bin/nologin /sbin/nologin /bin/false; do
    [ -x "$p" ] && { echo "$p"; return; }
  done
  echo "/bin/false"
}
NOLOGIN="$(choose_nologin)"

echo "==> 準備系統帳號與目錄..."

# 1) www-data 群組/帳號
sudo groupadd -f www-data
if ! id -u www-data >/dev/null 2>&1; then
  sudo useradd -r -M -s "$NOLOGIN" -g www-data www-data
  echo "  + 建立使用者 www-data"
else
  # 校正 shell（僅在不是 nologin 時）
  CUR_SHELL="$(getent passwd www-data | awk -F: '{print $7}')"
  case "$CUR_SHELL" in
    */nologin|/bin/false) : ;;
    *) sudo usermod -s "$NOLOGIN" www-data; echo "  * 將 www-data 的 shell 設為 $NOLOGIN" ;;
  esac
fi

# 2) nginx 群組/帳號
sudo groupadd -f nginx
if ! id -u nginx >/dev/null 2>&1; then
  sudo useradd -r -M -s "$NOLOGIN" -g nginx nginx
  echo "  + 建立使用者 nginx"
else
  # 確保主要群組為 nginx、shell 為 nologin
  if [ "$(id -gn nginx)" != "nginx" ]; then
    sudo usermod -g nginx nginx
    echo "  * 調整 nginx 的主要群組為 nginx"
  fi
  CUR_SHELL="$(getent passwd nginx | awk -F: '{print $7}')"
  case "$CUR_SHELL" in
    */nologin|/bin/false) : ;;
    *) sudo usermod -s "$NOLOGIN" nginx; echo "  * 將 nginx 的 shell 設為 $NOLOGIN" ;;
  esac
fi

# 3) 必要目錄
sudo mkdir -p /etc/nginx
sudo install -d -m 0755 -o www-data -g www-data \
  /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}

# 4) 顯示摘要
echo "==> 完成。摘要："
getent passwd www-data || true
getent passwd nginx || true
ls -ld /var/cache/nginx /var/cache/nginx/* || true
BASH

sudo chmod +x /root/nginx-preflight.sh
sudo /root/nginx-preflight.sh
