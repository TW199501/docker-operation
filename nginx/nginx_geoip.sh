#!/bin/bash
# ================================================
# 編譯Nginx與下載下載 GeoIP2 資料庫
# 版本：v1.3
# 作者：楊清雲
# 日期：2025-10-02
# ===============================================
set -e

# === 預設變數 ===
BUILD_DIR="/home/nginx_build_geoip2"
NGINX_VERSION="1.29.1" #可修改

# === 處理傳入參數 ===
for ARG in "$@"; do
    case $ARG in
        --path=*) BUILD_DIR="${ARG#*=}" ;;
        --version=*) NGINX_VERSION="${ARG#*=}" ;;
        *) echo "未知參數：$ARG"; exit 1 ;;
    esac
done

# === 強制移除舊版 nginx ===
echo "檢查是否有正在運行的 nginx 進程..."
if pgrep -x nginx > /dev/null; then
  echo "停止 nginx 進程..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop nginx || true
  else
    sudo pkill -TERM -x nginx || true
  fi

  sleep 5
  if pgrep -x nginx > /dev/null; then
    echo "仍有 nginx 進程在運行，強制終止..."
    sudo pkill -KILL -x nginx || true
    sleep 2
  fi
else
  echo "沒有發現運行中的 nginx 進程"
fi
# 清理PID文件
sudo rm -f /run/nginx.pid || true

echo "清理完成"

# 注意：我們暫時跳過包管理器操作，因為這可能是導致問題的原因

# === 建立建置目錄 ===
echo "建立建置目錄 $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || { echo "無法進入目錄 $BUILD_DIR"; exit 1; }
echo "當前工作目錄: $(pwd)"

# === 下載與解壓 NGINX 原始碼 ===
wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
tar -xzf "nginx-${NGINX_VERSION}.tar.gz"

# === Clone 所需模組 ===
git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git "$BUILD_DIR/ngx_http_geoip2_module"
git clone --recursive https://github.com/google/ngx_brotli.git "$BUILD_DIR/ngx_brotli"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git "$BUILD_DIR/headers-more-nginx-module"
git clone --depth=1 https://github.com/FRiCKLE/ngx_cache_purge.git "$BUILD_DIR/ngx_cache_purge"
git clone --depth=1 https://github.com/nginx/njs.git "$BUILD_DIR/njs"

# === 檢查編譯相關依賴 ===
echo "檢查編譯相關依賴..."
if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
  echo "警告: 缺少必要的編譯工具 (gcc, make)"
  echo "請手動安裝: sudo apt update && sudo apt install -y build-essential zlib1g-dev libssl-dev libmaxminddb-dev unzip git libpcre2-dev"
  exit 1
fi

# 檢查 PCRE / PCRE2 是否就緒（至少其一）
if command -v pcre2-config >/dev/null 2>&1; then
  echo "已偵測到 PCRE2（推薦）"
elif command -v pcre-config >/dev/null 2>&1; then
  echo "已偵測到舊版 PCRE（可用，但建議改用 PCRE2）"
else
  echo "缺少 PCRE/PCRE2。建議：sudo apt install libpcre2-dev"
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

# === 執行 configure 編譯 ===
cd "$BUILD_DIR/nginx-${NGINX_VERSION}"
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
  --with-openssl="$OPENSSL_DIR" \
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
echo "開始編譯 Nginx (使用2個核心以避免資源不足)..."
make -j2
sudo make install
make modules -j2
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
sudo wget -q -O /etc/nginx/geoip/GeoLite2-ASN.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
sudo wget -q -O /etc/nginx/geoip/GeoLite2-City.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
sudo wget -q -O /etc/nginx/geoip/GeoLite2-Country.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"

# === 設定自動更新腳本 ===
sudo tee /etc/nginx/geoip/update_geoip2.sh >/dev/null <<'EOF'

GEOIP_DIR="/etc/nginx/geoip"
TMP_DIR="/tmp/geoip2_update"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"

mkdir -p "$TMP_DIR"
wget -q -O "$TMP_DIR/GeoLite2-Country.mmdb" "$COUNTRY_URL"
[ -s "$TMP_DIR/GeoLite2-Country.mmdb" ] && mv "$TMP_DIR/GeoLite2-Country.mmdb" "$GEOIP_DIR/"
wget -q -O "$TMP_DIR/GeoLite2-City.mmdb" "$CITY_URL"
[ -s "$TMP_DIR/GeoLite2-City.mmdb" ] && mv "$TMP_DIR/GeoLite2-City.mmdb" "$GEOIP_DIR/"
wget -q -O "$TMP_DIR/GeoLite2-ASN.mmdb" "$ASN_URL"
[ -s "$TMP_DIR/GeoLite2-ASN.mmdb" ] && mv "$TMP_DIR/GeoLite2-ASN.mmdb" "$GEOIP_DIR/"
EOF
# === 鎖定 nginx 套件避免自動升級 ===
sudo apt-mark hold nginx

echo "NGINX 安裝與模組編譯完成，請確認 nginx.conf 中加入 include /etc/nginx/modules.d/*.conf; 並重新啟動 nginx"
