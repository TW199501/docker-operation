# Elf-Nginx 開發與維護指南

## 🛠️ 開發環境設置

### 本地開發環境

```bash
# 克隆專案
git clone <repository-url>
cd nginx1.29.3-docker

# 安裝依賴
docker-compose -f docker-compose.build.yml build

# 啟動開發環境
docker-compose -f docker-compose.build.yml up -d --build
```

### 開發工作流程

1. **修改配置**

   ```bash
   # 編輯配置文件
   vi /opt/nginx-stack/nginx/nginx.conf
   
   # 測試配置
   docker exec elf-nginx nginx -t
   
   # 重新載入
   docker exec elf-nginx nginx -s reload
   ```

2. **添加新模組**

   ```bash
   # 編輯 build-nginx.sh
   vi build-nginx.sh
   
   # 重新建構映像
   docker-compose -f docker-compose.build.yml build --no-cache
   ```

## 📝 程式碼結構

### 核心檔案

```text
nginx1.29.3-docker/
├── Dockerfile                     # 容器構建配置
├── build-nginx.sh                 # Nginx 編譯腳本
├── keepalived-install.sh          # Keepalived 安裝腳本
├── docker-entrypoint.sh           # 容器入口點
└── docs/                          # 文檔目錄
```

### 編譯腳本架構 (build-nginx.sh)

```bash
#!/usr/bin/env bash
set -euo pipefail

# 模組化設計
module_A_interactive_and_params() { ... }
module_C_source_and_deps() { ... }
module_D_build_nginx_and_base_init() { ... }
module_E_geoip_cloudflare_init() { ... }
module_F_update_geoip_install_and_timer() { ... }
module_H_build_modsecurity_waf() { ... }
module_G_ensure_nginx_run_user() { ... }

# 主要執行流程
run_stage "module_A_interactive_and_params" module_A_interactive_and_params
run_stage "module_C_source_and_deps" module_C_source_and_deps
run_stage "module_D_build_nginx_and_base_init" module_D_build_nginx_and_base_init
run_stage "module_E_geoip_cloudflare_init" module_E_geoip_cloudflare_init
run_stage "module_F_update_geoip_install_and_timer" module_F_update_geoip_install_and_timer
run_stage "module_H_build_modsecurity_waf" module_H_build_modsecurity_waf
```

## 🔧 自定義配置

### 添加新的 Nginx 模組

1. **編輯 build-nginx.sh**

   ```bash
   # 在 module_C_source_and_deps() 中添加
   git clone --depth=1 <new-module-repo> "$BUILD_DIR/new_module"
   
   # 在 module_D_build_nginx_and_base_init() 中添加
   --add-dynamic-module="$BUILD_DIR/new_module" \
   ```

2. **更新模組列表**

   ```bash
   # 在 default.modules.main.conf 中添加
   load_module /usr/lib/nginx/modules/new_module.so;
   ```

3. **重新建構**

   ```bash
   docker-compose build --no-cache
   ```

### 自定義 Keepalived 配置

```bash
# 修改 keepalived-install.sh 中的參數
VRID="${VRID:-51}"              # VRRP 組 ID
VIP_CIDR="${VIP_CIDR:-192.168.25.250/24}"  # 虛擬 IP
PRIORITY="${PRIORITY:-200}"     # 優先權

# 運行安裝
bash keepalived-install.sh
```

## 📊 性能調優

### 系統參數調優

```bash
# 編輯 /etc/sysctl.conf
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
sysctl -p

# 編輯 /etc/security/limits.conf
echo "nginx soft nofile 65535" >> /etc/security/limits.conf
echo "nginx hard nofile 65535" >> /etc/security/limits.conf
```

### Nginx 工作進程調優

```nginx
# nginx.conf 優化
worker_processes auto;
worker_connections 4096;
worker_rlimit_nofile 65535;

# 事件模組
events {
    use epoll;
    worker_connections 4096;
    multi_accept on;
}

# HTTP 模組
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    
    # 快取設定
    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
}
```

## 🔒 安全最佳實踐

### SSL/TLS 強化

```nginx
# 強制 HTTPS
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com;
    
    # SSL 配置
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # 強化設定
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # 安全標頭
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
```

### 防火牆設定

```bash
# UFW 設定
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable

# Docker 網路安全
docker network create --internal elf-internal
```

## 📋 測試與驗證

### 自動化測試

```bash
#!/bin/bash
# test-nginx.sh

echo "正在測試 Nginx 配置..."
docker exec elf-nginx nginx -t

echo "正在檢查服務狀態..."
docker-compose ps

echo "正在測試網站連通性..."
curl -I http://localhost

echo "正在檢查 SSL 憑證..."
openssl s_client -connect localhost:443 -servername localhost </dev/null

echo "測試完成！"
```

### 性能測試

```bash
# 使用 ab 進行壓力測試
ab -n 1000 -c 10 http://localhost/

# 使用 wrk 進行性能測試
wrk -t12 -c400 -d30s http://localhost/

# 使用 siege 進行負載測試
siege -c 10 -d 1 -t 30S http://localhost/
```

## 📈 監控與告警

### 監控腳本

```bash
#!/bin/bash
# monitor.sh

# 檢查服務狀態
if ! docker-compose ps | grep -q "Up"; then
    echo "ERROR: Container is down" | mail -s "Nginx Alert" admin@example.com
fi

# 檢查響應時間
RESPONSE_TIME=$(curl -o /dev/null -s -w "%{time_total}" http://localhost)
if (( $(echo "$RESPONSE_TIME > 2.0" | bc -l) )); then
    echo "WARNING: Slow response time: ${RESPONSE_TIME}s" | mail -s "Performance Alert" admin@example.com
fi

# 檢查錯誤日誌
ERROR_COUNT=$(docker exec elf-nginx tail -n 100 /var/log/nginx/error.log | grep -c "error")
if [ "$ERROR_COUNT" -gt 10 ]; then
    echo "WARNING: High error count: $ERROR_COUNT" | mail -s "Error Alert" admin@example.com
fi
```

### 日誌輪轉

```nginx
# logrotate 配置 (/etc/logrotate.d/nginx)
/var/log/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 nginx nginx
    postrotate
        docker exec elf-nginx nginx -s reopen
    endscript
}
```

## 🔄 CI/CD 流程

### GitHub Actions 範例

```yaml
# .github/workflows/ci.yml
name: CI/CD

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Build Docker images
      run: docker-compose -f docker-compose.build.yml build
      
    - name: Run tests
      run: |
        docker-compose -f docker-compose.build.yml up -d
        ./scripts/test-nginx.sh
        docker-compose -f docker-compose.build.yml down
        
    - name: Push images
      if: github.ref == 'refs/heads/main'
      run: |
        echo ${{ secrets.DOCKER_PASSWORD }} | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
        docker push tw199501/nginx:1.29.3
```

### Docker 映像更新

```bash
# 建構並標記新版本
docker build -t tw199501/nginx:1.29.3 -t tw199501/nginx:latest .

# 推送映像
docker push tw199501/nginx:1.29.3
docker push tw199501/nginx:latest

# 部署到生產環境
docker pull tw199501/nginx:latest
docker-compose up -d
```

## 📚 開發資源

### 有用工具

- **配置驗證**: `nginx -t`
- **性能分析**: `goaccess`, `nginx -V`
- **SSL 檢查**: `openssl s_client`, `sslscan`
- **網路分析**: `tcpdump`, `wireshark`
- **負載測試**: `ab`, `wrk`, `siege`

### 參考文檔

- [Nginx 官方文檔](https://nginx.org/en/docs/)
- [Docker 最佳實踐](https://docs.docker.com/develop/dev-best-practices/)
- [Docker Compose 參考](https://docs.docker.com/compose/compose-file/)
- [Keepalived 文檔](https://keepalived.readthedocs.io/)
- [ModSecurity 文檔](https://github.com/SpiderLabs/ModSecurity/wiki)

## 🐛 調試技巧

### 常見調試命令

```bash
# 進入容器除錯
docker exec -it elf-nginx /bin/bash

# 查看 Nginx 進程
docker exec elf-nginx ps aux | grep nginx

# 檢查網路連接
docker exec elf-nginx netstat -tlnp

# 查看即時日誌
docker-compose logs -f elf-nginx

# 檢查配置載入
docker exec elf-nginx nginx -T | head -50
```

### 效能分析

```bash
# 檢查記憶體使用
docker exec elf-nginx free -h

# 檢查磁碟 I/O
docker exec elf-nginx iostat -x 1

# 檢查網路統計
docker exec elf-nginx ss -s

# 查看檔案描述符使用
docker exec elf-nginx lsof | wc -l
```

## 📋 開發檢查清單

### 代碼提交前檢查

- [ ] 配置語法正確：`nginx -t`
- [ ] 所有測試通過
- [ ] 文檔已更新
- [ ] 沒有硬編碼的敏感信息
- [ ] 遵循專案編碼規範

### 發佈前檢查

- [ ] 版本號已更新
- [ ] Docker 映像正常建構
- [ ] 部署腳本測試通過
- [ ] 性能測試結果可接受
- [ ] 安全掃描無高危漏洞

### 監控指標

- [ ] 響應時間 < 2秒
- [ ] 錯誤率 < 0.1%
- [ ] CPU 使用率 < 80%
- [ ] 記憶體使用率 < 80%
- [ ] 磁碟使用率 < 85%
