# Elf-Nginx 故障排除指南

## 🚨 常見問題與解決方案

### 1. 容器啟動失敗

#### 症狀

- 容器無法啟動
- 容器啟動後立即退出
- 端口占用錯誤

#### 診斷步驟

```bash
# 檢查容器日誌
docker-compose logs elf-nginx
docker-compose logs haproxy

# 檢查端口占用
netstat -tlnp | grep :80
netstat -tlnp | grep :443

# 檢查 Docker 服務狀態
systemctl status docker
```

#### 解決方案

1. **端口占用**

   ```bash
   # 查找並終止佔用端口的進程
   sudo lsof -i :80
   sudo kill -9 <PID>
   ```

2. **權限問題**

   ```bash
   # 確保 Docker 有權限訪問掛載目錄
   sudo chown -R $USER:$USER /opt/nginx-stack/nginx
   sudo chmod -R 755 /opt/nginx-stack/nginx
   ```

3. **磁碟空間不足**

   ```bash
   # 檢查磁碟使用情況
   df -h
   docker system prune -f
   ```

### 2. Nginx 配置錯誤

#### 症狀

- Nginx 無法啟動
- 配置語法錯誤
- 404/500 錯誤頁面

#### 診斷步驟

```bash
# 測試配置語法
docker exec elf-nginx nginx -t

# 檢查配置檔
docker exec elf-nginx cat /etc/nginx/nginx.conf

# 查看錯誤日誌
docker exec elf-nginx tail -f /var/log/nginx/error.log
```

#### 解決方案

1. **語法錯誤**

   ```bash
   # 檢查配置語法並查看詳細錯誤
   docker exec elf-nginx nginx -T | grep error
   ```

2. **檔案路徑錯誤**

   ```bash
   # 確認配置檔案存在
   docker exec elf-nginx ls -la /etc/nginx/conf.d/
   ```

3. **權限問題**

   ```bash
   # 修正檔案權限
   docker exec elf-nginx chown -R nginx:nginx /etc/nginx
   docker exec elf-nginx chmod -R 644 /etc/nginx/conf.d/
   ```

### 3. Keepalived 故障轉移問題

#### 症狀

- 虛擬 IP 未正確綁定
- VRRP 通信失敗
- 主從切換異常

#### 診斷步驟

```bash
# 檢查 VRRP 狀態
journalctl -u keepalived --no-pager

# 驗證健康檢查腳本
bash /usr/local/sbin/check_nginx.sh

# 檢查虛擬 IP 綁定
ip -4 addr show dev eth0 | grep 192.168.25.250
```

#### 解決方案

1. **VRRP 通信問題**

   ```bash
   # 檢查防火牆設定
   sudo ufw status
   # 確保 VRRP 協議（112）允許通過
   ```

2. **配置錯誤**

   ```bash
   # 驗證 keepalived 配置
   keepalived -t -f /etc/keepalived/keepalived.conf
   ```

3. **網路介面問題**

   ```bash
   # 確認網路介面名稱正確
   ip link show
   # 更新 keepalived 配置中的 interface 參數
   ```

### 4. GeoIP 更新失敗

#### 症狀

- GeoIP 資料庫過期
- 更新腳本執行失敗
- 地理位置識別異常

#### 診斷步驟

```bash
# 手動執行更新腳本
docker exec elf-nginx /etc/nginx/scripts/update_geoip.sh

# 檢查 GeoIP 檔案
docker exec elf-nginx ls -la /usr/share/GeoIP/

# 查看更新日誌
tail -f /var/log/update_geoip.log
```

#### 解決方案

1. **網路連接問題**

   ```bash
   # 測試網路連接
   docker exec elf-nginx curl -I https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb
   ```

2. **權限問題**

   ```bash
   # 確保更新腳本有執行權限
   docker exec elf-nginx chmod +x /etc/nginx/scripts/update_geoip.sh
   ```

3. **磁碟空間**

   ```bash
   # 檢查磁碟空間
   docker exec elf-nginx df -h /usr/share/GeoIP
   ```

### 5. ModSecurity WAF 問題

#### 症狀

- WAF 規則未生效
- 誤報/漏報
- 效能下降

#### 診斷步驟

```bash
# 檢查 ModSecurity 狀態
docker exec elf-nginx nginx -V 2>&1 | grep modsecurity

# 查看審計日誌
docker exec elf-nginx tail -f /var/log/modsecurity/audit.log

# 測試 WAF 規則
curl -I "http://localhost/?test=<script>alert(1)</script>"
```

#### 解決方案

1. **規則未載入**

   ```bash
   # 檢查 WAF 配置
   docker exec elf-nginx cat /etc/nginx/modsecurity/main.conf
   ```

2. **規則調整**

   ```bash
   # 編輯例外規則
   docker exec elf-nginx vi /etc/nginx/modsecurity/local-exclusions.conf
   ```

3. **效能優化**

   ```bash
   # 調整 ModSecurity 配置
   docker exec elf-nginx vi /etc/nginx/modsecurity/modsecurity.conf
   ```

## 📊 監控與日誌分析

### 關鍵日誌路徑

- **Nginx錯誤日誌**: `/var/log/nginx/error.log`
- **Nginx訪問日誌**: `/var/log/nginx/access.log`
- **WAF審計日誌**: `/var/log/modsecurity/audit.log`
- **Keepalived日誌**: `journalctl -u keepalived`
- **容器日誌**: `docker-compose logs`

### 監控指令

```bash
# 查看即時日誌
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 分析訪問統計
docker exec elf-nginx goaccess /var/log/nginx/access.log

# 檢查系統資源使用
docker stats elf-nginx haproxy

# 監控網路連接
netstat -an | grep :80
netstat -an | grep :443
```

### 效能監控

```bash
# 檢查 Nginx 進程
ps aux | grep nginx

# 查看連接數
ss -s

# 檢查檔案描述符
lsof -p $(pgrep nginx) | wc -l
```

## 🔧 緊急恢復程序

### 1. 快速重啟服務

```bash
# 重啟所有服務
docker-compose restart

# 只重啟 nginx
docker-compose restart elf-nginx

# 強制重建容器
docker-compose up -d --force-recreate
```

### 2. 配置回滾

```bash
# 備份當前配置
cp -r /opt/nginx-stack/nginx /opt/nginx-stack/nginx.backup.$(date +%Y%m%d_%H%M%S)

# 恢復預設配置
docker exec elf-nginx nginx -s stop
cp /etc/nginx/nginx.conf.backup /opt/nginx-stack/nginx/nginx.conf
docker exec elf-nginx nginx
```

### 3. 緊急維護模式

```bash
# 啟用維護頁面
echo "System maintenance in progress" > /var/www/html/maintenance.html

# 更新 nginx 配置使用維護頁面
docker exec elf-nginx nginx -s reload
```

## 📋 故障排除檢查清單

### 基本檢查

- [ ] Docker 服務正常運行
- [ ] 端口 80/443 未被其他服務占用
- [ ] 磁碟空間充足（>10% 可用）
- [ ] 記憶體使用正常（<90%）

### 配置檢查

- [ ] nginx 配置語法正確：`nginx -t`
- [ ] 所有必要配置文件存在
- [ ] 檔案權限正確
- [ ] SSL 憑證有效

### 網路檢查

- [ ] 容器間網路連通性
- [ ] 外部訪問正常
- [ ] DNS 解析正常
- [ ] 防火牆設定正確

### 日誌檢查

- [ ] 無嚴重錯誤日誌
- [ ] 訪問日誌記錄正常
- [ ] 錯誤日誌無異常
- [ ] WAF 審計日誌正常

### 效能檢查

- [ ] 響應時間正常（<2秒）
- [ ] 并發連接數正常
- [ ] CPU 使用率正常（<80%）
- [ ] 記憶體使用率正常（<80%）

## 🆘 聯繫支援

如果以上方法都無法解決問題，請收集以下信息並聯繫技術支援：

### 系統信息

```bash
# 收集系統信息
uname -a
docker --version
docker-compose --version
docker system info
```

### 服務狀態

```bash
# 收集服務狀態
docker-compose ps
docker-compose logs --tail=100
journalctl -u keepalived --no-pager -n 50
```

### 配置信息

```bash
# 收集配置信息
docker exec elf-nginx nginx -V
docker exec elf-nginx ls -la /etc/nginx/
cat /opt/nginx-stack/nginx/nginx.conf
