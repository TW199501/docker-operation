```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/10-build-nginx.sh)"
```

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/15-modsecurity-nginx.sh)"
```

**cd** **/home/nginx\_build\_geoip2**   **# 依你實際位置**
cd** **nginx**                      **# 對應 d:\\app\\docker-operation\\nginx
chmod** **+x** **check-build-nginx.sh** **# 第一次需要
./check-build-nginx.sh**        **# 預設檢查 build-nginx.sh


就現在這支 [build-nginx.sh](cci:7://file:///d:/app/docker-operation/nginx/build-nginx.sh:0:0-0:0)，實際會用到/產生的「重點目錄」整理給你，方便你確認生態系：

### 1. 編譯用工作目錄

- **`$BUILD_DIR`**（預設你自己外面設，例如 `/home/nginx_build_geoip2`）
  - `nginx-${NGINX_VERSION}/`  → Nginx 原始碼與編譯輸出
  - `ngx_http_geoip2_module/`
  - `ngx_brotli/`
  - `headers-more-nginx-module/`
  - `ngx_cache_purge/`
  - `njs/`
  - `pcre2/`                   → PCRE2 git
  - `zlib-1.3.1/`              → zlib 原始碼
  - `openssl-3.5.4/`           → OpenSSL 原始碼
  - `goaccess/`                → GoAccess git
  - `ngx_brotli/deps/brotli/out/` → brotli 靜態庫 build 輸出

### 2. Nginx 安裝與設定目錄

- **`$NGINX_ETC`**（腳本裡預設 `/etc/nginx`）

  - `$NGINX_ETC/nginx.conf`
  - `$NGINX_ETC/conf.d/`
  - `$NGINX_ETC/sites-available/`
  - `$NGINX_ETC/sites-enabled/`
  - `$NGINX_ETC/geoip/`          → GeoIP2 mmdb、CF real_ip conf
  - `$NGINX_ETC/modules/`        → `00-load-modules.conf`
  - `$NGINX_ETC/ssl/`            → 700 權限的憑證目錄
  - `$NGINX_ETC/scripts/`        → 放自訂 sh 腳本的目錄
- **模組實體檔**

  - `/usr/lib/nginx/modules/`    → `*.so`（geoip2、brotli、headers-more、cache_purge、njs、image_filter…）
- **執行檔 / pid / log**

  - `/usr/sbin/nginx`
  - `/run/nginx.pid`
  - `/run/nginx.lock`
  - `/var/log/nginx/error.log`
  - `/var/log/nginx/access.log`
  - `/var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}/`

### 3. GeoIP2 / Cloudflare real_ip

- `/etc/nginx/geoip/`
  - `GeoLite2-ASN.mmdb`
  - `GeoLite2-City.mmdb`
  - `GeoLite2-Country.mmdb`
  - `cloudflare_v4_realip.conf`
  - `cloudflare_v6_realip.conf`
  - `cloudflared_realip.conf`（本機/隧道 IP）

### 4. GoAccess

- 編譯來源：`$BUILD_DIR/goaccess`
- 安裝後（預設路徑，供你之後用）：
  - `/usr/local/bin/goaccess`
  - `/usr/local/etc/goaccess/goaccess.conf`（預設設定）
  - 語系檔隨 `make install` 一起裝（通常在 `/usr/local/share/` 之類）

如果你要，我可以再幫你做一個「目錄一覽 echo 區塊」，在 A 做完時把這些重點路徑都 print 出來給你確認。

重構時可考慮的模組切分建議（純架構，無 code）
若之後你要 refactor，從架構角度可以拆成幾個「功能模組」：

[A] 互動與參數處理
[B] 環境清理與舊 Nginx 停止
[C] Source & 依賴準備
[D] Nginx 編譯與安裝
[E] GeoIP2 / Cloudflare real_ip 初始化
[F] update_geoip2 安裝與排程
[G] UFW 安裝與基線 & CF only policy
[H] 執行帳號與權限/目錄修正
[I] 首次啟動與驗證/保護機制（含 apt hold）
