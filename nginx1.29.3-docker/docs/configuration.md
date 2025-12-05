# Elf-Nginx 配置詳解

## 📁 項目結構

```
nginx1.29.3-docker/
├── Dockerfile                     # 容器構建配置
├── docker-compose.yml             # 容器編排配置（elf-nginx + haproxy）
├── build-nginx.sh                 # Nginx 編譯腳本
├── keepalived-install.sh          # 精簡版 Keepalived 安裝腳本
├── docker-entrypoint.sh           # Nginx 容器入口點
├── docs/                          # 文檔目錄
├── haproxy/                       # HAProxy 配置
│   └── haproxy.cfg                # HAProxy 前端配置
└── scripts/                       # 管理腳本
    └── manage_ip.sh               # IP管理工具
```

## 🔧 Docker Compose 配置

### 1. docker-compose.yml（發佈版本）

```yaml
name: elfnginxhaproxy
services:
  elf-nginx:
    container_name: elf-nginx
    image: tw199501/nginx:1.29.3
    restart: unless-stopped
    environment:
      - TZ=Asia/Taipei
    volumes:
      - /opt/nginx-stack/nginx:/etc/nginx
      - /opt/nginx-stack/nginx-logs:/var/log/nginx
    networks:
      - elf-internal

  haproxy:
    container_name: haproxy
    image: tw199501/haproxy:trixie
    restart: unless-stopped
    depends_on:
      - elf-nginx
    ports:
      - "80:80"
      - "443:443"
      - "8404:8404"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    networks:
      - elf-internal

networks:
  elf-internal:
    internal: true
```

### 2. docker-compose.build.yml（建置版本）

```yaml
name: hanginx
services:
  elf-nginx:
    build:
      context: ..
      dockerfile: nginx1.29.3-docker/Dockerfile
    image: tw199501/nginx:1.29.3
    restart: unless-stopped
    environment:
      - TZ=Asia/Taipei
    volumes:
      - /opt/nginx-stack/nginx:/etc/nginx
  haproxy:
    container_name: haproxy
    build:
      context: .
      dockerfile: haproxy/Dockerfile
    image: tw199501/haproxy:trixie
    restart: unless-stopped
    depends_on:
      - elf-nginx
    ports:
      - "80:80"
      - "443:443"
      - "8404:8404"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

### 3. nginx-ui-compose.yml（管理介面）

```yaml
services:
  nginx-ui:
    image: uozi/nginx-ui:dev
    container_name: nginx-ui
    restart: always
    networks:
      - nginx-ui-network
    environment:
      - NGINX_UI_NODE_DEMO=true
      - NGINX_UI_SERVER_HOST=0.0.0.0
      - NGINX_UI_SERVER_PORT=9860
      - NGINX_UI_NGINX_CONFIG_DIR=/etc/nginx
      - NGINX_UI_AUTH_MAX_ATTEMPTS=5
    ports:
      - 8080:80
      - 8443:443
      - 9168:9860
    volumes:
      - /opt/nginx-stack/nginx:/etc/nginx
      - /opt/nginx-stack/nginx-ui:/etc/nginx-ui
      - /opt/nginx-stack/nginx-logs:/var/log/nginx
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock
networks:
  nginx-ui-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_ip_masquerade: "true"
```

## 🏗️ Nginx 配置文件結構

```
/etc/nginx/
├── nginx.conf                    # 主配置文件
├── default.modules.main.conf     # 動態模組載入配置
├── conf.d/                       # 通用配置片段
│   ├── ssl.conf                  # SSL/TLS配置
│   ├── cloudflare.conf           # Cloudflare整合配置
│   └── waf.conf                 # WAF安全防護配置
├── sites-available/              # 可用站點配置
│   └── default.conf             # 預設站點配置
├── sites-enabled/                # 啟用站點配置
│   └── default.conf -> ../sites-available/default.conf
├── geoip/                        # 地理IP配置
│   ├── cloudflare_v4_realip.conf
│   ├── cloudflare_v6_realip.conf
│   ├── ip_whitelist.conf        # IP白名單配置
│   └── ip_blacklist.conf        # IP黑名單配置
└── scripts/                      # 管理腳本
    ├── update_geoip.sh          # 更新GeoIP資料庫腳本
    └── manage_ip.sh             # IP地址管理工具
```

## 📄 主要配置文件詳解

### 1. nginx.conf（主配置）

```nginx
include /etc/nginx/default.modules.main.conf;
worker_rlimit_nofile 65535;
user nginx;

worker_processes auto;

events {
    worker_connections 4096;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    keepalive_timeout  65;
    
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;

    server {
        listen       80;
        server_name  localhost;

        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}

stream {
    include /etc/nginx/streams-enabled/*;
}
```

### 2. default.modules.main.conf（動態模組）

```nginx
# 動態模組載入配置
load_module /usr/lib/nginx/modules/ngx_http_geoip2_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;
load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_image_filter_module.so;
load_module /usr/lib/nginx/modules/ngx_http_js_module.so;
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
load_module /usr/lib/nginx/modules/ngx_stream_geoip2_module.so;
load_module /usr/lib/nginx/modules/ngx_stream_js_module.so;
```

### 3. SSL/TLS 配置（conf.d/ssl.conf）

```nginx
# SSL 設置
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

### 4. Cloudflare 配置（conf.d/cloudflare.conf）

```nginx
# Cloudflare / cloudflared real_ip & GeoIP2
include /etc/nginx/geoip/cloudflare_v4_realip.conf;
include /etc/nginx/geoip/cloudflare_v6_realip.conf;

# GeoIP2
geoip2 /usr/share/GeoIP/GeoLite2-City.mmdb {
    $geoip2_data_city_name city names en;
    $geoip2_data_city_longitude location longitude;
    $geoip2_data_city_latitude location latitude;
}
```

## 🛡️ 安全功能配置

### 1. IP 白名單配置（geoip/ip_whitelist.conf）

```nginx
# IP 白名單配置（由 /etc/nginx/scripts/manage_ip.sh 維護）
# 預設全部拒絕，按需加入 allow 規則
deny all;

# 範例：允許內網與單一 IP
#allow 192.168.1.0/24;
#allow 10.0.0.1;
```

### 2. IP 黑名單配置（geoip/ip_blacklist.conf）

```nginx
# IP 黑名單配置
# 預設全部允許，按需加入 deny 規則
allow all;

# 範例：封鎖單一 IP 或網段
#deny 203.0.113.5;
#deny 198.51.100.0/24;
```

### 3. ModSecurity WAF 配置（conf.d/waf.conf）

```nginx
# 載入 ModSecurity 動態模組
# load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;

# 啟用 ModSecurity (http 區塊）
# modsecurity on;
# modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
```

## 🔄 自動化運維配置

### GeoIP 更新腳本（/etc/nginx/scripts/update_geoip.sh）

```bash
#!/usr/bin/env bash
set -euo pipefail
GEOIP_MMDB_DIR="/usr/share/GeoIP"
GEOIP_CONF_DIR="/etc/nginx/geoip"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"

# 更新腳本內容...
```

### IP 管理工具（/etc/nginx/scripts/manage_ip.sh）

```bash
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
```

## 📊 性能優化配置

### HTTP/2 & HTTP/3

```nginx
# 在 server 配置中啟用 HTTP/2
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;
    
    # HTTP/3 支持
    listen 443 quic reuseport;
    listen [::]:443 quic reuseport;
    
    # QUIC 配置
    add_header Alt-Svc 'h3=":443"; ma=86400, h3-29=":443"; ma=86400';
}
```

### 壓縮配置

```nginx
# Gzip 壓縮
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_proxied any;
gzip_comp_level 6;
gzip_types
    text/plain
    text/css
    text/xml
    text/javascript
    application/json
    application/javascript
    application/xml+rss
    application/atom+xml
    image/svg+xml;

# Brotli 壓縮（如果模組可用）
brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
