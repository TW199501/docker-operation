## SQL Server Docker 部署指南

提供兩種方式快速部署 SQL Server 2022：
1. **建議**：使用互動式腳本一次完成目錄建立、密碼產生、`.env` 撰寫與 `docker compose up`。
2. **進階**：手動依指令逐步建置，方便客製化或除錯。

---

### 目錄
1. [快速開始（互動式腳本）](#1-快速開始互動式腳本)
2. [腳本下載一覽（選用）](#2-腳本下載一覽選用)
3. [手動部署步驟](#3-手動部署步驟)
4. [已運行容器的權限修正](#4-已運行容器的權限修正)
5. [檢查與驗證](#5-檢查與驗證)

---

### 1. 快速開始（互動式腳本）

> Docker Compose v2 (`docker compose`) 必須已可使用。

```bash
curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/bootstrap-sqlserver.sh -o bootstrap-sqlserver.sh
chmod +x bootstrap-sqlserver.sh
sudo ./bootstrap-sqlserver.sh
```

腳本會自動檢查 `docker-compose.yml`，若缺少會從遠端下載範例（或依提示重新下載最新版），接著會問你：
- 資料存放路徑（會自動產生 `sql_data/sql_log/sql_backup/certs`）
- 容器名稱、對外 Port、Collation、資源限制
- 是否自動產生符合複雜度的 `MSSQL_SA_PASSWORD`
- 是否立即執行 `docker compose up -d`

腳本完成後會產生：
- `.env`：寫入所有必要參數（容器名稱、主機路徑、密碼、資源限制等）供 `docker-compose.yml` 引用
- 已就緒的資料夾權限（可選擇 chown 10001:0）
-（若選擇）已啟動的 SQL Server 容器

---

### 2. 腳本下載一覽（選用）

- 最新 `docker-compose.yml`（需搭配 `.env` 使用）：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/docker-compose.yml -o docker-compose.yml
  ```
- 單獨產生 SA 密碼：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/generate-sa-password.sh -o generate-sa-password.sh
  chmod +x generate-sa-password.sh
  ./generate-sa-password.sh 24   # 可自行調整長度（>=12）
  ```

---

### 3. 手動部署步驟

若想完全掌控每一步，可依下方流程自行操作。

1. 建立資料目錄與權限（路徑請依實際環境調整）：
   ```bash
   sudo mkdir -p /vol2/1000/ssd/app-data/mssql2022/{data,log,backup,certs}
    sudo chown -R 10001:0 /vol2/1000/ssd/app-data/mssql2022
    sudo chmod -R 770 /vol2/1000/ssd/app-data/mssql2022
   ```

2. 啟動容器（SELinux 主機建議在 volume 後加 `:Z`）：
   ```bash
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

3. 自訂 `docker-compose.yml`：若要改用 Compose，請依 `.env.example` 填寫所有必要變數（包含主機路徑、容器名稱、資源限制與密碼），然後執行：
  ```bash
  docker compose up -d
  ```
  > `.env` 缺少任何變數都會導致啟動失敗；建議先將 `.env.example` 複製成 `.env` 再依需求調整。

---

### 4. 已運行容器的權限修正

```bash
# 以 root 進容器
docker exec -u 0 -it mssql2022 bash

# 修正 /var/opt/mssql 及自訂路徑擁有者與權限
chown -R 10001:0 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022
chmod -R 770 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022

exit
docker restart mssql2022
```

---

### 5. 檢查與驗證

```bash
# 目錄與權限
ls -ld /vol2/1000/ssd/app-data/mssql2022
ls -ld /vol2/1000/ssd/app-data/mssql2022/{data,log,backup,certs}

# 看到類似 drwxrwx--- 10001 0 即正確
```

如需 SSL 憑證，可搭配 `certbot` 或 `acme.sh` 章節取得憑證後，掛載到 `.env` 中指定的 `MSSQL_CERT_DIR_HOST` 路徑。*** End Patch
