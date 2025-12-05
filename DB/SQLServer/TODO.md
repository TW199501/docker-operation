# SQL Server Always On TODO

## 1. 目標與前提

- [ ] TODO: (項目1-1)盤點業務需求與可用性 / RPO / RTO 目標
- [ ] TODO: (項目1-2)盤點現有 Proxmox / 儲存 / 網路資源並確認可用容量
- [ ] TODO: (項目1-3)確認 SQL Server 版本與授權策略（Developer / Standard / Enterprise）
- [ ] TODO: (項目1-4)依最終決策更新 ARCHITECTURE.md 的目標與前提章節

## 2. 伺服器角色規劃

- [ ] TODO: (項目2-1)實體建立三台 SQL 節點（DB-SQL-1/2/3）與一台中央管理伺服器（DB-ADMIN-1）
- [ ] TODO: (項目2-2)為各節點規劃主機名稱與 IP 配置，確認與現有 Nginx/HA 架構網段相容
- [ ] TODO: (項目2-3)為各節點規劃 CPU、記憶體、磁碟等硬體資源與驗收標準（含主機取名與預留餘裕）

## 3. Docker 佈署模式與 .env 設定

- [ ] TODO: (項目3-1)在每台節點主機建立 SQLServer 專用基底目錄（例如 /opt/sqlserver-nodeX）
- [ ] TODO: (項目3-2)從 SQLServer/oneSQLServer 下載或複製模板檔案到各節點目錄
- [ ] TODO: (項目3-3)為 DB-SQL-1 產生 `.env` 並填寫容器名稱、Port、目錄與資源限制
- [ ] TODO: (項目3-4)為 DB-SQL-2 產生 `.env` 並填寫容器名稱、Port、目錄與資源限制
- [ ] TODO: (項目3-5)為 DB-SQL-3 產生 `.env` 並填寫容器名稱、Port、目錄與資源限制
- [ ] TODO: (項目3-6)為三個 SQL 節點建立資料/日誌/備份/憑證目錄並設定正確擁有者與權限
- [ ] TODO: (項目3-7)在三個 SQL 節點的容器中啟用 MSSQL_ENABLE_HADR 並驗證 HADR 已成功啟用

## 4. Always On AG 拓樸與 Listener

- [ ] TODO: (項目4-1)在三個 SQL 節點上建立 Database Mirroring Endpoint 並設定加密與驗證
- [ ] TODO: (項目4-2)選定初始 Primary 節點並建立 AG_Production（不含資料庫）
- [ ] TODO: (項目4-3)在三個節點上建立要加入 AG 的資料庫並完成初次完整/差異備份與還原
- [ ] TODO: (項目4-4)將資料庫加入 AG_Production 並設定同步 / 非同步模式與自動/手動 failover 條件
- [ ] TODO: (項目4-5)建立 AG Listener，設定 Port / DNS / IP 並驗證從各節點與應用程式皆可連線
- [ ] TODO: (項目4-6)撰寫並驗證手動 failover / 強制 failover 的操作腳本與步驟文件

## 5. 中央管理伺服器與排程

- [ ] TODO: (項目5-1)在 DB-ADMIN-1 安裝 SQL CLI 工具（sqlcmd / bcp / sqlpackage 等）
- [ ] TODO: (項目5-2)在 DB-ADMIN-1 規劃 scripts / logs / backup-metadata 等排程目錄結構
- [ ] TODO: (項目5-3)撰寫完整備份腳本並測試可透過 AG Listener 成功備份所有主要資料庫
- [ ] TODO: (項目5-4)撰寫差異與交易記錄備份腳本並確認備份鏈可成功還原
- [ ] TODO: (項目5-5)撰寫索引維護與統計資訊更新腳本並排程在非尖峰時段執行
- [ ] TODO: (項目5-6)撰寫資料庫健康檢查與 AG 狀態報表腳本並排程執行

## 6. 監控與告警

- [ ] TODO: (項目6-1)在三個 SQL 節點安裝 Node Exporter 並設定為服務隨開機啟動
- [ ] TODO: (項目6-2)在三個 SQL 節點安裝 SQL Server Exporter 並配置連線帳號與權限
- [ ] TODO: (項目6-3)在 Nginx / HAProxy / keepalived 節點安裝或啟用對應 exporter
- [ ] TODO: (項目6-4)在 DB-ADMIN-1 安裝 Prometheus 並撰寫 scrape config 納入所有 exporter
- [ ] TODO: (項目6-5)為 Prometheus 設定資料保留時間與儲存路徑，評估磁碟用量
- [ ] TODO: (項目6-6)在 DB-ADMIN-1 安裝 Grafana 並連接到 Prometheus data source
- [ ] TODO: (項目6-7)匯入或建立 SQL / Node / Nginx / HAProxy / keepalived 的 Dashboard
- [ ] TODO: (項目6-8)為關鍵指標（CPU/記憶體/磁碟/AG 狀態/失敗連線）設定告警規則與通知管道
