# Elf-Nginx 部署指南

## 🏃‍♂️ 部署流程

### 環境要求

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **系統資源**: 最低2GB RAM, 4GB磁碟空間
- **網路**: 支持80/443端口映射

## 🚀 本機開發環境部署

### 1. 構建容器映像

```bash
# 在專案根目錄（包含 nginx1.29.3-docker）執行
docker builder prune -f    # 可選：清理 builder 快取

cd nginx1.29.3-docker
docker compose -f docker-compose.build.yml build
```

### 2. 啟動本機服務（測試用）

```bash
# 使用 build 版 compose 啟動 elf-nginx + haproxy
docker compose -f docker-compose.build.yml up -d --build
```

### 3. 推送映像到 Docker Hub

```bash
docker login
docker push tw199501/nginx:1.29.3
docker push tw199501/haproxy:trixie

# 或者使用提供的腳本：
# Bash (Git Bash / WSL):
bash nginx1.29.3-docker/push-images.sh
# Windows PowerShell (從專案根目錄):
.\nginx1.29.3-docker\push-images.ps1
```

## 🌐 跨主機部署（VM / 實體機）

### 1. 準備目標主機目錄

```bash
sudo mkdir -p /opt/nginx-stack/nginx
sudo mkdir -p /opt/nginx-stack/nginx-ui
```

### 2. 在目標主機拉取映像

```bash
docker pull tw199501/nginx:1.29.3
docker pull tw199501/haproxy:trixie
```

### 3. 使用 Compose 啟動服務

> 將發佈用的 `docker-compose.yml` 與 `nginx-ui-compose.yml` 複製到目標主機同一目錄。

```bash
docker compose -f docker-compose.yml up -d
docker compose -f nginx-ui-compose.yml up -d
```

### 4. 使用 Nginx UI 管理設定（方案B）

```text
流量路徑: Client -> haproxy(80/443) -> elf-nginx:80
配置路徑: /opt/nginx-stack/nginx <-> elf-nginx:/etc/nginx
          /opt/nginx-stack/nginx <-> nginx-ui:/etc/nginx
          /opt/nginx-stack/nginx-ui <-> nginx-ui:/etc/nginx-ui
```

#### Nginx UI 設定

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

## 🔄 高可用部署

### 1. 主從節點配置

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

### 2. 運行Keepalived安裝

```bash
# 在兩個節點上分別執行
bash keepalived-install.sh
```

### 3. 驗證高可用

```bash
# 檢查虛擬IP綁定
ip -4 addr show dev eth0 | grep 192.168.25.250

# 查看VRRP狀態
journalctl -u keepalived -e -n 50
```

## 🔧 服務管理指令

### Docker Compose 常用指令

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

### Nginx 服務管理

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

## 📊 性能調優

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

## 📋 部署檢查清單

### 部署前檢查

- [ ] 系統資源充足（2GB+ RAM, 4GB+ 磁碟）
- [ ] Docker 和 Docker Compose 已安裝
- [ ] 端口 80/443 可用
- [ ] 防火牆設定允許必要端口

### 部署後驗證

- [ ] 容器正常啟動：`docker compose ps`
- [ ] Nginx 配置語法正確：`docker exec elf-nginx nginx -t`
- [ ] 網站可正常訪問
- [ ] 日誌無錯誤：`docker compose logs elf-nginx`
- [ ] GeoIP 更新腳本可正常執行

### 高可用驗證

- [ ] 主從節點 Keepalived 服務正常
- [ ] 虛擬 IP 正確綁定
- [ ] 健康檢查腳本正常運作
- [ ] 故障轉移機制測試通過
