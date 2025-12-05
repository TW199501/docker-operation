# SQL Server Always On 三節點 + 中央管理伺服器 + 監控 架構規劃

## 1. 目標與前提

- **目標**
  - 建立一套以 Docker 為基礎的 SQL Server 2022 Always On 架構。
  - 採用 **3 個 SQL 節點** + **1 個中央管理伺服器** 的拓樸。
  - 未來可與現有 Nginx/HAProxy/keepalived 架構、Prometheus + Grafana 監控整合。
- **前提**
  - 各伺服器已安裝 Docker / Docker Compose。
  - 網路環境允許節點之間互通（TCP 1433、AG endpoint 連線埠等）。
  - 採用本專案 `SQLServer/oneSQLServer` 目錄中的設定作為「單節點」範本，再擴展成多節點。

---

## 2. 伺服器角色規劃

### 2.1 SQL 節點（Always On 成員）

- **DB-SQL-1（節點 A）**

  - Docker 容器名稱：`sqlnode1`（實際名稱可在 `.env` 中調整）。
  - 角色：AG **預設 Primary Replica**。
  - 任務：主要寫入節點，對外主要連線目標（透過 listener 或直接 IP）。
  - Host 目錄範例：
    - `/data/sqlnode1/sql_data`
    - `/data/sqlnode1/sql_log`
    - `/data/sqlnode1/sql_backup`
    - `/data/sqlnode1/sql_certs`
- **DB-SQL-2（節點 B）**

  - Docker 容器名稱：`sqlnode2`。
  - 角色：AG **同步 Secondary Replica**，支援 **自動/手動 failover**。
  - 任務：接管 Primary 故障時的角色；可提供唯讀查詢（選配）。
  - Host 目錄範例：
    - `/data/sqlnode2/sql_data`
    - `/data/sqlnode2/sql_log`
    - `/data/sqlnode2/sql_backup`
    - `/data/sqlnode2/sql_certs`
- **DB-SQL-3（節點 C）**

  - Docker 容器名稱：`sqlnode3`。
  - 角色：AG **Secondary Replica**（可設定為同步或非同步）。
  - 任務：
    - 作為額外 HA 節點，或
    - 作為 **唯讀報表 / ETL 節點**（建議非同步，降低對主系統影響）。
  - Host 目錄範例：
    - `/data/sqlnode3/sql_data`
    - `/data/sqlnode3/sql_log`
    - `/data/sqlnode3/sql_backup`
    - `/data/sqlnode3/sql_certs`

### 2.2 中央管理伺服器（不跑資料庫）

- **DB-ADMIN-1（中央管理與監控節點）**
  - 不啟動 SQL Server 資料庫實例。
  - 安裝工具：
    - `sqlcmd` / `bcp` / `sqlpackage` 等 SQL CLI 工具。
    - `cron` 或其他 job runner（之後可接 Jenkins / GitLab Runner）。
    - **Prometheus** + **Grafana**（監控平台）。
  - 任務：
    - 統一管理 **排程工作**：
      - 備份（完整 / 差異 / 交易記錄）。
      - Index / 統計資訊維護。
      - 健康檢查與報表。
    - 集中部署監控：
      - 從各 SQL 節點抓取 metrics（透過 exporter）。
      - 整合現有 Nginx / HAProxy / keepalived 節點的監控。

---

## 3. Docker 佈署模式與 .env 設定方向

### 3.1 單節點模板（oneSQLServer）

- 以 `SQLServer/oneSQLServer` 目錄為 **單一 SQL 節點模板**：
  - `.env.example`：定義容器名稱、對外 Port、Collation、資源限制等。
  - `generate-sa-password.sh`：產生符合複雜度的 `MSSQL_SA_PASSWORD`。
  - `bootstrap-sqlserver.sh`：互動式建立目錄 / `.env` / `docker compose up`。
- 多節點時：
  - 在每一台 DB-SQL-N 主機上，複製一份模板目錄（或下載對應腳本）。
  - 各自生成 `.env` 與目錄結構，避免共用同一份 Host 資料路徑。

### 3.2 共同環境變數（每個 SQL 节點）

以下為每個 SQL Docker 容器 `.env` 應共通的關鍵變數（實值視實際需求調整）：

```text
MSSQL_CONTAINER_NAME=sqlnode1            # 每台主機不同
MSSQL_SA_PASSWORD=強密碼（用 generate-sa-password.sh 產生）
MSSQL_PID=Developer                      # 或 Standard / Enterprise
MSSQL_COLLATION=Chinese_Taiwan_Stroke_Count_100_CI_AS_SC_UTF8
MSSQL_AGENT_ENABLED=true
MSSQL_ENABLE_HADR=1                      # 啟用 Always On HADR
TZ=Asia/Taipei

# 對外連線
MSSQL_HOST_PORT=1433                     # 視各節點防火牆與網段規劃而定

# Host 目錄位置（各節點獨立）
MSSQL_DATA_DIR_HOST=/data/sqlnode1/sql_data
MSSQL_LOG_DIR_HOST=/data/sqlnode1/sql_log
MSSQL_BACKUP_DIR_HOST=/data/sqlnode1/sql_backup
MSSQL_CERT_DIR_HOST=/data/sqlnode1/sql_certs

# 資源限制（範例）
MSSQL_LIMIT_CPU=4.0
MSSQL_LIMIT_MEM=12G
MSSQL_RESERVE_CPU=2.0
MSSQL_RESERVE_MEM=6G
```

> 實際上，`sqlnode2` / `sqlnode3` 會使用相同結構但不同 Host 目錄與容器名稱，以避免多台共用同一個磁碟目錄造成單點風險。

### 3.3 Volume 與憑證

- 每個節點透過 Docker volume 將 Host 目錄掛載到容器內：
  - 資料：`/var/opt/mssql/data`
  - 日誌：`/var/opt/mssql/log`
  - 備份：`/var/opt/mssql/backup`
  - 憑證：自訂路徑（例如 `/var/opt/mssql/certs`）
- 憑證用途：
  - Always On AG Endpoint（Database Mirroring Endpoint 的加密）。
  - TDS 加密（Client ↔ SQL 連線加密，選配）。

---

## 4. Always On Availability Group 拓樸建議

### 4.1 AG 拓樸

- 建議建立 1 組 AG，例如 `AG_Production`：
  - Replica 角色配置：
    - `sqlnode1`：Primary（同步 commit，允許 auto failover）。
    - `sqlnode2`：同步 Secondary（auto failover partner）。
    - `sqlnode3`：
      - 視需求選擇 **同步** 或 **非同步**。
      - 若作為報表節點，建議非同步 + 唯讀。

### 4.2 Listener（建議採用）

- 建議建立 AG Listener 以簡化連線設定：
  - Listener 名稱：例如 `sql-ag-listener` 或內網 FQDN。
  - Listener IP：設定在與節點相同的子網，配合 DNS 設定。
- 應用程式與中央管理伺服器的連線：
  - 優先連到 **Listener 名稱**，而不是單一節點 IP。
  - Failover 後，Listener 自動指向新的 Primary，無須修改連線字串。

### 4.3 Failover 策略

- 同步 Replica（`sqlnode1` ↔ `sqlnode2`）：
  - 支援 **自動 failover**。
  - 當 Primary 故障時自動切換到 Partner，縮短中斷時間。
- 第三節點（`sqlnode3`）：
  - 作為額外保險或報表節點，通常採 **手動 failover**。
  - 若是非同步，避免網路抖動時影響交易延遲。

---

## 5. 中央管理伺服器職責

### 5.1 排程類型

中央管理伺服器 **不承載應用程式業務**，專注於：

- 備份相關排程：
  - 完整備份（每日 / 每週）。
  - 差異備份（每日）。
  - 交易記錄備份（每幾分鐘一次，視 RPO 要求）。
- 維護工作：
  - Index 重建 / 重組。
  - 統計資訊更新。
  - 資料庫完整性檢查。
- 健康檢查與報表：
  - AG Replica 狀態與延遲。
  - 磁碟使用率與成長趨勢。
  - 高負載查詢與慢查詢統計（可搭配 DMV / Query Store）。

### 5.2 實作方式

- 作業系統：Linux（建議與你現有 Docker / Nginx 節點一致）。
- 工具建議：
  - `cron` 搭配 shell script + `sqlcmd`。
  - 每個 script 優先連到 **AG Listener**，而不是特定節點 IP。
  - 如需更複雜排程，可再疊加 Jenkins / GitLab Runner 等 CI/CD 工具。

---

## 6. 監控與現有 Nginx/HA 架構整合

### 6.1 每個 SQL 節點

- 安裝 exporter：
  - Node Exporter：CPU / 記憶體 / 磁碟 / 網路。
  - SQL Server Exporter：
    - 連線數、查詢延遲、等待統計。
    - AG Replica 狀態、同步延遲、Failover 次數等。

### 6.2 Nginx / HAProxy / keepalived 節點

- 從既有架構延伸：
  - Nginx Exporter：HTTP 連線數、錯誤比率等。
  - HAProxy Exporter：frontend/backend 連線、錯誤、延遲。
  - keepalived：
    - 透過 log / script 或 exporter 監控 VRRP 狀態與 VIP 所在節點。

### 6.3 中央監控平台

- 在中央管理伺服器部署：
  - **Prometheus**：抓取所有節點（3 個 SQL + Nginx/HA/keepalived 節點）。
  - **Grafana**：
    - 匯入 SQL Server / Node / Nginx / HAProxy / keepalived 等 Dashboard。
    - 設定告警規則，透過 Email / Webhook / Chat 工具通知。
