



## 🌟 建議規格（可穩定多人同時用 + 跑容器 / 編譯）

| 資源      | 規格                               |
| ------- | -------------------------------- |
| CPU     | **8 核心 / 16 執行緒**                |
| 記憶體 RAM | **16GB～24GB**（每人預留 2～3GB）        |
| 硬碟      | **NVMe SSD 100GB+**              |
| 網路      | 至少 1Gbps（區域內訪問或透過 Cloudflare）    |
| OS      | Ubuntu Server / Debian / Rocky 9 |
| 安全性     | 建議搭配 Nginx + SSL + 防火牆           |

👉 適用於：多人共同編輯、使用 Git、跑 npm build、Docker compose 測試等情境。

---

## ⚙️ 容器化建議架構（可搭配 Docker Compose）

```yaml
services:
  code-server:
    image: codercom/code-server:latest
    ports:
      - "8443:8443"
    volumes:
      - /data/code:/home/coder/project
    environment:
      - PASSWORD=yourpassword
    restart: unless-stopped
```

如每人獨立容器，可建立 6 個 service + Nginx 代理子路徑，例如：

```
https://dev.yourdomain.com/alice
https://dev.yourdomain.com/bob
```

---

## 🛡️ 加值建議（多人穩定使用）

| 項目                    | 建議配置說明                                 |
| --------------------- | -------------------------------------- |
| Nginx + Let's Encrypt | 提供 HTTPS 與登入保護                         |
| PostgreSQL / Redis    | 可加裝 DB 工具，用 Code Server 操作             |
| Git 持久化               | 每個使用者資料夾獨立掛載，避免編輯衝突                    |
| 每人固定 workspace        | 利用 Nginx 子路徑或多容器分離                     |
| 使用 Cloudflare Tunnel  | 若無固定 IP 可用 Cloudflare proxy 保障連線穩定性與保護 |

---

## 📌 結語

| 使用人數 | 最低可用（共用容器）         | 推薦配置（每人穩定流暢）               |
| ---- | ------------------ | -------------------------- |
| 6 人  | 4C / 8G / 50GB SSD | 8C / 24G / 100GB+ NVMe SSD |

```
project-root/
├── Dockerfile
├── docker-compose.yml
├── users/
│   ├── eddie/
│   └── bob/

```