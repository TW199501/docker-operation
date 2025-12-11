#!/usr/bin/env bash
# ================================================
# 編譯 build-nginx.sh
# 版本：v1.1 (非互動版本)
# 說明：重構 - 移除互動式流程，支援全自動建置
# 日期：2025-11-28
# ===============================================
set -euo pipefail

# ===== 全域預設變數（可被環境變數覆蓋，確保在 module_A 之前就有值）=====
BUILD_DIR=${BUILD_DIR:-/home/nginx_build_geoip2}
NGINX_VERSION=${NGINX_VERSION:-1.29.3}
NGINX_ETC=${NGINX_ETC:-/etc/nginx}
AUTO_CONFIRM=${AUTO_CONFIRM:-1}      # 自動確認建置
SKIP_CLEANUP=${SKIP_CLEANUP:-0}     # 跳過清理確認
FORCE_CLEANUP=${FORCE_CLEANUP:-0}   # 強制清理
LAN_CIDR=${LAN_CIDR:-"192.168.25.0/24"}

install_nginx_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo ">> 此系統無 systemd，略過 nginx.service 建立"
    return
  fi

  local SERVICE_FILE=/etc/systemd/system/nginx.service
  if [ ! -f "$SERVICE_FILE" ]; then
    echo ">> 建立 /etc/systemd/system/nginx.service"
    $SUDO tee "$SERVICE_FILE" >/dev/null <<'UNIT'
[Unit]
Description=nginx - high performance web server
Documentation=man:nginx(8)
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=/usr/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
  else
    echo ">> 偵測到既有 nginx.service，略過覆寫"
  fi

  echo ">> 重新載入 systemd 並啟動 nginx"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable nginx >/dev/null 2>&1 || true
  if ! $SUDO systemctl restart nginx; then
    $SUDO systemctl start nginx || true
  fi
  $SUDO systemctl status nginx --no-pager || true
}

# ===== 全域 SUDO =====
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
module_A_interactive_and_params() {
  # 设置命令前缀（自动检测是否需要 sudo）
  if [ "$(id -u)" -eq 0 ]; then
    # 已经是 root，不需要 sudo
    SUDO=""
  else
    # 普通用户，需要 sudo
    if ! command -v sudo >/dev/null 2>&1; then
      echo "錯誤：需要 sudo 權限但找不到 sudo 命令"
      exit 1
    fi
    SUDO="sudo"
  fi

  # ===== 顯示配置並確認 =====
  echo "=========================================="
  echo "  Nginx 編譯配置"
  echo "=========================================="
  echo "Nginx 版本：    $NGINX_VERSION"
  echo "OpenSSL 版本：  3.5.4"
  echo "PCRE2 來源：    git (PCRE2Project/pcre2)"
  echo "建置目錄：      $BUILD_DIR"
  echo "內網 CIDR:     $LAN_CIDR"
  echo "zlib 版本：     1.3.1 (source)"
  echo "brotli 來源：    ngx_brotli (source build)"
  echo "GeoIP2 套件：   libmaxminddb0 / libmaxminddb-dev / mmdb-bin"
  echo "GoAccess 來源： git (allinurl/goaccess)"
  echo "=========================================="
  echo ""
  echo ""
  read -p "確認開始編譯？(y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消編譯"
    exit 0
  fi
  echo ""
}

module_B_cleanup_and_stop_old_nginx() {
  # ===== 檢查並清理前次構建失敗的檔案 =====
  echo ">> 檢查前次構建環境..."
  CLEANUP_NEEDED=0

  # 檢查建置目錄
  if [ -d "$BUILD_DIR" ]; then
    echo "   發現前次建置目錄：$BUILD_DIR"
    CLEANUP_NEEDED=1
  fi

  # 檢查是否有殘留的編譯檔案
  if [ -f "/usr/sbin/nginx.new" ] || [ -f "/usr/sbin/nginx.old" ]; then
    echo "   發現殘留的 Nginx 備份檔案"
    CLEANUP_NEEDED=1
  fi

  # 檢查是否有未完成的模組檔案
  if [ -d "/usr/lib/nginx/modules.tmp" ]; then
    echo "   發現未完成的模組目錄"
    CLEANUP_NEEDED=1
  fi

  if [ "$CLEANUP_NEEDED" -eq 1 ]; then
    echo ""
    read -p "是否清理前次構建的檔案以保持環境乾淨？(Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      echo ">> 清理前次構建檔案..."
      rm -rf "$BUILD_DIR" 2>/dev/null || true
      $SUDO rm -f /usr/sbin/nginx.new /usr/sbin/nginx.old 2>/dev/null || true
      $SUDO rm -rf /usr/lib/nginx/modules.tmp 2>/dev/null || true
      echo "✓ 清理完成"
    else
      echo ">> 保留前次構建檔案，繼續執行"
    fi
    echo ""
  else
    echo "✓ 環境乾淨，無需清理"
    echo ""
  fi

  # ===== 停止舊 Nginx（若在跑） =====
  echo ">> 檢查 Nginx 進程..."
  if pgrep -x nginx >/dev/null; then
    echo "   停止 nginx ..."
    if command -v systemctl >/dev/null 2>&1; then
      $SUDO systemctl stop nginx || true
    else
      $SUDO pkill -TERM -x nginx || true
    fi
    sleep 3
    if pgrep -x nginx >/dev/null; then
      $SUDO pkill -KILL -x nginx || true
    fi
  fi
  $SUDO rm -f /run/nginx.pid || true
}

module_C_source_and_deps() {
  # ===== 準備建置目錄 =====
  echo ">> 建立建置目錄：$BUILD_DIR"
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  NGINX_ETC="${NGINX_ETC:-/etc/nginx}"   # Nginx 設定目錄

  # ===== 抓 Nginx 原始碼 =====
  echo ">> 下載 Nginx ${NGINX_VERSION}"
  wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
  tar -xzf "nginx-${NGINX_VERSION}.tar.gz"

  # ===== 模組原始碼（可重複執行：先清理目標目錄再 clone） =====
  echo ">> 取得外掛模組"

  rm -rf "$BUILD_DIR/ngx_http_geoip2_module" \
         "$BUILD_DIR/ngx_brotli" \
         "$BUILD_DIR/headers-more-nginx-module" \
         "$BUILD_DIR/ngx_cache_purge" \
         "$BUILD_DIR/njs" \
         "$BUILD_DIR/goaccess"

  git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git "$BUILD_DIR/ngx_http_geoip2_module"
  git clone --recursive https://github.com/google/ngx_brotli.git "$BUILD_DIR/ngx_brotli"
  git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git "$BUILD_DIR/headers-more-nginx-module"
  git clone --depth=1 https://github.com/FRiCKLE/ngx_cache_purge.git "$BUILD_DIR/ngx_cache_purge"
  git clone --depth=1 https://github.com/nginx/njs.git "$BUILD_DIR/njs"
  git clone --depth=1 https://github.com/allinurl/goaccess.git "$BUILD_DIR/goaccess"

  # ===== 依賴安裝（先定義 SUDO / need_install）=====
  echo ">> 檢查/安裝建置依賴"
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  need_install=0
  for b in gcc make git curl wget cmake; do
    command -v "$b" >/dev/null 2>&1 || need_install=1
  done

  if [ "$need_install" -eq 1 ]; then
    echo "偵測到缺少編譯工具，嘗試自動安裝..."
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      $SUDO apt-get update -yq
      $SUDO apt-get install -yq \
        build-essential zlib1g-dev libssl-dev libmaxminddb0 libmaxminddb-dev mmdb-bin \
        autoconf autopoint gettext libncursesw5-dev \
        unzip git libpcre2-dev libxml2-dev libxslt1-dev libmodsecurity3 libmodsecurity-dev libgd-dev \
        curl wget cmake libbrotli-dev
    else
      echo "無法判斷套件管理器，請手動安裝依賴。"
      exit 1
    fi
  fi

  # 二次驗證
  for bin in gcc make git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "安裝失敗：缺少 $bin"; exit 1; }
  done

  # 確認 PCRE2 就緒（或至少 PCRE v1）
  if command -v pcre2-config >/dev/null 2>&1; then
    echo "已偵測到 PCRE2 推薦"
  elif command -v pcre-config >/dev/null 2>&1; then
    echo "已偵測到舊版 PCRE 可用,但建議改用 PCRE2"
  else
    echo "缺少 PCRE/PCRE2 開發環境，請手動安裝 libpcre2-dev/pcre2-devel 或重跑本腳本。"
    exit 1
  fi
  echo "依賴檢查完成"

  cd "$BUILD_DIR"

  # 先編譯安裝 libmaxminddb，提供 ngx_http_geoip2_module 所需的 libmaxminddb.so.0
  echo ">> 下載並編譯 libmaxminddb 1.12.2"
  LIBMAX_VER=1.12.2
  curl -fL --retry 3 -o "libmaxminddb-$LIBMAX_VER.tar.gz" \
    "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAX_VER/libmaxminddb-$LIBMAX_VER.tar.gz"
  tar -xzf "libmaxminddb-$LIBMAX_VER.tar.gz"
  (
    cd "libmaxminddb-$LIBMAX_VER" && \
    ./configure && \
    make -j"$(nproc)" && \
    $SUDO make install
  )

  # 抓 PCRE2（使用官方釋出版，內含 configure/Makefile）
  echo ">> 下載 PCRE2 10.47 釋出版"
  curl -fL --retry 3 -o pcre2-10.47.tar.gz \
    "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.gz"
  tar -xzf pcre2-10.47.tar.gz

  # 抓 zlib (1.3.1)
  ZLIB_VER=1.3.1
  curl -fL --retry 3 -o "zlib-$ZLIB_VER.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz"
  tar -xzf "zlib-$ZLIB_VER.tar.gz"
  ZLIB_DIR="$BUILD_DIR/zlib-$ZLIB_VER"
  test -f "$ZLIB_DIR/configure" || { echo "zlib 原始碼目錄不正確"; exit 1; }

  # 抓 OpenSSL
  OPENSSL_VER=3.5.4 # 可修改
  curl -fL --retry 3 -o "openssl-$OPENSSL_VER.tar.gz" \
    "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"
  tar -xzf "openssl-$OPENSSL_VER.tar.gz"
  OPENSSL_DIR="$BUILD_DIR/openssl-$OPENSSL_VER"
  test -f "$OPENSSL_DIR/Configure" || { echo "OpenSSL 原始碼目錄不正確"; exit 1; }

  # ===== 初始化 / 建置 ngx_brotli 依賴的 brotli 靜態庫 =====
  echo ">> 初始化 ngx_brotli 子模組並建置 brotli 靜態庫"
  git -C "$BUILD_DIR/ngx_brotli" submodule update --init --recursive || true

  BROTLI_SRC="$BUILD_DIR/ngx_brotli/deps/brotli"
  BROTLI_OUT="$BROTLI_SRC/out"

  mkdir -p "$BROTLI_OUT"
  # 注意：-S 要用到 brotli 專案根目錄（有 CMakeLists.txt），不是 .../c
  cmake -S "$BROTLI_SRC" -B "$BROTLI_OUT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  cmake --build "$BROTLI_OUT" -j"$(nproc)"
}

module_D_build_nginx_and_base_init() {

  # ===== configure / make =====
  echo ">> configure Nginx"
  cd "$BUILD_DIR/nginx-${NGINX_VERSION}"
  make clean || true
  ./configure \
  --with-pcre="$BUILD_DIR/pcre2-10.47" \
  --with-pcre-jit \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/run/nginx.pid \
  --lock-path=/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=nginx --group=nginx \
  --with-compat --with-file-aio --with-threads \
  --with-http_addition_module --with-http_auth_request_module \
  --with-http_dav_module --with-http_flv_module --with-http_gunzip_module \
  --with-http_gzip_static_module --with-http_mp4_module \
  --with-http_random_index_module --with-http_realip_module \
  --with-http_secure_link_module --with-http_slice_module \
  --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module \
  --with-http_image_filter_module=dynamic \
  --with-http_v2_module --with-openssl="$OPENSSL_DIR" --with-http_v3_module \
  --with-http_xslt_module \
  --with-mail=dynamic --with-mail_ssl_module \
  --with-stream=dynamic --with-stream_realip_module \
  --with-stream_ssl_module --with-stream_ssl_preread_module \
  --with-cc-opt='-O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC' \
  --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed' \
  --add-dynamic-module="$BUILD_DIR/ngx_http_geoip2_module" \
  --add-dynamic-module="$BUILD_DIR/ngx_brotli" \
  --add-dynamic-module="$BUILD_DIR/headers-more-nginx-module" \
  --add-dynamic-module="$BUILD_DIR/ngx_cache_purge" \
  --add-dynamic-module="$BUILD_DIR/njs/nginx"

echo ">> make / make install"
make -j"$(nproc)"
$SUDO make install
make modules -j"$(nproc)"
$SUDO mkdir -p /usr/lib/nginx/modules
$SUDO cp objs/*.so /usr/lib/nginx/modules/

echo ">> 略過 GoAccess 安裝（將在安裝 WAF 時再處理）"

# 模組載入首次安裝：全載 + 存在檢查
echo ">> 初始化 Nginx 目錄與模組（首次安裝）"

# 基本目錄（http / stream / geoip / ssl / modules）
$SUDO mkdir -p \
  "$NGINX_ETC/conf.d" \
  "$NGINX_ETC/sites-available" \
  "$NGINX_ETC/sites-enabled" \
  "$NGINX_ETC/geoip" \
  "$NGINX_ETC/ssl" \
  "$NGINX_ETC/scripts"

$SUDO chmod 700 "$NGINX_ETC/ssl"

# Nginx cache/temp 目錄（對應 configure 中的 *_temp-path）
$SUDO mkdir -p \
  /var/cache/nginx/client_temp \
  /var/cache/nginx/proxy_temp \
  /var/cache/nginx/fastcgi_temp \
  /var/cache/nginx/uwsgi_temp \
  /var/cache/nginx/scgi_temp

# 確保 nginx 執行帳號與目錄權限
module_G_ensure_nginx_run_user

# 想載哪些 .so 就列在這裡；不存在就自動跳過
MODULES=(
  ngx_http_geoip2_module.so
  ngx_http_brotli_filter_module.so
  ngx_http_brotli_static_module.so
  ngx_http_headers_more_filter_module.so
  ngx_http_image_filter_module.so
  ngx_http_js_module.so
  ngx_stream_geoip2_module.so
  ngx_stream_js_module.so
)

# 重新生成模組設定（寫入 modules.conf，供 main context 載入）
MODULES_CONF="$NGINX_ETC/modules.conf"
$SUDO rm -f "$MODULES_CONF"
{
  for so in "${MODULES[@]}"; do
    if [ -f "/usr/lib/nginx/modules/$so" ]; then
      echo "load_module /usr/lib/nginx/modules/$so;"
    fi
  done
} | $SUDO tee "$MODULES_CONF" >/dev/null

# 確保 modules.conf 在 main context 被 include
if ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/modules\.conf;?' /etc/nginx/nginx.conf; then
  echo ">> 在 nginx.conf 最前加入 modules.conf include"
  $SUDO sed -i '1i include /etc/nginx/modules.conf;' /etc/nginx/nginx.conf
fi

# 建立 SSL 通用配置（如不存在）
if [ ! -f "$NGINX_ETC/conf.d/ssl.conf" ]; then
  echo ">> 建立 $NGINX_ETC/conf.d/ssl.conf"
  $SUDO tee "$NGINX_ETC/conf.d/ssl.conf" >/dev/null <<'SSL_CONF'
# SSL 設置
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
SSL_CONF
fi

# 確保 http{} 內有 include sites-enabled/*
if ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/sites-enabled/\*;?' /etc/nginx/nginx.conf; then
  echo ">> 在 nginx.conf http{} 內加入 sites-enabled include"
  if $SUDO grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/conf\.d/\*\.conf;?' /etc/nginx/nginx.conf; then
    $SUDO sed -i '/^[[:space:]]*include[[:space:]]\+\/etc\/nginx\/conf\.d\/\*\.conf;\?/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
  else
    $SUDO sed -i '/^[[:space:]]*http[[:space:]]*{/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
  fi
fi

if [ ! -f /etc/nginx/sites-available/default.conf ]; then
  echo ">> 建立 /etc/nginx/sites-available/default.conf 範例"
  $SUDO tee /etc/nginx/sites-available/default.conf >/dev/null <<'NG'
server {
    listen 80 default_server;
    #listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
}
NG
fi

if [ ! -e /etc/nginx/sites-enabled/default.conf ]; then
  echo ">> 建立 sites-enabled 預設符號連結"
  $SUDO ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf
fi

# 初始化 IP 白名單配置（如不存在，存放於 /etc/nginx/geoip）
if [ ! -f /etc/nginx/geoip/ip_whitelist.conf ]; then
  echo ">> 建立 /etc/nginx/geoip/ip_whitelist.conf 範例"
  $SUDO tee /etc/nginx/geoip/ip_whitelist.conf >/dev/null << 'NG'
# IP 白名單配置（由 /etc/nginx/scripts/manage_ip.sh 維護）
# 預設全部拒絕，按需加入 allow 規則
deny all;

# 範例：允許內網與單一 IP
#allow 192.168.1.0/24;
#allow 10.0.0.1;
NG
fi

# 初始化 IP 黑名單配置（如不存在，存放於 /etc/nginx/geoip）
if [ ! -f /etc/nginx/geoip/ip_blacklist.conf ]; then
  echo ">> 建立 /etc/nginx/geoip/ip_blacklist.conf 範例"
  $SUDO tee /etc/nginx/geoip/ip_blacklist.conf >/dev/null <<'BL'
# IP 黑名單配置
# 預設全部允許，按需加入 deny 規則
allow all;

# 範例：封鎖單一 IP 或網段
#deny 203.0.113.5;
#deny 198.51.100.0/24;
BL
fi

  # ===== 確認 Nginx binary 與語法正常，否則中止後續 GeoIP/更新腳本安裝 =====
  echo ">> 初次檢查 nginx 版本與語法"
  if ! command -v nginx >/dev/null 2>&1; then
    echo "錯誤：找不到 nginx 指令（安裝可能失敗），中止後續 GeoIP 安裝" >&2
    exit 1
  fi

  if ! $SUDO nginx -v >/dev/null 2>&1; then
    echo "錯誤：nginx -v 失敗，中止後續 GeoIP 安裝" >&2
    exit 1
  fi

  if ! $SUDO nginx -t; then
    echo "錯誤：nginx -t 失敗，中止後續 GeoIP 安裝" >&2
    exit 1
  fi
}

module_E_geoip_cloudflare_init() {
  # GeoIP2 mmdb
echo ">> 安裝 GeoIP2 mmdb"

COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"

$SUDO mkdir -p /usr/share/GeoIP
$SUDO wget -q -O /usr/share/GeoIP/GeoLite2-ASN.mmdb     "$ASN_URL"
$SUDO wget -q -O /usr/share/GeoIP/GeoLite2-City.mmdb    "$CITY_URL"
$SUDO wget -q -O /usr/share/GeoIP/GeoLite2-Country.mmdb "$COUNTRY_URL"

# Cloudflare IP初始化
  echo ">> 初始化 Cloudflare real_ip 與 conf.d/cloudflare.conf"
  $SUDO mkdir -p /etc/nginx/conf.d
  $SUDO install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
  TMP_CF="$(mktemp -d)"
  trap 'rm -rf "$TMP_CF"' EXIT
  curl -fsSL --retry 3 "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v4_realip.conf"
  curl -fsSL --retry 3 "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v6_realip.conf"
  $SUDO install -m0644 "$TMP_CF/cloudflare_v4_realip.conf" /etc/nginx/geoip/cloudflare_v4_realip.conf
  $SUDO install -m0644 "$TMP_CF/cloudflare_v6_realip.conf" /etc/nginx/geoip/cloudflare_v6_realip.conf

  $SUDO tee /etc/nginx/conf.d/cloudflare.conf >/dev/null << 'NG'

# Cloudflare / cloudflared real_ip & GeoIP2
include /etc/nginx/geoip/cloudflare_v4_realip.conf;
include /etc/nginx/geoip/cloudflare_v6_realip.conf;

#set_real_ip_from 172.20.0.0/16; # cloudflared 隧道 IP
#set_real_ip_from 127.0.0.1;

#real_ip_header X-Forwarded-For;
#real_ip_recursive on;

# GeoIP2
#geoip2_proxy_recursive on;
#geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb {
#auto_reload 5m;
#geoip2_metadata_country_build metadata build_epoch;
#$geoip2_data_country_code source=$remote_addr country iso_code;
$geoip2_data_country_name country names en;
}
geoip2 /usr/share/GeoIP/GeoLite2-City.mmdb {
$geoip2_data_city_name city names en;
$geoip2_data_city_longitude location longitude;
$geoip2_data_city_latitude location latitude;
}
NG
}

module_F_update_geoip_install_and_timer() {
  # 更新Geoip與Cloudflrae IP
  echo ">> 寫入 /etc/nginx/scripts/update_geoip.sh 每周三 六 03:00 跑"
  $SUDO tee /etc/nginx/scripts/update_geoip.sh >/dev/null <<'UPD'
#!/usr/bin/env bash
set -euo pipefail
GEOIP_MMDB_DIR="/usr/share/GeoIP"
GEOIP_CONF_DIR="/etc/nginx/geoip"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
UFW_SYNC="${UFW_SYNC:-0}"

mkdir -p "$GEOIP_MMDB_DIR" "$GEOIP_CONF_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

dl() {
  curl -fL --retry 3 -o "$TMP/$2" "$1" && install -m0644 "$TMP/$2" "$GEOIP_MMDB_DIR/$2"
}

# 1) mmdb
dl "$COUNTRY_URL" "GeoLite2-Country.mmdb" || true
dl "$CITY_URL"    "GeoLite2-City.mmdb"    || true
dl "$ASN_URL"     "GeoLite2-ASN.mmdb"     || true

# 2) CF real_ip（仍放在 /etc/nginx/geoip）
curl -fsSL --retry 3 "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cf4.conf"
curl -fsSL --retry 3 "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cf6.conf"
install -m0644 "$TMP/cf4.conf" "$GEOIP_CONF_DIR/cloudflare_v4_realip.conf"
install -m0644 "$TMP/cf6.conf" "$GEOIP_CONF_DIR/cloudflare_v6_realip.conf"

# 3) 重載 nginx:不再執行 nginx -t,只做 reload
if pgrep -x nginx >/dev/null 2>&1; then
  if nginx -s reload; then
    echo "[OK] nginx reloaded after GeoIP/Cloudflare update"
  else
    echo "[WARN] nginx reload 失敗，請手動檢查 nginx"
  fi
else
  echo "[INFO] nginx 未在執行，僅完成清單/DB 更新；略過 reload"
fi
UPD

$SUDO chmod +x /etc/nginx/scripts/update_geoip.sh

# 安排排程（systemd 優先，否則 /etc/cron.d，再否則 crontabs/root）
if command -v systemctl >/dev/null 2>&1; then
  echo ">> 使用 systemd timer 安排排程"
  $SUDO tee /etc/systemd/system/update-geoip.service >/dev/null <<'UNIT'
[Unit]
Description=Update GeoIP2 DB & Cloudflare real_ip lists (nginx reload)
[Service]
Type=oneshot
ExecStart=/etc/nginx/scripts/update_geoip.sh
UNIT

$SUDO tee /etc/systemd/system/update-geoip.timer >/dev/null <<'UNIT'
[Unit]
Description=Run update_geoip twice weekly at 03:00
[Timer]
OnCalendar=Wed,Sat 03:00
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
UNIT
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now update-geoip.timer
  systemctl list-timers | grep update-geoip || true
elif [ -d /etc/cron.d ]; then
  echo ">> 使用 /etc/cron.d 安排排程"
  echo '0 3 * * 3,6 root /etc/nginx/scripts/update_geoip.sh >/var/log/update_geoip.log 2>&1' | $SUDO tee /etc/cron.d/update_geoip >/dev/null
  $SUDO chmod 644 /etc/cron.d/update_geoip
  $SUDO systemctl reload cron 2>/dev/null || $SUDO systemctl reload crond 2>/dev/null || \
  $SUDO service cron reload 2>/dev/null || $SUDO service crond reload 2>/dev/null || true
else
  echo ">> BusyBox/Alpine：寫入 /etc/crontabs/root"
  $SUDO mkdir -p /etc/crontabs
  $SUDO sed -i '\#update_geoip.sh#d' /etc/crontabs/root 2>/dev/null || true
  echo '0 3 * * 3,6 /etc/nginx/scripts/update_geoip.sh >/var/log/update_geoip.log 2>&1' | $SUDO tee -a /etc/crontabs/root >/dev/null
  $SUDO service crond restart 2>/dev/null || $SUDO rc-service crond restart 2>/dev/null || true
fi
}

module_H_build_modsecurity_waf() {
  echo "==> 開始第二階段：編譯與啟用 ModSecurity WAF"

  local MODSEC_WORK NGX_MODULES_DIR MODSEC_DIR CONF_D_DIR
  MODSEC_WORK="${BUILD_DIR}/modsec_build"
  NGX_MODULES_DIR="/usr/lib/nginx/modules"
  MODSEC_DIR="/etc/nginx/modsecurity"
  CONF_D_DIR="/etc/nginx/conf.d"

  echo "==> 準備建置目錄：$MODSEC_WORK"
  rm -rf "$MODSEC_WORK"
  mkdir -p "$MODSEC_WORK"

  echo "==> 安裝/確認 libModSecurity v3 與必要套件"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -yq
    $SUDO apt-get install -yq libmodsecurity3 libmodsecurity-dev modsecurity-crs git build-essential curl
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache modsecurity modsecurity-dev modsecurity-rules-owasp-crs git build-base curl
  fi

  if ! ldconfig -p 2>/dev/null | grep -qi 'libmodsecurity\.so'; then
    echo "!! 找不到 libmodsecurity(libmodsecurity.so)。請確認 libmodsecurity 已安裝（含 -dev）。" >&2
    return 1
  fi

  echo "==> 取得 ModSecurity-nginx 連接器 v1.0.4"
  local MODSEC_NGX_VER MODSEC_NGX_DIR
  MODSEC_NGX_VER="v1.0.4"
  MODSEC_NGX_DIR="${MODSEC_WORK}/ModSecurity-nginx-${MODSEC_NGX_VER}"
  curl -fL --retry 3 -o "${MODSEC_WORK}/ModSecurity-nginx-${MODSEC_NGX_VER}.tar.gz" \
    "https://github.com/owasp-modsecurity/ModSecurity-nginx/releases/download/${MODSEC_NGX_VER}/ModSecurity-nginx-${MODSEC_NGX_VER}.tar.gz"
  tar -xzf "${MODSEC_WORK}/ModSecurity-nginx-${MODSEC_NGX_VER}.tar.gz" -C "$MODSEC_WORK"

  echo "==> 準備對應版本 Nginx 原始碼（用於編譯動態模組）"
  local NGINX_VER NGX_SRC
  NGINX_VER="$(nginx -v 2>&1 | sed -n 's/^nginx version: nginx\///p')"
  if [ -z "$NGINX_VER" ]; then
    echo "!! 無法取得 nginx 版本" >&2
    return 1
  fi

  NGX_SRC="${BUILD_DIR}/nginx-${NGINX_VER}"
  if [ ! -d "$NGX_SRC" ]; then
    echo "!! 找不到對應版本原始碼目錄: $NGX_SRC" >&2
    echo "   請先透過本腳本完成 Nginx 主程式編譯後再執行 WAF 階段。" >&2
    return 1
  fi

  echo "==> 讀取目前 nginx 的 configure 參數"
  local NGX_ARGS NGX_ARGS_CLEAN CONFIG_CMD
  NGX_ARGS="$(nginx -V 2>&1 | sed -n 's/^.*configure arguments: //p')"
  if [ -z "$NGX_ARGS" ]; then
    echo "!! 無法取得 configure arguments" >&2
    return 1
  fi
  NGX_ARGS_CLEAN="$(echo "$NGX_ARGS" \
    | sed -E 's/--with-openssl=[^ ]+//g; s/--with-pcre=[^ ]+//g; s/--with-zlib=[^ ]+//g; s/[[:space:]]+/ /g')"

  echo "==> 以目前參數重新 configure（僅建置 modules），加入 ModSecurity 連接器"
  cd "$NGX_SRC"
  make clean || true
  CONFIG_CMD="./configure $NGX_ARGS_CLEAN --add-dynamic-module=\"${MODSEC_NGX_DIR}\""
  echo "    執行：$CONFIG_CMD"
  eval "$CONFIG_CMD"
  make modules -j"$(nproc)"

  echo "==> 安裝 ngx_http_modsecurity_module.so -> ${NGX_MODULES_DIR}"
  $SUDO install -d -m 0755 "${NGX_MODULES_DIR}"
  if [ -f "objs/ngx_http_modsecurity_module.so" ]; then
    $SUDO install -m 0755 "objs/ngx_http_modsecurity_module.so" "${NGX_MODULES_DIR}/"
  else
    echo "!! 編譯失敗，找不到 objs/ngx_http_modsecurity_module.so" >&2
    return 1
  fi

  echo "==> 佈署 ModSecurity 與 CRS 設定"
  $SUDO install -d -m 0755 "$MODSEC_DIR"

  local LOG_DIR AUDIT_LOG
  LOG_DIR="/var/log/modsecurity"
  AUDIT_LOG="$LOG_DIR/audit.log"
  $SUDO install -d -m 0755 "$LOG_DIR"
  $SUDO touch "$AUDIT_LOG"

  local ACTIVE_CFG MPID CMD RUN_USER
  ACTIVE_CFG="/etc/nginx/nginx.conf"
  MPID=""
  if command -v pgrep >/dev/null 2>&1; then
    MPID="$(pgrep -f 'nginx: master process' | head -n1 || true)"
  fi
  [ -n "$MPID" ] || MPID="$(ps ax -o pid=,cmd= | awk '/nginx: master process/{print $1; exit}')"
  if [ -n "${MPID:-}" ] && [ -r "/proc/$MPID/cmdline" ]; then
    CMD="$(tr '\0' ' ' </proc/"$MPID"/cmdline)"
    if grep -q -- ' -c ' <<<"$CMD"; then
      ACTIVE_CFG="$(sed -n 's/.* -c \([^ ]\+\).*/\1/p' <<<"$CMD")"
    fi
  fi

  RUN_USER="$(awk '/^\s*user\s+/{print $2}' "$ACTIVE_CFG" 2>/dev/null | tr -d ' ;' | head -n1 || true)"
  [ -z "$RUN_USER" ] && RUN_USER="www-data"
  $SUDO chown "$RUN_USER:$RUN_USER" "$AUDIT_LOG" 2>/dev/null || true
  $SUDO install -d -m 0750 -o "$RUN_USER" -g "$RUN_USER" /var/cache/modsecurity

  local CORE_CONF TEMPLATES FOUND_TEMPLATE
  CORE_CONF="$MODSEC_DIR/modsecurity.conf"
  TEMPLATES=(
    /etc/modsecurity/modsecurity.conf-recommended
    /usr/local/etc/modsecurity.conf-recommended
    /usr/share/modsecurity-crs/modsecurity.conf-recommended
    /usr/share/doc/modsecurity-crs/examples/modsecurity.conf-recommended
  )
  FOUND_TEMPLATE=""
  for t in "${TEMPLATES[@]}"; do
    [ -f "$t" ] && { FOUND_TEMPLATE="$t"; break; }
  done

  if [ -n "$FOUND_TEMPLATE" ]; then
    echo "   - 使用樣板：$FOUND_TEMPLATE"
    $SUDO cp -f "$FOUND_TEMPLATE" "$CORE_CONF"
    $SUDO sed -i 's/^\s*SecRuleEngine\s\+.*/SecRuleEngine On/' "$CORE_CONF"
  else
    echo "   - 找不到樣板，寫入最小可用設定（fallback）"
    $SUDO tee "$CORE_CONF" >/dev/null <<'CONF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess Off
SecTmpDir /tmp
SecDataDir /var/cache/modsecurity
SecAuditEngine RelevantOnly
SecAuditLog /var/log/modsecurity/audit.log
SecAuditLogFormat JSON
SecAuditLogType Serial
SecAuditLogParts ABCEFHKZ
SecArgumentSeparator &
SecResponseBodyLimit 524288
SecRequestBodyLimit 268435456
SecRequestBodyNoFilesLimit 131072
SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000
CONF
  fi

  local CRS_DIR
  CRS_DIR=""
  for d in /usr/share/modsecurity-crs /etc/modsecurity/crs /usr/local/share/modsecurity-crs; do
    if [ -d "$d" ]; then CRS_DIR="$d"; break; fi
  done

  if [ -n "$CRS_DIR" ]; then
    echo "   - 偵測到 CRS: $CRS_DIR"
    $SUDO ln -sfn "$CRS_DIR" "$MODSEC_DIR/crs"
    if [ -f "$MODSEC_DIR/crs/crs-setup.conf.example" ] && [ ! -f "$MODSEC_DIR/crs/crs-setup.conf" ]; then
      $SUDO cp "$MODSEC_DIR/crs/crs-setup.conf.example" "$MODSEC_DIR/crs/crs-setup.conf"
    fi
    [ -f "$MODSEC_DIR/crs/crs-setup.conf" ] || echo "# minimal CRS setup" | $SUDO tee "$MODSEC_DIR/crs/crs-setup.conf" >/dev/null
    if [ ! -d "$MODSEC_DIR/crs/rules" ]; then
      echo "⚠️  未發現 $MODSEC_DIR/crs/rules，請確認 modsecurity-crs 是否完整安裝" >&2
    fi
  else
    echo "   - 未找到 CRS（之後可安裝 modsecurity-crs 套件再重載）"
  fi

  local MAIN_CONF
  MAIN_CONF="$MODSEC_DIR/main.conf"
  {
    echo "Include $CORE_CONF"
    if [ -n "$CRS_DIR" ]; then
      echo "Include $MODSEC_DIR/crs/crs-setup.conf"
      echo "Include $MODSEC_DIR/crs/rules/*.conf"
    fi
    echo "Include $MODSEC_DIR/local-exclusions.conf"
  } | $SUDO tee "$MAIN_CONF" >/dev/null

  $SUDO tee "$MODSEC_DIR/local-exclusions.conf" >/dev/null <<'EXC'
# 範例：排除 192.168.0.0/16 的 920440 規則（請依需求調整/刪除）
SecRule REMOTE_ADDR "@ipMatch 192.168.0.0/16" \
    "id:400000,phase:2,nolog,pass,ctl:ruleRemoveById=920440"
EXC

  $SUDO install -d -m 0755 "$CONF_D_DIR"
  $SUDO tee "$CONF_D_DIR/waf.conf" >/dev/null <<'NG'
# 載入 ModSecurity 動態模組
load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;

# 啟用 ModSecurity (http 區塊）
modsecurity on;
modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
NG

  echo "   - 主設定：$MAIN_CONF"
  echo "   - 啟用片段：$CONF_D_DIR/waf.conf"

  echo "==> 嘗試重載 Nginx（不執行 nginx -t）"
  if [ -n "${MPID:-}" ] && [ -f "$ACTIVE_CFG" ]; then
    if nginx -s reload; then
      echo "[OK] 已透過目前 master 進程重載 nginx"
    else
      echo "[WARN] 透過 master 進程重載失敗，請手動檢查 nginx"
    fi
  else
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
      if systemctl reload nginx; then
        echo "[OK] 已透過 systemctl reload nginx"
      else
        echo "[WARN] systemctl reload nginx 失敗，改用 nginx -s reload"
        nginx -s reload || echo "[WARN] nginx -s reload 失敗，請手動檢查 nginx"
      fi
    else
      nginx -s reload || nginx || echo "[WARN] nginx reload/start 失敗，請手動檢查 nginx 配置"
    fi
  fi

  echo
  echo "✅ 完成 ModSecurity v3 + CRS 啟用。"
  echo "   - 模組：${NGX_MODULES_DIR}/ngx_http_modsecurity_module.so（已自動載入）"
  echo "   - 核心設定：${CORE_CONF:-$MODSEC_DIR/modsecurity.conf}"
  echo "   - CRS：${CRS_DIR:-未安裝（已跳過 Include）}"
  echo "   - 包含檔：${MAIN_CONF}"
}

# 4) 設定 IP 白名單管理
# 創建 IP 管理腳本（集中在 /etc/nginx/scripts/manage_ip.sh）
$SUDO mkdir -p /etc/nginx/scripts
$SUDO tee /etc/nginx/scripts/manage_ip.sh >/dev/null <<'UPD'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: $0 <allow|deny> <IP地址> <配置文件路徑>" >&2
  echo "示例: $0 allow 192.168.1.100 /etc/nginx/conf.d/ip_whitelist.conf" >&2
}

if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

ACTION="$1"
IP_ADDRESS="$2"
CONFIG_FILE="$3"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "配置文件不存在: $CONFIG_FILE" >&2
  exit 1
fi

case "$ACTION" in
  allow)
    if grep -q "allow $IP_ADDRESS;" "$CONFIG_FILE"; then
      echo "IP $IP_ADDRESS 已在白名單中"
    else
      # 在 deny all; 之前插入 allow 規則
      sed -i "/deny all;/i\    allow $IP_ADDRESS;" "$CONFIG_FILE"
      echo "已添加 IP $IP_ADDRESS 到白名單"
    fi
    ;;
  deny)
    if grep -q "allow $IP_ADDRESS;" "$CONFIG_FILE"; then
      sed -i "/allow $IP_ADDRESS;/d" "$CONFIG_FILE"
      echo "已從白名單中移除 IP $IP_ADDRESS"
    else
      echo "IP $IP_ADDRESS 不在白名單中"
    fi
    ;;
  *)
    echo "無效的動作，請使用 'allow' 或 'deny'" >&2
    exit 1
    ;;
esac
UPD

$SUDO chmod +x /etc/nginx/scripts/manage_ip.sh

# 測試並重新加載 Nginx 配置（僅在系統已有 nginx 指令時執行）
if command -v nginx >/dev/null 2>&1; then
  if $SUDO nginx -t; then
    $SUDO systemctl reload nginx 2>/dev/null || $SUDO nginx -s reload || true
  fi
fi

module_G_ensure_nginx_run_user() {
  local RUN_USER RUN_GROUP
  RUN_USER="nginx"
  RUN_GROUP="nginx"
  getent group "$RUN_GROUP" >/dev/null 2>&1 || $SUDO groupadd --system "$RUN_GROUP"
  getent passwd "$RUN_USER" >/dev/null 2>&1 || $SUDO useradd --system --no-create-home \
    --shell /usr/sbin/nologin --gid "$RUN_GROUP" --home-dir /nonexistent "$RUN_USER"

  # 在主設定加入/修正 user 指令
  if grep -qE '^\s*user\s+' /etc/nginx/nginx.conf; then
    EXISTING_USER="$(awk '/^\s*user\s+/{print $2}' /etc/nginx/nginx.conf | tr -d ' ;')"
    if ! getent passwd "$EXISTING_USER" >/dev/null 2>&1; then
      $SUDO sed -i "s/^\s*user\s\+\S\+\s*;/user ${RUN_USER};/" /etc/nginx/nginx.conf
    fi
  else
    $SUDO sed -i "1a user ${RUN_USER};" /etc/nginx/nginx.conf
  fi

  # 建立 temp/cache 目錄並指定擁有者（對應你的 --http-*_temp-path）
  $SUDO install -d -m 0755 -o "$RUN_USER" -g "$RUN_GROUP" \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp
}

module_A_interactive_and_params
module_B_cleanup_and_stop_old_nginx
module_C_source_and_deps
module_D_build_nginx_and_base_init
module_E_geoip_cloudflare_init
module_F_update_geoip_install_and_timer
module_H_build_modsecurity_waf
install_nginx_systemd_service

# ===== 首次更新、驗證 =====
echo ">> 先啟動 Nginx（若尚未啟動）"
if command -v nginx >/dev/null 2>&1 && ! pgrep -x nginx >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl start nginx 2>/dev/null || $SUDO nginx || \
      echo "注意：Nginx 啟動失敗，請稍後手動檢查 /etc/nginx 配置"
  else
    $SUDO nginx || echo "注意：Nginx 啟動失敗，請稍後手動檢查 /etc/nginx 配置"
  fi
fi

# =====（apt 系列）鎖定 nginx 避免自動升級 =====
if command -v apt-mark >/dev/null 2>&1; then
  $SUDO apt-mark hold nginx || true
fi




echo ">> 完成！請手動檢查 /etc/nginx 配置，並重啟 Nginx"
echo ">> 完成後可執行「nginx -t」驗證配置"
echo ">> 完成後可執行「systemctl restart nginx」重啟 Nginx"
echo ">> 完成後可執行「systemctl status nginx」檢查狀態"
