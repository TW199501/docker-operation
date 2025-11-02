## Cloudflare Tunnel Docker 組態

這份說明提供一套簡單的 Docker Compose 範本，用來部署 Cloudflare Tunnel 服務，並額外透過 Watchtower 自動更新容器。透過這個組態，您可以安全地將內部服務公開到網際網路，而不需在路由器上開放埠。

---

### 目錄
- [需求條件](#需求條件)
- [快速開始](#快速開始)
- [環境變數 (.env)](#環境變數-env)
- [可選設定：hosts](#可選設定hosts)
- [常用指令](#常用指令)
- [自動更新 (Watchtower)](#自動更新-watchtower)
- [故障排除](#故障排除)

---

### 需求條件
在開始前請確認：
1. 已安裝 [Docker](https://docs.docker.com/get-docker/)
2. 已安裝 [Docker Compose](https://docs.docker.com/compose/)
3. 您的網域 DNS 由 Cloudflare 管理，並可存取 Cloudflare Zero Trust/Access 介面建立 Tunnel Token。

---

### 快速開始
1. **取得程式碼**
   ```bash
   git clone https://github.com/TW199501/docker-operation.git
   cd docker-operation/cloudflare
   ```

2. **設定環境變數** (`.env`)
   - 依照 [環境變數 (.env)](#環境變數-env) 章節建立 `.env`。

3. **啟動服務**
   ```bash
   docker compose up -d
   ```
   - `cloudflare-tunnel` 會依照 `CLOUDFLARE_TUNNEL_TOKEN` 與 `config/hosts` 內的設定啟動。
   - `watchtower` 會自動監控並更新被標記允許的容器。

---

### 環境變數 (.env)
專案已提供 `.env.example` 作為範本：

```bash
CLOUDFLARE_TUNNEL_TOKEN=your_actual_tunnel_token_here
```

操作步驟：
1. 複製範本
   ```bash
   cp .env.example .env
   ```
2. 取得 Cloudflare Tunnel Token：
   - 登入 Cloudflare 儀表板 → Zero Trust/Access → Tunnels。
   - 建立新隧道，完成後複製提供的 Token。
3. 編輯 `.env`，將 `your_actual_tunnel_token_here` 換成實際 Token。

> 建議：為避免 `.env` 被版本控制追蹤，根目錄的 `.gitignore` 已忽略 `.env`。

---

### 可選設定：`hosts`
- `cloudflare/config/hosts` 會掛載至容器的 `/etc/hosts`。
- 如需自訂內部 DNS 對應，可在該檔案內新增，例如：
  ```
  192.168.1.10   internal-app.local
  ```
- 若不需要額外對應，可保留預設檔案。

---

### 常用指令
- **啟動服務**
  ```bash
  docker compose up -d
  ```
- **查看服務狀態**
  ```bash
  docker compose ps
  ```
- **查看 Cloudflare Tunnel 日誌**
  ```bash
  docker logs -f cloudflare-tunnel
  ```
- **停止服務**
  ```bash
  docker compose down
  ```
- **清除容器與匿名 Volume**
  ```bash
  docker compose down -v
  ```

---

### 自動更新 (Watchtower)
- `docker-compose.yml` 內建 [Watchtower](https://containrrr.dev/watchtower/) 服務。
- 只會更新帶有 `com.centurylinklabs.watchtower.enable=true` 標籤的容器（目前為 `cloudflare-tunnel`）。
- 啟動後 Watchtower 會定期檢查映像是否有新版，若有更新會拉取新映像並重新啟動容器。
- `--cleanup` 參數會自動刪除舊映像，減少磁碟占用。

如需調整更新頻率或通知方式，可參考 Watchtower 官方文件。

---

### 故障排除
- **Tunnel 無法啟動**：
  - 確認 `.env` 的 Token 是否正確。
  - 檢查伺服器時間是否同步（已掛載 `/etc/localtime`，但仍建議啟用 NTP）。

- **Watchtower 未更新容器**：
  - 確認目標容器是否有設定 `com.centurylinklabs.watchtower.enable=true`。
  - 檢查 Watchtower 日誌：
    ```bash
    docker logs -f watchtower
    ```

---

