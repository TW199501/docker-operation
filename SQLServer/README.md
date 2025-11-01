當然可以！這裡把「可行且精簡」的語法整理成一頁小抄，照其中一組跑即可。

# 最短可行（主機預先建目錄 + docker run）

```bash
# 主機上準備掛載目錄
sudo mkdir -p /vol2/1000/ssd/app-data/mssql2022/{data,log,backup}
sudo chown -R 10001:0 /vol2/1000/ssd/app-data/mssql2022
sudo chmod -R 770 /vol2/1000/ssd/app-data/mssql2022

# 啟動容器（SELinux 主機建議加 :Z）
docker run -d --name mssql2022 \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD='YourStrong!Passw0rd' \
  -e MSSQL_DATA_DIR=/var/opt/mssql/data \
  -e MSSQL_LOG_DIR=/var/opt/mssql/log \
  -e MSSQL_BACKUP_DIR=/var/opt/mssql/backup \
  -p 1433:1433 \
  -v /vol2/1000/ssd/app-data/mssql2022:/var/opt/mssql:Z \
  --user 10001:0 \
  mcr.microsoft.com/mssql/server:2022-latest
```

# 已在跑的容器（進去修權限）

```bash
# 以 root 進容器
docker exec -u 0 -it mssql2022 bash

# 修正 /var/opt/mssql 及自訂路徑擁有者與權限
chown -R 10001:0 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022
chmod -R 770 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022

exit
docker restart mssql2022
```

# 驗證

```bash
# 目錄與權限
ls -ld /vol2/1000/ssd/app-data/mssql2022
ls -ld /vol2/1000/ssd/app-data/mssql2022/{data,log,backup}

# 看到類似 drwxrwx--- 10001 0 即正確
```

以下是 **生成自簽名 SSL/TLS 憑證** 的 OpenSSL 命令語法，適用於 SQL Server 加密連線：

---

### **1. 生成自簽名憑證**
```bash
openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
    -keyout sqlserver.key -out sqlserver.crt \
    -subj "/CN=your-server-name" \
    -days 365
```

#### **參數說明**：
- `-x509`: 生成自簽名憑證。
- `-newkey rsa:4096`: 使用 RSA 4096 位元加密。
- `-sha256`: 使用 SHA-256 雜湊演算法。
- `-nodes`: 不加密私鑰（無密碼）。
- `-keyout`: 私鑰輸出檔案。
- `-out`: 憑證輸出檔案。
- `-subj`: 憑證主體（替換 `your-server-name` 為你的伺服器名稱或 IP）。
- `-days 365`: 憑證有效期（天數）。

---

### **2. 合併憑證和私鑰（可選）**
```bash
cat sqlserver.crt sqlserver.key > sqlserver.pem
```

---

### **3. 設定檔案權限**
```bash
chmod 644 sqlserver.key sqlserver.crt
```

---

### **4. 將憑證掛載到容器**
在 `docker-compose.yml` 中新增掛載（如果尚未設定）：
```yaml
volumes:
  - /path/to/certs:/etc/mssql/certs
```

---

### **5. SQL Server 使用憑證**
```sql
USE master;
GO
CREATE CERTIFICATE SqlServerTLSCert
FROM FILE = '/etc/mssql/certs/sqlserver.crt'
WITH PRIVATE KEY (
    FILE = '/etc/mssql/certs/sqlserver.key',
    DECRYPTION BY PASSWORD = ''  -- 如果私鑰有密碼則填寫
);
GO
```

---

### **注意事項**
1. **生產環境建議**：  
   - 自簽名憑證僅適用於測試，生產環境請使用 CA 簽發的憑證（如 Let's Encrypt）。
2. **憑證路徑**：  
   - 確保掛載路徑與 SQL Server 中的路徑一致。
3. **重啟服務**：  
   - 載入憑證後需重啟 SQL Server 服務。



   以下是 **使用 Docker 容器化申請 Let's Encrypt 憑證** 的方法（支援 Cloudflare DNS 驗證），無需手動安裝工具：

---

### **1. 使用 `certbot/dns-cloudflare` 鏡像**
此鏡像已內建 `certbot` 和 Cloudflare DNS 插件，適合在 Docker 中運行。

#### **步驟 1: 準備 Cloudflare API 憑證**
建立配置文件 `~/cloudflare.ini`：
```ini
dns_cloudflare_email = your_email@example.com
dns_cloudflare_api_key = your_cloudflare_api_key
```
- 替換 `your_email@example.com` 和 `your_cloudflare_api_key`（從 Cloudflare 儀表板獲取）。

#### **步驟 2: 運行 certbot 容器**
```bash
docker run -it --rm \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "/path/to/cloudflare.ini:/cloudflare.ini" \
  certbot/dns-cloudflare certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  -d yourdomain.com \
  -d sql.yourdomain.com
```

#### **步驟 3: 自動續期**
```bash
docker run --rm \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "/path/to/cloudflare.ini:/cloudflare.ini" \
  certbot/dns-cloudflare renew
```

---

### **2. 使用 `acme.sh` 鏡像**
#### **步驟 1: 運行 acme.sh 容器**
```bash
docker run --rm \
  -v "/path/to/certs:/acme.sh" \
  -e CF_Email="your_email@example.com" \
  -e CF_Key="your_cloudflare_api_key" \
  neilpang/acme.sh --issue \
  --dns dns_cf \
  -d yourdomain.com \
  -d sql.yourdomain.com
```

#### **步驟 2: 自動續期**
```bash
docker run --rm \
  -v "/path/to/certs:/acme.sh" \
  neilpang/acme.sh --renew -d yourdomain.com
```

---

### **3. 掛載憑證到 SQL Server 容器**
修改 `docker-compose.yml`，將憑證掛載到 SQL Server：
```yaml
volumes:
  - /etc/letsencrypt/live/yourdomain.com/fullchain.pem:/etc/mssql/certs/sqlserver.crt
  - /etc/letsencrypt/live/yourdomain.com/privkey.pem:/etc/mssql/certs/sqlserver.key
```

---

### **4. 注意事項**
1. **憑證路徑**：  
   - 確保主機路徑（如 `/etc/letsencrypt`）存在且可讀。
2. **權限問題**：  
   ```bash
   chmod 644 /etc/letsencrypt/live/yourdomain.com/*
   ```
3. **Cloudflare 代理設定**：  
   - 在 Cloudflare DNS 設定中，暫時關閉代理（設定為「DNS only」）。

---

以下是 **生成自簽名 SSL/TLS 憑證** 的 OpenSSL 命令語法，適用於 SQL Server 加密連線：

---

### **1. 生成自簽名憑證**
```bash
openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
    -keyout sqlserver.key -out sqlserver.crt \
    -subj "/CN=your-server-name" \
    -days 365
```

#### **參數說明**：
- `-x509`: 生成自簽名憑證。
- `-newkey rsa:4096`: 使用 RSA 4096 位元加密。
- `-sha256`: 使用 SHA-256 雜湊演算法。
- `-nodes`: 不加密私鑰（無密碼）。
- `-keyout`: 私鑰輸出檔案。
- `-out`: 憑證輸出檔案。
- `-subj`: 憑證主體（替換 `your-server-name` 為你的伺服器名稱或 IP）。
- `-days 365`: 憑證有效期（天數）。

---

### **2. 合併憑證和私鑰（可選）**
```bash
cat sqlserver.crt sqlserver.key > sqlserver.pem
```

---

### **3. 設定檔案權限**
```bash
chmod 644 sqlserver.key sqlserver.crt
```

---

### **4. 將憑證掛載到容器**
在 `docker-compose.yml` 中新增掛載（如果尚未設定）：
```yaml
volumes:
  - /path/to/certs:/etc/mssql/certs
```

---

### **5. SQL Server 使用憑證**
```sql
USE master;
GO
CREATE CERTIFICATE SqlServerTLSCert
FROM FILE = '/etc/mssql/certs/sqlserver.crt'
WITH PRIVATE KEY (
    FILE = '/etc/mssql/certs/sqlserver.key',
    DECRYPTION BY PASSWORD = ''  -- 如果私鑰有密碼則填寫
);
GO
```

---

### **注意事項**
1. **生產環境建議**：  
   - 自簽名憑證僅適用於測試，生產環境請使用 CA 簽發的憑證（如 Let's Encrypt）。
2. **憑證路徑**：  
   - 確保掛載路徑與 SQL Server 中的路徑一致。
3. **重啟服務**：  
   - 載入憑證後需重啟 SQL Server 服務。

如果需要進一步調整或驗證，請告訴我！