#!/bin/bash
=================================================
# 編譯Nginx與下載下載 GeoIP2 資料庫
# 版本：v1.0
# 作者：楊清雲
# 日期：2025-04-18
=================================================
set -e

# === 預設變數 ===
BUILD_DIR="/home/nginx_build_geoip2"
NGINX_VERSION="1.26.3"

# === 處理傳入參數 ===
for ARG in "$@"; do
    case $ARG in
        --path=*) BUILD_DIR="${ARG#*=}" ;;
        --version=*) NGINX_VERSION="${ARG#*=}" ;;
        *) echo "未知參數：$ARG"; exit 1 ;;
    esac
done

# === 強制移除舊版 nginx ===
echo "移除 nginx 與模組..."
sudo pkill -9 nginx || true
sudo rm -f /run/nginx.pid
sudo apt remove --purge -y --allow-change-held-packages nginx nginx-core nginx-common libnginx-mod-* || true
sudo rm -rf /etc/nginx /usr/lib/nginx /var/log/nginx /usr/share/nginx /var/lib/nginx

# === 建立建置目錄 ===
echo "建立建置目錄 $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# === 下載與解壓 NGINX 原始碼 ===
wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
tar -xzf "nginx-${NGINX_VERSION}.tar.gz"

# === Clone 所需模組 ===
git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git "$BUILD_DIR/ngx_http_geoip2_module"
git clone --recursive https://github.com/google/ngx_brotli.git "$BUILD_DIR/ngx_brotli"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git "$BUILD_DIR/headers-more-nginx-module"
git clone --depth=1 https://github.com/FRiCKLE/ngx_cache_purge.git "$BUILD_DIR/ngx_cache_purge"
git clone --depth=1 https://github.com/nginx/njs.git "$BUILD_DIR/njs"

# === 安裝編譯相關依賴 ===
sudo apt update && sudo apt install -y build-essential libpcre3-dev zlib1g-dev libssl-dev libmaxminddb-dev unzip git 

# === 執行 configure 編譯 ===
cd "$BUILD_DIR/nginx-${NGINX_VERSION}"

./configure \
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
  --user=nginx \
  --group=nginx \
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-mail=dynamic \
  --with-mail_ssl_module \
  --with-stream=dynamic \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-cc-opt="-O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC" \
  --with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed" \
  --add-dynamic-module="$BUILD_DIR/ngx_http_geoip2_module" \
  --add-dynamic-module="$BUILD_DIR/ngx_brotli" \
  --add-dynamic-module="$BUILD_DIR/headers-more-nginx-module"  \
  --add-dynamic-module="$BUILD_DIR/ngx_cache_purge" \
  --add-dynamic-module="$BUILD_DIR/njs/nginx"

# === 建置與安裝 NGINX 與模組 ===
make -j$(nproc)
sudo make install
make modules -j$(nproc)
sudo mkdir -p /usr/lib/nginx/modules
sudo cp objs/*.so /usr/lib/nginx/modules/

# === 建立模組載入設定檔 ===
sudo mkdir -p /etc/nginx/modules.d
sudo tee /etc/nginx/modules.d/00-load-geoip2.conf >/dev/null << EOF
load_module /usr/lib/nginx/modules/ngx_http_geoip2_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;
load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_js_module.so;
EOF

# === 安裝 GeoIP2 資料庫 ===
sudo mkdir -p /etc/nginx/geoip
sudo wget -q -O /etc/nginx/geoip/GeoLite2-Country.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
sudo wget -q -O /etc/nginx/geoip/GeoLite2-City.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"


# === 設定自動更新腳本 ===
sudo tee /etc/nginx/geoip/update_geoip2.sh >/dev/null <<'EOF'

GEOIP_DIR="/etc/nginx/geoip"
TMP_DIR="/tmp/geoip2_update"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"

mkdir -p "$TMP_DIR"
wget -q -O "$TMP_DIR/GeoLite2-Country.mmdb" "$COUNTRY_URL"
[ -s "$TMP_DIR/GeoLite2-Country.mmdb" ] && mv "$TMP_DIR/GeoLite2-Country.mmdb" "$GEOIP_DIR/"
wget -q -O "$TMP_DIR/GeoLite2-City.mmdb" "$CITY_URL"
[ -s "$TMP_DIR/GeoLite2-City.mmdb" ] && mv "$TMP_DIR/GeoLite2-City.mmdb" "$GEOIP_DIR/"
EOF
# === 鎖定 nginx 套件避免自動升級 ===
sudo apt-mark hold nginx

echo "NGINX 安裝與模組編譯完成，請確認 nginx.conf 中加入 include /etc/nginx/modules.d/*.conf; 並重新啟動 nginx"
