# Elf-Nginx 容器化部署方案

## 📖 專案概述

Elf-Nginx 是一個基於 Nginx 1.29.3 的企業級容器化部署解決方案，整合了高可用性、安全防護、地理位置識別和自動化運維等進階功能。

### 🚀 主要特色

- **高性能**: 基於源碼自定義編譯，整合多個效能優化模組
- **高可用**: Keepalived 實現主從故障轉移機制
- **安全防護**: ModSecurity WAF + GeoIP + IP過濾多重保護
- **自動化**: 定期更新地理IP資料庫和Cloudflare配置
- **模組化**: 動態模組載入，靈活配置管理

## 🏗️ 技術架構

### 核心組件

#### Web服務器

- **Nginx版本**: 1.29.3 (自定義編譯)
- **基礎映像**: Debian Bookworm Slim
- **編譯選項**: 完整功能集，包含SSL、HTTP/2、HTTP/3支援

#### 第三方模組集成

| 模組名稱 | 功能描述 | 版本 |
|---------|---------|------|
| ngx_http_geoip2_module | GeoIP2地理位置識別 | 最新版 |
| ngx_brotli | Google Brotli壓縮 | 最新版 |
| headers-more-nginx-module | HTTP頭部自定義 | 最新版 |
| ngx_cache_purge | 快取清理功能 | 最新版 |
| njs | JavaScript支援 | 最新版 |
| ModSecurity-nginx | WAF安全防護 | v1.0.4 |

#### 依賴庫版本

- **OpenSSL**: 3.5.4
- **PCRE2**: 10.47
- **zlib**: 1.3.1
- **libmaxminddb**: 1.12.2

## 📁 項目結構

```
nginx1.29.3-docker/
├── Dockerfile                     # 容器構建配置
├── docker-compose.yml             # 容器編排配置（elf-nginx + haproxy）
├── build-nginx.sh                 # Nginx 編譯腳本
├── 30-keepalived-install.sh       # 實體機 / VM 上安裝 Keepalived 的腳本
├── keepalived-install.sh          # 精簡版 Keepalived 安裝腳本
├── docker-entrypoint.sh           # Nginx 容器入口點
├── nginx/                         # Nginx 配置與資料掛載根目錄
│   ├── etc/                       # Nginx 配置
│   ├── modules/                   # 動態模組
│   ├── logs/                      # 運行日誌
│   ├── cache/                     # 緩存文件
│   ├── geoip/                     # GeoIP 資料庫
│   └── keepalived/                # Keepalived 配置（僅掛載用）
├── haproxy/
│   └── haproxy.cfg                # HAProxy 前端配置
├── README.md                      # 項目說明文檔
└── todos.md                       # 開發任務清單
```

## 🔧 配置詳解

### Docker Compose 配置

```yaml
version: "3.9"

services:
  elf-nginx:
    container_name: elf-nginx
    build:
      context: .
      dockerfile: Dockerfile        # 以當前目錄的 Dockerfile 構建
    image: elf-nginx:latest
    restart: unless-stopped
    volumes:
      - ./nginx/etc:/etc/nginx                      # 配置檔持久化
      - ./nginx/modules:/usr/lib/nginx/modules      # 動態模組
      - ./nginx/logs:/var/log/nginx                 # 日誌檔持久化
      - ./nginx/cache:/var/cache/nginx              # 緩存檔持久化
      - ./nginx/geoip:/usr/share/GeoIP              # GeoIP 資料庫
      - ./nginx/keepalived:/etc/keepalived          # Keepalived 配置（僅掛載用）

  haproxy:
    container_name: haproxy
    image: haproxy:2.9
    restart: unless-stopped
    depends_on:
      - elf-nginx
    ports:
      - "80:80"    # HTTP 流量
      - "443:443"  # HTTPS 流量
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

### Nginx 配置文件結構

```
/etc/nginx/
├── nginx.conf                    # 主配置文件
├── modules.conf                  # 動態模組載入配置
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

### SSL/TLS 安全配置

```nginx
# SSL 設置
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

## 🛡️ 安全功能

### 1. ModSecurity WAF 防護

- **OWASP Core Rule Set (CRS)** 整合
- **動態規則載入** 機制
- **JSON格式審計日誌** 記錄
- **自定義例外規則** 支援

### 2. GeoIP 地理位置過濾

- **即時地理位置識別**
- **國家/城市級別定位**
- **自動資料庫更新** (每週三、六)
- **Cloudflare IP整合** 支援

### 3. 訪問控制

- **IP白名單機制** - 允許特定IP/網段訪問
- **IP黑名單機制** - 阻擋可疑IP/網段
- **動態規則管理** - 運行時調整訪問控制

## 🚀 高可用性配置

### Keepalived 設定

#### 配置文件示例

```ini
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_nginx {
    script "/usr/local/sbin/check_nginx.sh"
    interval 2
    fall 3
    rise 2
}

vrrp_instance VI_51 {
    state MASTER                    # MASTER 或 BACKUP
    interface eth0                  # 網卡接口名稱
    virtual_router_id 51            # VRRP組ID
    priority 200                    # 優先權 (MASTER: 200, BACKUP: 100)
    advert_int 1                    # 廣播間隔(秒)
    
    # 單播配置
    unicast_src_ip 192.168.25.10    # 本機IP地址
    unicast_peer {
        192.168.25.11               # 對端IP地址
    }
    
    authentication {
        auth_type PASS
        auth_pass 23887711          # VRRP驗證密碼
    }
    
    track_script {
        chk_nginx                   # 健康檢查腳本
    }
    
    virtual_ipaddress {
        192.168.25.250/24 dev eth0  # 虛擬IP地址
    }
}
```

#### 健康檢查機制

- **進程檢查** - 監控nginx主進程狀態
- **服務響應** - HTTP健康檢查(可選)
- **自動故障轉移** - 主服務異常時自動切換到備援

## 📊 性能優化

### 壓縮配置

- **Gzip壓縮** - 標準HTTP壓縮
- **Brotli壓縮** - Google高效壓縮算法
- **靜態文件優化** - 支持預壓縮文件

### 快取機制

- **代理快取** - 後端服務響應快取
- **客戶端快取** - 瀏覽器快取控制
- **FastCGI快取** - 動態內容快取

### HTTP/2 & HTTP/3

- **HTTP/2多路複用** - 提升頁面載入速度
- **HTTP/3 QUIC** - 最新協議支援

## 🔄 自動化運維

### 定期更新任務

#### GeoIP資料庫更新

- **更新頻率**: 每週三、六 03:00
- **更新內容**: GeoLite2 Country/City/ASN資料庫
- **更新範圍**: Cloudflare IP範圍
- **自動重載**: 更新後自動重啟nginx

#### 系統排程配置

```bash
# systemd timer 格式
[Timer]
OnCalendar=Wed,Sat 03:00
Persistent=true
RandomizedDelaySec=5min
```

### 日誌管理

- **訪問日誌** - `/var/log/nginx/access.log`
- **錯誤日誌** - `/var/log/nginx/error.log`
- **WAF審計日誌** - `/var/log/modsecurity/audit.log`
- **Keepalived日誌** - `/var/log/keepalived/`

## 🏃‍♂️ 部署指南

### 環境要求

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **系統資源**: 最低2GB RAM, 4GB磁碟空間
- **網路**: 支持80/443端口映射

### 快速部署（本機開發環境）

#### 1. 構建容器映像

```bash
# 在專案根目錄（包含 nginx1.29.3-docker）執行
docker builder prune -f    # 可選：清理 builder 快取

cd nginx1.29.3-docker
docker compose -f docker-compose.build.yml build
```

#### 2. 啟動本機服務（測試用）

```bash
# 使用 build 版 compose 啟動 elf-nginx + haproxy
docker compose -f docker-compose.build.yml up -d --build
```

#### 3. 推送映像到 Docker Hub

```bash
docker login
docker push tw199501/nginx:1.29.3
docker push tw199501/haproxy:trixie
```

### 跨主機部署（VM / 實體機）

#### 1. 準備目標主機目錄

```bash
sudo mkdir -p /opt/nginx-stack/nginx
sudo mkdir -p /opt/nginx-stack/nginx-ui
```

#### 2. 在目標主機拉取映像

```bash
docker pull tw199501/nginx:1.29.3
docker pull tw199501/haproxy:trixie
```

#### 3. 使用 Compose 啟動服務

> 將發佈用的 `docker-compose.yml` 與 `nginx-ui-compose.yml` 複製到目標主機同一目錄。

```bash
docker compose -f docker-compose.yml up -d
docker compose -f nginx-ui-compose.yml up -d
```

#### 4. 使用 Nginx UI 管理設定（方案B）

```text
流量路徑: Client -> haproxy(80/443) -> elf-nginx:80
配置路徑: /opt/nginx-stack/nginx <-> elf-nginx:/etc/nginx
          /opt/nginx-stack/nginx <-> nginx-ui:/etc/nginx
          /opt/nginx-stack/nginx-ui <-> nginx-ui:/etc/nginx-ui
```

首次登入 Nginx UI：`http://<host>:8080` 或 `https://<host>:8443`。

Nginx UI 中對應 `elf-nginx` 的建議設定：

- ContainerName：`elf-nginx`
- ConfigDir：`/etc/nginx`
- PIDPath：`/run/nginx.pid`
- SbinPath：`/usr/sbin/nginx`
- TestConfigCmd：`nginx -t`
- AccessLogPath：`/var/log/nginx/access.log`
- ErrorLogPath：`/var/log/nginx/error.log`
- LogDirWhiteList：`/var/log/nginx`

上述設定完成後，Nginx UI 在後台執行語法檢查與重載時，等同於：

```bash
docker exec elf-nginx nginx -t
docker exec elf-nginx nginx -s reload
```

### 高可用部署

#### 1. 主從節點配置

```bash
# 主節點 (MASTER)
export ROLE=MASTER
export IFACE=eth0
export VRID=51
export VIP_CIDR=192.168.25.250/24
export PEER_IP=192.168.25.11
export PRIORITY=200

# 備援節點 (BACKUP)
export ROLE=BACKUP
export IFACE=eth0
export VRID=51
export VIP_CIDR=192.168.25.250/24
export PEER_IP=192.168.25.10
export PRIORITY=100
```

#### 2. 運行Keepalived安裝

```bash
# 在兩個節點上分別執行
bash 30-keepalived-install.sh
```

#### 3. 驗證高可用

```bash
# 檢查虛擬IP綁定
ip -4 addr show dev eth0 | grep 192.168.25.250

# 查看VRRP狀態
journalctl -u keepalived -e -n 50
```

## 🔧 管理指令

### IP管理工具

```bash
# 添加IP到白名單
bash /etc/nginx/scripts/manage_ip.sh allow 192.168.1.100 /etc/nginx/geoip/ip_whitelist.conf

# 從白名單移除IP
bash /etc/nginx/scripts/manage_ip.sh deny 192.168.1.100 /etc/nginx/geoip/ip_whitelist.conf
```

### 服務管理

```bash
# 重新載入nginx配置
nginx -s reload

# 測試nginx配置
nginx -t

# 重啟nginx服務
systemctl restart nginx

# 檢查nginx狀態
systemctl status nginx
```

### 監控與維護

```bash
# 查看nginx進程
ps aux | grep nginx

# 檢查端口占用
netstat -tlnp | grep :80
netstat -tlnp | grep :443

# 查看實時日誌
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

## 🚨 故障排除

### 常見問題

#### 1. 容器啟動失敗

```bash
# 檢查容器日誌
docker-compose logs elf-nginx

# 檢查端口占用
netstat -tlnp | grep :80
netstat -tlnp | grep :443
```

#### 2. Nginx配置錯誤

```bash
# 測試配置語法
docker exec elf-nginx nginx -t

# 檢查配置檔
docker exec elf-nginx cat /etc/nginx/nginx.conf
```

#### 3. Keepalived故障轉移問題

```bash
# 檢查VRRP狀態
journalctl -u keepalived --no-pager

# 驗證健康檢查腳本
bash /usr/local/sbin/check_nginx.sh
```

### 日誌分析

#### 關鍵日誌路徑

- **Nginx錯誤日誌**: `/var/log/nginx/error.log`
- **WAF審計日誌**: `/var/log/modsecurity/audit.log`
- **Keepalived日誌**: `journalctl -u keepalived`

## 📈 性能調優

### 系統參數調整

```bash
# 調整文件描述符限制
echo "nginx soft nofile 65535" >> /etc/security/limits.conf
echo "nginx hard nofile 65535" >> /etc/security/limits.conf

# 調整網路參數
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
sysctl -p
```

### Nginx工作進程調優

```nginx
worker_processes auto;
worker_connections 4096;
worker_rlimit_nofile 65535;
```

## 🔐 安全建議

### 1. 定期更新

- **安全補丁**: 定期更新系統和軟件包
- **SSL憑證**: 使用Let's Encrypt自動更新憑證
- **規則更新**: 定期更新WAF規則集

### 2. 訪問控制

- **白名單管理**: 僅允許信任的IP地址
- **速率限制**: 防止DDoS攻擊
- **SSL配置**: 使用強加密算法

### 3. 監控告警

- **日誌監控**: 設置異常訪問告警
- **性能監控**: 監控響應時間和吞吐量
- **安全監控**: 檢測可疑攻擊模式

## 📦 Docker / Compose 常用指令

> 以下指令假設目前在 `nginx1.29.3-docker` 目錄中執行。

```bash
# 使用 build 版 compose 構建映像（僅 build，不啟動容器）
docker compose -f docker-compose.build.yml build

# 使用 build 版 compose 構建並啟動（開發自用）
docker compose -f docker-compose.build.yml up -d --build

# 使用發佈版 docker-compose.yml 啟動（給別人直接用映像）
docker compose up -d

# 停止並移除容器（不刪映像）
docker compose down

# 查看目前容器狀態
docker compose ps

# 查看 nginx / haproxy 日誌
docker compose logs -f elf-nginx
docker compose logs -f haproxy

# 進入 nginx 容器（除錯用）
docker exec -it elf-nginx /bin/bash

# 手動觸發 GeoIP 更新腳本
docker exec elf-nginx /etc/nginx/scripts/update_geoip.sh
```

## 📞 技術支援

### 相關文檔

- [Nginx官方文檔](https://nginx.org/en/docs/)
- [ModSecurity文檔](https://github.com/SpiderLabs/ModSecurity/wiki)
- [Keepalived文檔](https://keepalived.readthedocs.io/)

### 項目資訊

- **版本**: 1.29.3
- **更新日期**: 2025-11-28
- **維護者**: Elf團隊

---

*本專案致力於提供企業級nginx容器化解決方案，如有問題或建議，歡迎提交Issue或Pull Request。*
