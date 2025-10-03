#!/usr/bin/env bash
# ================================================
# 編譯Nginx與下載 GeoIP2 + 整合 Cloudflare Real IP
# 版本：v1.4（整合 real_ip 與每週更新）
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
if pgrep -x nginx >/dev/null; then
  echo "停止 nginx 進程..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop nginx || true
  else
    sudo pkill -TERM -x nginx || true
  fi
  sleep 5
  if pgrep -x nginx >/dev/null; then
    echo "仍有 nginx 進程在運行，強制終止..."
    sudo pkill -KILL -x nginx || true
    sleep 2
  fi
else
  echo "沒有發現運行中的 nginx 進程"
fi
sudo rm -f /run/nginx.pid || true
echo "清理完成"

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

# === 檢查並自動安裝編譯相關依賴（支援 apt/dnf/yum/apk）===
echo "檢查編譯相關依賴..."
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    echo "需要 root 權限或 sudo 才能自動安裝套件"; exit 1
  fi
fi

need_install=0
for bin in gcc make git; do
  command -v "$bin" >/dev/null 2>&1 || need_install=1
done

if [ "$need_install" -eq 1 ]; then
  echo "偵測到缺少編譯工具，嘗試自動安裝..."
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -yq
    $SUDO apt-get install -yq build-essential zlib1g-dev libssl-dev libmaxminddb-dev unzip git libpcre2-dev libxml2-dev libxslt1-dev curl wget cmake
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf -y groupinstall "Development Tools"
    $SUDO dnf -y install pcre2-devel zlib-devel openssl-devel libmaxminddb-devel unzip git libxml2-devel libxslt-devel curl wget cmake
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum -y groupinstall "Development Tools"
    $SUDO yum -y install pcre2-devel zlib-devel openssl-devel libmaxminddb-devel unzip git libxml2-devel libxslt-devel curl wget cmake
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev unzip git curl wget cmake libxml2-dev libxslt-dev
  else
    echo "無法判斷套件管理器，請手動安裝依賴。"
    exit 1
  fi
fi

for bin in gcc make git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "安裝失敗：缺少 $bin"; exit 1; }
done

if command -v pcre2-config >/dev/null 2>&1; then
  echo "已偵測到 PCRE2（推薦）"
elif command -v pcre-config >/dev/null 2>&1; then
  echo "已偵測到舊版 PCRE（可用，但建議 PCRE2）"
else
  echo "缺少 PCRE/PCRE2 開發環境"; exit 1
fi
echo "依賴檢查完成"

cd "$BUILD_DIR"
# PCRE2
curl -LO https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz
tar -xzf pcre2-10.44.tar.gz
# OpenSSL
OPENSSL_VER=3.5.4 #可修改
curl -fL --retry 3 -o "openssl-$OPENSSL_VER.tar.gz" "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"
tar -xzf "openssl-$OPENSSL_VER.tar.gz"
OPENSSL_DIR="$BUILD_DIR/openssl-$OPENSSL_VER"
test -f "$OPENSSL_DIR/Configure" || { echo "OpenSSL 原始碼目錄不正確"; exit 1; }

# === 檢查/建置 Brotli 庫 ===
BROTLI_OUT="$BUILD_DIR/ngx_brotli/deps/brotli/out"
if [ ! -f "$BROTLI_OUT/libbrotlienc.a" ] && [ ! -f /usr/lib/x86_64-linux-gnu/libbrotlienc.so ] && [ ! -f /usr/lib64/libbrotlienc.so ]; then
  echo "未偵測到 Brotli 開發庫，嘗試建置子模組..."
  git -C "$BUILD_DIR/ngx_brotli" submodule update --init --recursive || true
  if command -v cmake >/dev/null 2>&1; then
    mkdir -p "$BROTLI_OUT"
    cmake -S "$BUILD_DIR/ngx_brotli/deps/brotli/c" -B "$BROTLI_OUT" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    cmake --build "$BROTLI_OUT" -j"$(nproc)"
  else
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -yq && sudo apt-get install -yq libbrotli-dev
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y brotli-devel
    elif command -v apk >/dev/null 2>&1; then
      sudo apk add --no-cache brotli-dev
    fi
  fi
fi

# === configure 編譯 ===
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
  --with-http_xslt_module \
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
  --add-dynamic-module="$BUILD_DIR/headers-more-nginx-module" \
  --add-dynamic-module="$BUILD_DIR/ngx_cache_purge" \
  --add-dynamic-module="$BUILD_DIR/njs/nginx"

echo "開始編譯 Nginx (使用2個核心以避免資源不足)..."
make -j2
sudo make install
make modules -j2
sudo mkdir -p /usr/lib/nginx/modules
sudo cp objs/*.so /usr/lib/nginx/modules/

# === 建立模組載入設定檔 ===
sudo mkdir -p /etc/nginx/modules.d
sudo tee /etc/nginx/modules.d/00-load-geoip2.conf >/dev/null << 'EOF'
load_module /usr/lib/nginx/modules/ngx_http_geoip2_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;
load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_js_module.so;
EOF

# === 安裝 GeoIP2 資料庫 ===
sudo mkdir -p /etc/nginx/geoip
sudo wget -q -O /etc/nginx/geoip/GeoLite2-ASN.mmdb     "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
sudo wget -q -O /etc/nginx/geoip/GeoLite2-City.mmdb    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
sudo wget -q -O /etc/nginx/geoip/GeoLite2-Country.mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"

# === 初始化 Cloudflare real_ip 與 NGINX real_ip 設定 ===
echo "初始化 Cloudflare real_ip 清單與 NGINX real_ip 設定..."
sudo mkdir -p /etc/nginx/conf.d

# 1) 產生 CF v4/v6 include（安全：先寫 tmp 再覆蓋）
TMP_CF="$(mktemp -d)"; trap 'rm -rf "$TMP_CF"' EXIT
curl -fsSL --retry 3 https://www.cloudflare.com/ips-v4 | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v4_realip.conf"
curl -fsSL --retry 3 https://www.cloudflare.com/ips-v6 | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP_CF/cloudflare_v6_realip.conf"
sudo install -m 0644 "$TMP_CF/cloudflare_v4_realip.conf" /etc/nginx/geoip/cloudflare_v4_realip.conf
sudo install -m 0644 "$TMP_CF/cloudflare_v6_realip.conf" /etc/nginx/geoip/cloudflare_v6_realip.conf

# 2) 建 cloudflared_realip.conf（信任本機與本機內網 IP）
MY_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')"
sudo bash -c 'cat > /etc/nginx/geoip/cloudflared_realip.conf' <<EOF
set_real_ip_from 127.0.0.1;
${MY_IP:+set_real_ip_from $MY_IP;}
# 如 cloudflared 不在本機，請手動加：set_real_ip_from <cloudflared 所在IP>;
EOF

# 3) http{} 內統一載入的 real_ip 片段
sudo tee /etc/nginx/conf.d/00-realip.conf >/dev/null << 'NG'
# === 信任來源（本機 / 隧道路徑 / Cloudflare 節點）===
include /etc/nginx/geoip/cloudflared_realip.conf;
include /etc/nginx/geoip/cloudflare_v4_realip.conf;
include /etc/nginx/geoip/cloudflare_v6_realip.conf;

# === 用 X-Forwarded-For 還原真實訪客 IP（隧道路徑最穩）===
real_ip_header X-Forwarded-For;
real_ip_recursive on;

# （可選）GeoIP2 城市/國家變數
geoip2 /etc/nginx/geoip/GeoLite2-City.mmdb {
    auto_reload 6h;
    $geoip2_data_country_name country names en;
    $geoip2_data_city_name    city names en;
}
NG

# 4) 確保 nginx.conf 有 include conf.d/*.conf
if ! grep -qE 'include\s+/etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf; then
  echo "在 nginx.conf 的 http{} 內加入 include /etc/nginx/conf.d/*.conf;"
  sudo sed -i '/http\s*{/a \    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
fi

# === 寫入「合併版」自動更新腳本（GeoIP2 + Cloudflare IP）===
sudo tee /usr/local/sbin/update_geoip2.sh >/dev/null << 'UPD'
#!/usr/bin/env bash
set -euo pipefail
GEOIP_DIR="/etc/nginx/geoip"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
mkdir -p "$GEOIP_DIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 下載 + 原子覆蓋（成功才替換）
dl() { curl -fL --retry 3 -o "$TMP/$2" "$1" && install -m 0644 "$TMP/$2" "$GEOIP_DIR/$2"; }
# 1) 更新 GeoLite2
dl "$COUNTRY_URL" "GeoLite2-Country.mmdb" || true
dl "$CITY_URL"    "GeoLite2-City.mmdb"    || true
dl "$ASN_URL"     "GeoLite2-ASN.mmdb"     || true
# 2) 產生 CF v4/v6 set_real_ip_from 清單
curl -fsS "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v4_realip.conf"
curl -fsS "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v6_realip.conf"
install -m 0644 "$TMP/cloudflare_v4_realip.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
install -m 0644 "$TMP/cloudflare_v6_realip.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"
# 3) 驗證並重載 NGINX
if nginx -t; then nginx -s reload; echo "[OK] GeoIP2 + CF real_ip 已更新並重載"; else echo "[WARN] nginx -t 失敗，未重載"; exit 1; fi
UPD
sudo chmod +x /usr/local/sbin/update_geoip2.sh

# === 建立排程：每週三、六 03:00 執行 ===
sudo sed -i '\#update_geoip2.sh#d' /etc/crontab
echo '0 3 * * 3,6 root /usr/local/sbin/update_geoip2.sh >/var/log/update_geoip2.log 2>&1' | sudo tee -a /etc/crontab >/dev/null
sudo systemctl reload cron 2>/dev/null || sudo systemctl reload crond 2>/dev/null || sudo service cron reload 2>/dev/null || true

# === 首次更新一次，並重載 NGINX ===
/usr/local/sbin/update_geoip2.sh || true

# === 鎖定 nginx 套件避免自動升級（apt 系列才有） ===
if command -v apt-mark >/dev/null 2>&1; then
  sudo apt-mark hold nginx || true
fi

# === 最終驗證 ===
sudo nginx -t && sudo nginx -s reload
echo "NGINX 安裝完成，模組與 real_ip 已整合。"
echo "請確認：nginx.conf 已包含 include /etc/nginx/modules.d/*.conf;（本腳本已處理 conf.d 載入）"
