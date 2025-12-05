# SQL Server Docker 部署指南

提供兩種方式快速部署 SQL Server 2022：

1. **建議**：使用互動式腳本一次完成目錄建立、密碼產生、`.env` 撰寫與 `docker compose up`。
2. **進階**：手動依指令逐步建置，方便客製化或除錯。

---

## 目錄

1. [快速開始（互動式腳本）](#快速開始互動式腳本)
2. [腳本下載一覽（選用）](#腳本下載一覽選用)

---

## 快速開始（互動式腳本）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/bootstrap-sqlserver.sh)"
chmod +x bootstrap-sqlserver.sh
sudo ./bootstrap-sqlserver.sh
```

> Docker Compose v2 (`docker compose`) 必須已可使用。

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

## 腳本下載一覽（選用）

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
