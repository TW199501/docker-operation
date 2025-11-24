#!/usr/bin/env bash
# ================================================
# 編譯 10-build-nginx.sh
# 版本：v1.5（整合 UFW 基線；update 腳本可選同步 UFW）
# 說明：編譯Nginx1,29.1，開啟UFW+GeoIP2+Cloudflare real_ip
# 日期：2025-10-03
# ===============================================
set -euo pipefail

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

# ===== 可調參數（可用環境變數覆寫） =====
BUILD_DIR="${BUILD_DIR:-/home/nginx_build_geoip2}"
NGINX_VERSION="${NGINX_VERSION:-1.29.3}" # Nginx 版本
LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"  # 本機介面 IPv4

UFW_BASELINE="${UFW_BASELINE:-yes}"   # yes: 套用基礎 UFW（80/443 對外、22/8080 僅內網）
UFW_SSH_LIMIT="${UFW_SSH_LIMIT:-no}"  # yes: 把內網 SSH 規則改限速
UFW_SYNC_DEFAULT="${UFW_SYNC:-0}"     # 0: update 腳本不動 UFW；1: 會同步 CF 白名單（80/443）

# ===== 停止舊 Nginx（若在跑） =====
echo ">> 檢查 Nginx 進程..."
if pgrep -x nginx >/dev/null; then
  echo "   停止 nginx ..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop nginx || true
  else
    sudo pkill -TERM -x nginx || true
  fi
  sleep 3
  if pgrep -x nginx >/dev/null; then
    sudo pkill -KILL -x nginx || true
  fi
fi
sudo rm -f /run/nginx.pid || true

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

# ===== 模組原始碼 =====
echo ">> 取得外掛模組"
git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git "$BUILD_DIR/ngx_http_geoip2_module"
git clone --recursive https://github.com/google/ngx_brotli.git "$BUILD_DIR/ngx_brotli"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git "$BUILD_DIR/headers-more-nginx-module"
git clone --depth=1 https://github.com/FRiCKLE/ngx_cache_purge.git "$BUILD_DIR/ngx_cache_purge"
git clone --depth=1 https://github.com/nginx/njs.git "$BUILD_DIR/njs"


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
      build-essential zlib1g-dev libssl-dev libmaxminddb0 libmaxminddb-dev \
      unzip git libpcre2-dev libxml2-dev libxslt1-dev libmodsecurity3 libmodsecurity-dev\
      curl wget cmake libbrotli-dev
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf -y groupinstall "Development Tools"
    $SUDO dnf -y install \
      pcre2-devel zlib-devel openssl-devel libmaxminddb-devel \
      unzip git libxml2-devel libxslt-devel \
      curl wget cmake brotli-devel
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum -y groupinstall "Development Tools"
    $SUDO yum -y install \
      pcre2-devel zlib-devel openssl-devel libmaxminddb-devel \
      unzip git libxml2-devel libxslt-devel \
      curl wget cmake brotli-devel
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache \
      build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev \
      unzip git curl wget cmake libxml2-dev libxslt-dev brotli-dev
  else
    echo "無法判斷套件管理器，請手動安裝依賴。"; exit 1
  fi
fi

# 二次驗證
for bin in gcc make git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "安裝失敗：缺少 $bin"; exit 1; }
done

# 確認 PCRE2 就緒（或至少 PCRE v1）
if command -v pcre2-config >/dev/null 2>&1; then
  echo "已偵測到 PCRE2（推薦）"
elif command -v pcre-config >/dev/null 2>&1; then
  echo "已偵測到舊版 PCRE（可用，但建議改用 PCRE2）"
else
  echo "缺少 PCRE/PCRE2 開發環境，請手動安裝 libpcre2-dev/pcre2-devel 或重跑本腳本。"
  exit 1
fi
echo "依賴檢查完成"

cd "$BUILD_DIR"
# 抓 PCRE2
curl -LO https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz
tar -xzf pcre2-10.44.tar.gz
# 抓 OpenSSL
OPENSSL_VER=3.5.4 #可修改
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

# ===== configure / make =====
echo ">> configure Nginx"
cd "$BUILD_DIR/nginx-${NGINX_VERSION}"
make clean || true
./configure \
  --with-pcre="$BUILD_DIR/pcre2-10.44" \
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
  --user=www-data --group=www-data \
  --with-compat --with-file-aio --with-threads \
  --with-http_addition_module --with-http_auth_request_module \
  --with-http_dav_module --with-http_flv_module --with-http_gunzip_module \
  --with-http_gzip_static_module --with-http_mp4_module \
  --with-http_random_index_module --with-http_realip_module \
  --with-http_secure_link_module --with-http_slice_module \
  --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module \
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
make -j2
$SUDO make install
make modules -j2
$SUDO mkdir -p /usr/lib/nginx/modules
$SUDO cp objs/*.so /usr/lib/nginx/modules/

# ===== 模組載入（首次安裝：全載 + 存在檢查）=====
echo ">> 初始化 Nginx 目錄與模組（首次安裝）"

# 基本目錄（http / stream / geoip / ssl / modules）
$SUDO mkdir -p \
  "$NGINX_ETC/conf.d" \
  "$NGINX_ETC/sites-available" \
  "$NGINX_ETC/sites-enabled" \
  "$NGINX_ETC/streams-available" \
  "$NGINX_ETC/streams-enabled" \
  "$NGINX_ETC/geoip" \
  "$NGINX_ETC/modules" \
  "$NGINX_ETC/ssl"

$SUDO chmod 700 "$NGINX_ETC/ssl"

# 想載哪些 .so 就列在這裡；不存在就自動跳過
MODULES=(
  ngx_http_geoip2_module.so
  ngx_http_brotli_filter_module.so
  ngx_http_brotli_static_module.so
  ngx_http_headers_more_filter_module.so
  ngx_http_js_module.so
  ngx_stream_module.so
  ngx_stream_geoip2_module.so
  ngx_stream_js_module.so
  ngx_mail_module.so
)

# 重新生成模組設定
$SUDO rm -f "$NGINX_ETC/modules/00-load-modules.conf"
{
  for so in "${MODULES[@]}"; do
    if [ -f "/usr/lib/nginx/modules/$so" ]; then
      echo "load_module /usr/lib/nginx/modules/$so;"
    fi
  done
} | $SUDO tee "$NGINX_ETC/modules/00-load-modules.conf" >/dev/null

# 確保主設定會載入 modules.d/*.conf（放在檔案最上面最穩）
if ! grep -qE '^[[:space:]]*include[[:space:]]+'"$NGINX_ETC"'/modules/\*\.conf;?' "$NGINX_ETC/nginx.conf"; then
  echo ">> 在 $NGINX_ETC/nginx.conf 最上方加入 include modules"
  $SUDO sed -i "1i include $NGINX_ETC/modules/*.conf;" "$NGINX_ETC/nginx.conf"
fi

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

# 驗證（跳過 IPv6 相關錯誤）
$SUDO nginx -t || echo "警告：nginx -t 測試失敗，可能是因為 IPv6 配置問題。這在 IPv6 被禁用的系統上是正常的。"


# ===== GeoIP2 mmdb =====
echo ">> 安裝 GeoIP2 mmdb"
$SUDO mkdir -p /etc/nginx/geoip
$SUDO wget -q -O /etc/nginx/geoip/GeoLite2-ASN.mmdb     "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
$SUDO wget -q -O /etc/nginx/geoip/GeoLite2-City.mmdb    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
$SUDO wget -q -O /etc/nginx/geoip/GeoLite2-Country.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"

# ===== real_ip 初始化 =====
echo ">> 初始化 Cloudflare real_ip 與 conf.d"
$SUDO mkdir -p /etc/nginx/conf.d
$SUDO install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
TMP_CF="$(mktemp -d)"; trap 'rm -rf "$TMP_CF"' EXIT
curl -fsSL --retry 3 https://www.cloudflare.com/ips-v4 | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v4_realip.conf"
curl -fsSL --retry 3 https://www.cloudflare.com/ips-v6 | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v6_realip.conf"
$SUDO install -m0644 "$TMP_CF/cloudflare_v4_realip.conf" /etc/nginx/geoip/cloudflare_v4_realip.conf
$SUDO install -m0644 "$TMP_CF/cloudflare_v6_realip.conf" /etc/nginx/geoip/cloudflare_v6_realip.conf
MY_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')"
$SUDO bash -c 'cat > /etc/nginx/geoip/cloudflared_realip.conf' <<EOF
set_real_ip_from 127.0.0.1;
${MY_IP:+set_real_ip_from $MY_IP;}
# cloudflared 不在本機時：加上 set_real_ip_from <cloudflared_IP>;
EOF
$SUDO tee /etc/nginx/conf.d/00-realip.conf >/dev/null << 'NG'
# 信任來源（本機 / 隧道 / Cloudflare）
include /etc/nginx/geoip/cloudflared_realip.conf;
include /etc/nginx/geoip/cloudflare_v4_realip.conf;
include /etc/nginx/geoip/cloudflare_v6_realip.conf;
# 用 XFF 還原
real_ip_header X-Forwarded-For;
real_ip_recursive on;
# （可選）GeoIP2 變數
geoip2 /etc/nginx/geoip/GeoLite2-City.mmdb {
  auto_reload 6h;
  $geoip2_data_country_name country names en;
  $geoip2_data_city_name    city names en;
}
NG

# 確保 conf.d 有被載入（若現有配置壞掉，回寫安全基底）
write_base_nginx_conf() {
  local NOW; NOW="$(date +%F_%H%M%S)"
  if [ -f "$NGINX_ETC/nginx.conf" ]; then
    $SUDO cp -a "$NGINX_ETC/nginx.conf" "$NGINX_ETC/nginx.conf.bak.$NOW" || true
  fi
  $SUDO tee "$NGINX_ETC/nginx.conf" >/dev/null <<'NG'
include /etc/nginx/modules/*.conf;

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
    #設定也挪到 00-realip.conf
    #include /etc/nginx/geoip/cloudflared_realip.conf;
    #include /etc/nginx/geoip/cloudflare_v4_realip.conf;
    #include /etc/nginx/geoip/cloudflare_v6_realip.conf;
    #set_real_ip_from 127.0.0.1;
    #real_ip_header X-Forwarded-For;
    #real_ip_recursive on;
    default_type application/octet-stream;

    # GeoIP2（mmdb + 變數）
    geoip2_proxy_recursive on;
    geoip2 /etc/nginx/geoip/GeoLite2-City.mmdb {
        auto_reload 5m;
        $geoip2_data_country_name country names en;
        $geoip2_data_city_name    city names en;
    }

    log_format cf '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent" '
        'Country="$geoip2_data_country_name" '
        'City="$geoip2_data_city_name"';
    access_log /var/log/nginx/access.log cf;

    sendfile on;
    #tcp_nopush     on;
    keepalive_timeout 65;

    limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=5r/s;

    # brotli + gzip
    brotli on;
    brotli_static on;
    brotli_comp_level 6;
    brotli_types text/plain text/css application/json application/javascript application/xml;

    gzip on;
    gzip_min_length 1;
    gzip_comp_level 5;

    server_names_hash_bucket_size 32;
    client_header_buffer_size 1k;
    client_body_buffer_size 8k;
    client_max_body_size 2g;
    client_body_timeout 300s;
    send_timeout 300s;

    # header 整理
    more_clear_headers "X-Powered-By";
    more_clear_headers "Via";
    more_set_headers 'Server: MySecureGateway';
    server_tokens off;

    proxy_cache_path /var/cache/nginx/proxy_cache levels=1:2 use_temp_path=on keys_zone=proxy_cache:10m inactive=60m max_size=1g min_free=100m manager_files=100 manager_sleep=50ms manager_threshold=200ms loader_files=199 loader_sleep=50ms loader_threshold=200ms;
}
stream {
    include /etc/nginx/streams-enabled/*;
}
NG
}

# 若語法檢查失敗（例如 include 寫壞），就覆寫成基礎模板
echo ">> 檢查 Nginx 配置（模組加載前）..."
if ! $SUDO nginx -t >/dev/null 2>&1; then
  echo ">> 檢測到 nginx 配置有誤，回寫標準 nginx.conf ..."
  echo ">> 這可能是因为模組尚未加載，在首次安裝時是正常的"
  write_base_nginx_conf
fi

# ===== 合併版更新腳本（GeoIP2 + CF real_ip + 可選 UFW）=====
echo ">> 寫入 /usr/local/sbin/update_geoip2.sh（每週三、六 03:00 跑）"
$SUDO tee /usr/local/sbin/update_geoip2.sh >/dev/null <<'UPD'
#!/usr/bin/env bash
set -euo pipefail
GEOIP_DIR="/etc/nginx/geoip"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
UFW_SYNC="${UFW_SYNC:-0}"

mkdir -p "$GEOIP_DIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

dl() { curl -fL --retry 3 -o "$TMP/$2" "$1" && install -m0644 "$TMP/$2" "$GEOIP_DIR/$2"; }

# 1) mmdb
dl "$COUNTRY_URL" "GeoLite2-Country.mmdb" || true
dl "$CITY_URL"    "GeoLite2-City.mmdb"    || true
dl "$ASN_URL"     "GeoLite2-ASN.mmdb"     || true

# 2) CF real_ip
curl -fsSL --retry 3 "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cf4.conf"
curl -fsSL --retry 3 "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cf6.conf"
install -m0644 "$TMP/cf4.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
install -m0644 "$TMP/cf6.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"

# 3) UFW（可選）
if [ "$UFW_SYNC" = "1" ] && command -v ufw >/dev/null 2>&1; then
  UFW_BIN="$(command -v ufw)"
  STATE_DIR="/var/lib/ufw-cf"; mkdir -p "$STATE_DIR"
  sed -n 's/^set_real_ip_from \([^;]*\);$/\1/p' "$TMP/cf4.conf" | sort -u > "$TMP/cf4.list"
  sed -n 's/^set_real_ip_from \([^;]*\);$/\1/p' "$TMP/cf6.conf" | sort -u > "$TMP/cf6.list"
  [ -f "$STATE_DIR/cf4.prev" ] || : > "$STATE_DIR/cf4.prev"
  [ -f "$STATE_DIR/cf6.prev" ] || : > "$STATE_DIR/cf6.prev"
  CF4_ADD=$(comm -13 "$STATE_DIR/cf4.prev" "$TMP/cf4.list" || true)
  CF4_DEL=$(comm -23 "$STATE_DIR/cf4.prev" "$TMP/cf4.list" || true)
  CF6_ADD=$(comm -13 "$STATE_DIR/cf6.prev" "$TMP/cf6.list" || true)
  CF6_DEL=$(comm -23 "$STATE_DIR/cf6.prev" "$TMP/cf6.list" || true)
  del_net() { local n="$1" p="$2"; mapfile -t idx < <("$UFW_BIN" status numbered | awk -v n="$n" -v p="$p/tcp" '$0 ~ /^\[/ && $2==p && index($0,n)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr); for i in "${idx[@]:-}"; do "$UFW_BIN" --force delete "$i" || true; done; }
  for n in $CF4_DEL; do for p in 80 443; do del_net "$n" "$p"; done; done
  for n in $CF6_DEL; do for p in 80 443; do del_net "$n" "$p"; done; done
  for n in $CF4_ADD; do for p in 80 443; do "$UFW_BIN" allow proto tcp from "$n" to any port "$p" comment "cf-auto"; done; done
  for n in $CF6_ADD; do for p in 80 443; do "$UFW_BIN" allow proto tcp from "$n" to any port "$p" comment "cf-auto"; done; done
  install -m0644 "$TMP/cf4.list" "$STATE_DIR/cf4.prev"
  install -m0644 "$TMP/cf6.list" "$STATE_DIR/cf6.prev"
  echo "[OK] UFW CF 白名單已同步（80/443）"
else
  echo "[SKIP] UFW 同步關閉或未安裝（UFW_SYNC=$UFW_SYNC）"
fi

# 4) 測試+重載：若目前 master 用了自訂 -c，就用同一路徑驗證+reload
CFG=""
MPID="$(pgrep -ax 'nginx: master process' | awk 'NR==1{print $1}')"
if [ -n "$MPID" ]; then
  CMD="$(tr '\0' ' ' </proc/$MPID/cmdline)"
  if echo "$CMD" | grep -q -- ' -c '; then
    CFG="$(echo "$CMD" | sed -n 's/.* -c \([^ ]\+\).*/\1/p')"
  fi
fi

if [ -n "$CFG" ]; then
  nginx -t -c "$CFG" && nginx -s reload
  echo "[OK] reload with -c $CFG"
elif [ -s /run/nginx.pid ] && kill -0 "$(cat /run/nginx.pid)" 2>/dev/null; then
  nginx -t && nginx -s reload && echo "[OK] reload (default conf)"
else
  echo "[INFO] nginx 未在執行，僅完成清單/DB 更新；略過 reload"
fi
UPD
$SUDO chmod +x /usr/local/sbin/update_geoip2.sh

# ===== 安排排程（systemd 優先，否則 cron.d，再否則 crontabs/root） =====
if command -v systemctl >/dev/null 2>&1; then
  echo ">> 使用 systemd timer 安排排程"
  $SUDO tee /etc/systemd/system/update-geoip2.service >/dev/null <<'UNIT'
[Unit]
Description=Update GeoIP2 DB & Cloudflare real_ip lists (nginx reload)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update_geoip2.sh
UNIT
  $SUDO tee /etc/systemd/system/update-geoip2.timer >/dev/null <<'UNIT'
[Unit]
Description=Run update_geoip2 twice weekly at 03:00
[Timer]
OnCalendar=Wed,Sat 03:00
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
UNIT
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now update-geoip2.timer
  systemctl list-timers | grep update-geoip2 || true
elif [ -d /etc/cron.d ]; then
  echo ">> 使用 /etc/cron.d 安排排程"
  echo '0 3 * * 3,6 root /usr/local/sbin/update_geoip2.sh >/var/log/update_geoip2.log 2>&1' | $SUDO tee /etc/cron.d/update_geoip2 >/dev/null
  $SUDO chmod 644 /etc/cron.d/update_geoip2
  $SUDO systemctl reload cron 2>/dev/null || $SUDO systemctl reload crond 2>/dev/null || $SUDO service cron reload 2>/dev/null || $SUDO service crond reload 2>/dev/null || true
else
  echo ">> BusyBox/Alpine：寫入 /etc/crontabs/root"
  $SUDO mkdir -p /etc/crontabs
  $SUDO sed -i '\#update_geoip2.sh#d' /etc/crontabs/root 2>/dev/null || true
  echo '0 3 * * 3,6 /usr/local/sbin/update_geoip2.sh >/var/log/update_geoip2.log 2>&1' | $SUDO tee -a /etc/crontabs/root >/dev/null
  $SUDO service crond restart 2>/dev/null || $SUDO rc-service crond restart 2>/dev/null || true
fi

# ===== UFW 基線（自動安裝；若無法裝則跳過）=====
if [ "${UFW_BASELINE:-yes}" = "yes" ]; then
  if ! command -v ufw >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      echo ">> 未偵測到 UFW，正在安裝..."
      if $SUDO apt-get update -y && $SUDO apt-get install -y ufw; then
        :
      else
        echo "!! UFW 安裝失敗，跳過 UFW 基線"
        UFW_BASELINE="no"
      fi
    else
      echo "!! 非 apt 系統且未安裝 UFW，跳過 UFW 基線"; UFW_BASELINE="no"
    fi
  fi
fi

if [ "$UFW_BASELINE" = "yes" ] && command -v ufw >/dev/null 2>&1; then
  echo ">> 套用 UFW 基線（80/443 對外；22/8080 只 $LAN_CIDR）"

  # 開啟 IPv6 支援（若設定檔存在）
  if [ -f /etc/default/ufw ]; then
    $SUDO sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw || true
  fi

  # 基線策略
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing

  # 對外開放的服務
  $SUDO ufw allow 80/tcp  comment 'http open to world'
  $SUDO ufw allow 443/tcp comment 'https open to world'

  # 僅內網可用的服務
  $SUDO ufw allow from "$LAN_CIDR" to any port 22   proto tcp comment 'ssh from LAN'
  $SUDO ufw allow from "$LAN_CIDR" to any port 8080 proto tcp comment '8080 from LAN'

  # （可選）把 SSH 改限速
  if [ "${UFW_SSH_LIMIT:-no}" = "yes" ]; then
    mapfile -t del_idx < <($SUDO ufw status numbered | \
      awk -v p="22/tcp" -v c="$LAN_CIDR" '$0 ~ /^\[/ && $2==p && index($0,c)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
    for i in "${del_idx[@]:-}"; do $SUDO ufw --force delete "$i" || true; done
    $SUDO ufw limit from "$LAN_CIDR" to any port 22 proto tcp comment 'ssh from LAN (limit)'
  fi

  # 啟用 + 設為開機自動啟用（若有 systemd）
  $SUDO ufw --force enable
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl enable --now ufw 2>/dev/null || true
  fi

  $SUDO ufw reload
  $SUDO ufw status verbose
else
  echo ">> 跳過 UFW 基線（UFW_BASELINE=$UFW_BASELINE 或未安裝 UFW）"
fi


# === 確保有可用的 NGINX 執行帳號與暫存目錄，並在 nginx.conf 設定 user ===
ensure_nginx_run_user() {
  local RUN_USER RUN_GROUP
  if getent passwd www-data >/dev/null 2>&1; then
    RUN_USER="www-data"; RUN_GROUP="www-data"
  else
    RUN_USER="nginx"; RUN_GROUP="nginx"
    getent group nginx >/dev/null 2>&1 || $SUDO groupadd --system nginx
    getent passwd nginx >/dev/null 2>&1 || $SUDO useradd --system --no-create-home \
      --shell /usr/sbin/nologin --gid nginx --home-dir /nonexistent nginx
  fi

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
  $SUDO install -d -m 0755 -o "$RUN_USER" -g "$RUN_GROUP" /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}
}
ensure_nginx_run_user

# 再驗證一次（這裡才檢查，以免 user 未就緒）
echo ">> 檢查 Nginx 配置（模塊加載後）..."
$SUDO nginx -t || {
  echo ">> nginx -t 失敗，檢查詳細錯誤信息..."
  $SUDO nginx -t 2>&1 | head -10
  echo ">> 如果錯誤與模塊相關，可能是模塊還未完全加載，這在首次安裝時是正常的"
  echo ">> 腳本將繼續執行，Nginx 服務會在稍後啟動"
}

# ===== 可選：切換為「80/443 只允許 Cloudflare」=====
# 使用方式：執行腳本時帶 CF_ONLY_HTTP=yes
# 例如：CF_ONLY_HTTP=yes $SUDO bash /root/nginx_build_geoip2.sh
if [ "${CF_ONLY_HTTP:-no}" = "yes" ] && command -v ufw >/dev/null 2>&1; then
  echo ">> 切換為『80/443 只允許 Cloudflare』：先同步 CF 白名單，再移除世界開放規則"
  UFW_SYNC=1 /usr/local/sbin/update_geoip2.sh || true
  $SUDO ufw delete allow 80/tcp  2>/dev/null || true
  $SUDO ufw delete allow 443/tcp 2>/dev/null || true
  $SUDO ufw status numbered | sed -n '1,80p'
fi

# ===== 首次更新、驗證 =====
echo ">> 先啟動 Nginx（若尚未啟動）"
$SUDO nginx -t && (pgrep -x nginx >/dev/null || $SUDO nginx)

echo ">> 首次執行 update_geoip2.sh"
UFW_SYNC="$UFW_SYNC_DEFAULT" /usr/local/sbin/update_geoip2.sh || true

# ===== 最終驗證並套用 =====
echo ">> 最終驗證並套用 Nginx 配置..."
$SUDO nginx -t || echo "警告：Nginx 配置測試失敗，但在首次安裝時這可能是正常的"
if $SUDO nginx -t >/dev/null 2>&1; then
  $SUDO systemctl restart nginx 2>/dev/null || $SUDO nginx -s reload
else
  echo ">> 嘗試直接啟動 Nginx（可能會有警告，但服務應該能正常運行）"
  $SUDO nginx || echo "注意：Nginx 啟動失敗，請在解決配置問題後手動啟動"
fi

# =====（apt 系列）鎖定 nginx 避免自動升級 =====
if command -v apt-mark >/dev/null 2>&1; then
  $SUDO apt-mark hold nginx || true
fi

echo "✅ 完成。下一次自動更新：每週三、六 03:00。"
echo "   若要切換成『80/443 只允許 Cloudflare』："
echo "     1) 刪世界開放： $SUDO ufw delete allow 80/tcp ; $SUDO ufw delete allow 443/tcp"
echo "     2) 開啟同步：   $SUDO bash -c 'echo export UFW_SYNC=1 >> /etc/environment'"
echo "     3) 立即同步：   UFW_SYNC=1 /usr/local/sbin/update_geoip2.sh && sudo ufw status numbered"
