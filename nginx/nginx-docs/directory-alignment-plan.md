---
description: nginx directory alignment and script integration plan
---
# NGINX 目錄與腳本整合計畫

## 背景

目前 `nginx` 相關腳本（`00-preflight-nginx.sh`, `10-build-nginx.sh`, `update_geoip2_cf_ip.sh`, `ufw-cf-allow.sh` 等）各自負責不同階段：

- **00-preflight**：準備帳號與目錄權限。
- **10-build**：編譯/安裝 Nginx、配置模組與 baseline 設定。
- **update_geoip2_cf_ip**：部署 GeoIP2 與 Cloudflare real_ip 更新腳本與排程。
- **ufw-cf-allow**：針對 UFW 與 Cloudflare 範圍的同步。
- **a87-unified-nginx-network** 等其他腳本提供選用功能（firewalld、UFW、GeoIP 整合）。

為確保環境符合官方/主流發行版的目錄慣例並降低重複部署，我們需要整理正規目錄與腳本整合方案。

## 目前已遵循的官方目錄

`10-build-nginx.sh` 已將建置後的主要路徑對齊 Debian/Ubuntu 以及 upstream Nginx 的慣例：

| 類型            | 目錄                                                        | 說明                                      | 來源腳本                                            |
| --------------- | ----------------------------------------------------------- | ----------------------------------------- | --------------------------------------------------- |
| 執行檔          | `/usr/sbin/nginx`                                         | 主程式                                    | `--sbin-path` in `10-build-nginx.sh`            |
| 動態模組        | `/usr/lib/nginx/modules/`                                 | `load_module` 目標，符合官方預設        | `--modules-path` + `cp objs/*.so`               |
| 主設定          | `/etc/nginx/nginx.conf`                                   | 全域設定                                  | `--conf-path`                                     |
| conf.d          | `/etc/nginx/conf.d/`                                      | 處理站台與 real_ip include                | `--http` include + scripts                        |
| sites-available | `/etc/nginx/sites-available/`                             | 儲存站台原始設定檔，透過 symlink 控制啟用 | 尚未自動建立（需新增步驟）                          |
| sites-enabled   | `/etc/nginx/sites-enabled/`                               | 指向啟用站台的符號連結                    | 尚未自動建立（需新增步驟）                          |
| modules.d       | `/etc/nginx/modules.d/`                                   | 動態模組載入清單                          | `10-build-nginx.sh` 產生 `00-load-modules.conf` |
| 暫存            | `/var/cache/nginx/{client_temp,...}`                      | HTTP 模組快取                             | `--http-*-temp-path` + `ensure_nginx_run_user`  |
| 日誌            | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` | 預設 log                                  | `--http-log-path`, `--error-log-path`           |
| PID/Lock        | `/run/nginx.pid`, `/run/nginx.lock`                     | 進程資訊                                  | `--pid-path`, `--lock-path`                     |

因此核心安裝路徑已符合官方建議，後續調整聚焦在周邊腳本與排程統一。

## 預計調整方向

1. **統一 Cloudflare UFW 腳本部署**

   - `ufw-cf-allow.sh` 需確保使用 `CF_PORTS` 配置，並在統一流程中被安裝/排程。
   - 考慮讓 `10-build-nginx.sh` 或新整合腳本在建置完成後執行 `ufw-cf-allow.sh` 安裝段。
2. **標準化 GeoIP2/CF real_ip 更新**

   - `update_geoip2_cf_ip.sh` 目前會寫 `/usr/local/sbin/update_geoip2.sh` 並用 `/etc/crontab` 安排；
   - 可改為 systemd timer（若存在）或 `/etc/cron.d/`，統一與 `a87-unified-nginx-network.sh` 的作法。
3. **新增 sites-available / sites-enabled 支援**

   - 在建置流程中建立 `/etc/nginx/sites-available`、`/etc/nginx/sites-enabled` 目錄。
   - 在 `nginx.conf` 中加入 `include /etc/nginx/sites-enabled/*;`，並於腳本示範使用 `ln -s` 啟用站台。
   - 更新 `10-build-nginx.sh` 或共用函式，確保目錄權限與範例設定同步建立。
4. **整合 UFW/GeoIP 流程**

   - `a87-unified-nginx-network.sh` 已提供整合，需加入對新版 `ufw-cf-allow.sh`、`update_cf_ip.sh` 的部署步驟，避免兩套腳本重疊。
5. **文件化與維運指引**

   - 在 `nginx-docs/` 下維護流程說明，包含：
     1. 建置前環境檢查 (`00-preflight`)
     2. 編譯安裝 (`10-build`)
     3. 選擇性模組腳本（ModSecurity 等）
     4. 網路/防火牆整合（CF UFW、firewalld）
     5. 排程與維護（GeoIP2 更新、UFW 同步）

## 整合多支腳本的建議流程

1. **Preflight**：`00-preflight-nginx.sh` — 建立使用者/目錄。
2. **Build**：`10-build-nginx.sh` — 完成編譯與基本配置，執行後確認 `nginx -t`。
3. **Security Add-ons（選用）**：例如 `15-modsecurity-nginx.sh`。
4. **Network Integration**：
   - 執行改版後的 `a87-unified-nginx-network.sh`，統一部署 `ufw-cf-sync`/`update_geoip2.sh` 並建立 cron/timer。
   - 若僅需 GeoIP2/CF real_ip，可直接跑 `update_geoip2_cf_ip.sh`。
5. **Optional Services**：如 `25-nginxwebui-install.sh` 等其他服務腳本。
6. **驗證**：統一以 `nginx -t`、`ufw status numbered`、`systemctl timers` 進行。

> 下一步：更新 `a87-unified-nginx-network.sh` 以部署新版本 `ufw-cf-allow.sh`、`update_cf_ip.sh`，並將 `update_geoip2_cf_ip.sh` 的排程改用 `cron.d` 或 systemd timer，以避免多套排程互相覆蓋。
> 同時在 `10-build-nginx.sh` 補上 `sites-available`/`sites-enabled` 目錄建立與 `include` 指令，加上示範 symlink 流程。

## 預期完成後的目錄樹

```text
/etc/nginx/
├── nginx.conf
├── conf.d/
│   ├── 00-realip.conf
│   └── ...
├── modules.d/
│   └── 00-load-modules.conf
├── sites-available/
│   ├── default.conf
│   └── example.com.conf
└── sites-enabled/
    ├── default.conf -> /etc/nginx/sites-available/default.conf
    └── example.com.conf -> /etc/nginx/sites-available/example.com.conf

/usr/lib/nginx/modules/
├── ngx_http_geoip2_module.so
├── ngx_http_brotli_filter_module.so
└── ...

/usr/local/sbin/
├── ufw-cf-sync.sh
├── ufw-cf-allow.sh (若沿用舊腳本)
├── update_geoip2.sh
└── update_cf_ip.sh

/var/log/
└── nginx/
    ├── access.log
    └── error.log
```

## TODO Checklist

- [X] `10-build-nginx.sh` 建立 `/etc/nginx/sites-available`、`/etc/nginx/sites-enabled`，並在 `nginx.conf` 加入 `include /etc/nginx/sites-enabled/*;`。
- [X] 提供範例 server 檔與 symlink 建立範本（default.conf）。
- [X] 更新 `a87-unified-nginx-network.sh` 以部署新版 `ufw-cf-allow.sh` / `update_cf_ip.sh`。
- [X] 將 `update_geoip2_cf_ip.sh` 排程改為 `/etc/cron.d` 或 systemd timer。
- [X] 在文件補充整合測試步驟（`nginx -t`、`ufw status`、`systemctl list-timers`）。

## 附錄：範例站台與符號連結

- 範例檔：`nginx/sites-available/default.conf`，對應腳本生成的預設 VirtualHost。
- 符號連結示範：

  ```bash
  sudo ln -s /etc/nginx/sites-available/example.com.conf /etc/nginx/sites-enabled/example.com.conf
  sudo nginx -t && sudo systemctl reload nginx
  ```

## 整合測試與驗證步驟

1. **Nginx 配置**：

   - `sudo nginx -t`
   - `sudo systemctl reload nginx`
2. **UFW 狀態**（若啟用）：`sudo ufw status numbered | sed -n '1,60p'`
3. **firewalld ipset**（若啟用）：`sudo firewall-cmd --permanent --ipset=cloudflare4 --get-entries | head`
4. **排程確認**：

   - systemd：`systemctl list-timers update-geoip2.timer ufw-cf-sync.timer 2>/dev/null`
   - cron.d：`sudo grep update /etc/cron.d/*`
5. **腳本單次執行**：

   - `/usr/local/sbin/ufw-cf-allow.sh --help`（或直接執行確認）
   - `/usr/local/sbin/update_geoip2.sh`

目前流程可以這樣定位：

1. **建置/安裝腳本**

   - [10-build-nginx.sh](cci:7://file:///d:/app/docker-operation/nginx/10-build-nginx.sh:0:0-0:0)、[25-nginxwebui-install.sh](cci:7://file:///d:/app/docker-operation/nginx/25-nginxwebui-install.sh:0:0-0:0) 在編譯或安裝後，不會主動部署 Cloudflare-UFW 腳本，也不會設定 GeoIP2 排程。
   - 如果需要自動做這件事，可以考慮在流程中新增一步，呼叫專門的部署腳本。
2. **設定排程 & Cloudflare 放行**

   - [ufw-cf-allow.sh](cci:7://file:///d:/app/docker-operation/nginx/ufw-cf-allow.sh:0:0-0:0)（或更新後的 `ufw-cf-sync.sh` 類腳本）負責同步 Cloudflare 的 IP 並寫入 UFW 規則，記得執行後也設定對應 crontab/systemd timer。
   - [update_geoip2_cf_ip.sh](cci:7://file:///d:/app/docker-operation/nginx/update_geoip2_cf_ip.sh:0:0-0:0) 或 [a87-unified-nginx-network.sh](cci:7://file:///d:/app/docker-operation/nginx/a87-unified-nginx-network.sh:0:0-0:0) 會安裝 `/usr/local/sbin/update_geoip2.sh`，這支每次跑會更新 GeoIP2 mmdb 與 Cloudflare real_ip 清單，同時可在排程裡安排每週固定時間執行。
3. **整合建議**

   - 在主要編譯腳本完成後，手動或加碼碼流程呼叫上述同步腳本，確保 Cloudflare IP 已加到 UFW、GeoIP2 更新排程也就位。
   - 若要統一流程，可擴充 [a87-unified-nginx-network.sh](cci:7://file:///d:/app/docker-operation/nginx/a87-unified-nginx-network.sh:0:0-0:0)，讓它也部署最新的 [ufw-cf-allow.sh](cci:7://file:///d:/app/docker-operation/nginx/ufw-cf-allow.sh:0:0-0:0) / `update_cf_ip.sh`，就能一次搞定防火牆與 GeoIP 的排程。
