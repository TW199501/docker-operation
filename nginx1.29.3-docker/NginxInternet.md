# Nginx 網路教學

## 1. 先釐清幾個核心觀念

### 1.1 `ports` 跟 `networks` 分工

- `ports`：**宿主機 ⇄ 容器**
  - 例：`"80:80"` 是「宿主機 80 → 容器 80」。
- `networks`：**容器 ⇄ 容器**
  - 同一個 network 裡的容器，可以用 `http://服務名:port` 互相連。

兩者是不同層級：

- 外面的人（含別的 VM） → 看 `ports`。
- 同一台機器上不同容器互連 → 看 `networks`。

---

## 2. 幾個常見 Docker 網路設定比較表

### 2.1 Compose `networks` + `internal` / `external` / default

| 類型                              | 關鍵設定                                                                               | 誰可以跟誰連                                                                                                                                                | 典型用法                                             | 注意事項                                                                   |
| --------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------- |
| **預設 default 網路**       | 不寫 `networks`，Compose 自己建一個 `<project>_default`                            | 同一個[docker-compose.yml](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/docker-compose.yml:0:0-0:0) 裡的 service 互相可用 `http://服務名:port` | 單一專案內部的服務互連                               | 不同 compose 專案彼此看不到                                                |
| **自訂 bridge 網路**        | `networks: ...`，不加 `internal` / `external`                                    | 連到同一個自訂網路的容器互通                                                                                                                                | 想清楚分組（例如 `frontend-net`, `backend-net`） | 跟 default 類似，只是你自己命名                                            |
| **`internal: true` 網路** | ``yaml networks: my-net: internal: true``                                              | 只有這個 network 裡的容器彼此互通；**不能直接對外上網**                                                                                               | 嚴格隔離的「內部區」，例如 backend-only              | 在這個網路上的容器跑 `curl` 出去會失敗（除非再掛一個非 internal 的網路） |
| **`external: true` 網路** | ``yaml networks: my-net: external: true``（網路要先 `docker network create my-net`） | 只要連到這個 external network 的*任何* compose 專案，都可以互通                                                                                           | 多個不同 compose / 專案要互相連線時                  | 只是「重用既有網路」，不會限制是否能上網                                   |

### 2.2 `host.docker.internal`

| 名稱                     | 用在哪裡 | 功能                                    |
| ------------------------ | -------- | --------------------------------------- |
| `host.docker.internal` | 容器裡   | 讓容器可以用固定 DNS 名稱連到「宿主機」 |

例：
你在容器裡：

```bash
curl http://host.docker.internal:8080
```

→ 打的是「宿主機 8080 port」，不是其他容器。

---

## 3. 你現在 [docker-compose.yml](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/docker-compose.yml:0:0-0:0) 的網路設計

你目前的 [docker-compose.yml](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/docker-compose.yml:0:0-0:0) 大致是這樣（略）：

```yaml
services:
  elf-nginx:
    image: tw199501/elf-nginx:1.29.3
    ...
    networks:
      - elf-internal

  haproxy:
    image: haproxy:trixie
    ...
    networks:
      - elf-internal

networks:
  elf-internal:
    internal: true
```

**效果：**

- `elf-nginx` 和 `haproxy` 兩個容器在 `elf-internal` 這個網路裡，可以互相用 `http://elf-nginx:80` 連線。
- 因為有 `ports: "80:80"`, `"443:443"` 在 haproxy 上：
  - 外面的人（含 nginxWebUI、其他 VM）是打 **宿主機 IP:80/443** → haproxy → elf-nginx。
- 因為 `internal: true`：
  - `elf-nginx` / `haproxy` 這兩個容器 **不能直接上網**。
  - 對你現在的 `update_geoip.sh` 很關鍵：這支腳本要 `curl github / cloudflare`，
    如果它跑在只有 internal 的網路上，會 ping 不出去。

你剛剛已經測過 `update_geoip.sh` 可以跑，代表現在環境應該仍有對外路徑
（例如還掛著預設 network 或目前 Docker Engine 行為允許 outgoing）。
但設計上，要記得：**internal: true 是預期要把外網封掉的**。

---

## 4. `host.docker.internal` 的實際案例

### 案例 A：容器打回宿主機上的 nginxWebUI

- 宿主機（Windows / Linux）IP：`192.168.25.10`
- 上面跑一個 nginxWebUI，在宿主機的 8080 port：

  ```text
  http://192.168.25.10:8080
  ```

- 你的 `haproxy` 容器想把某個 backend 指到這個 nginxWebUI，就可以在 [haproxy.cfg](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/haproxy/haproxy.cfg:0:0-0:0) 這樣寫：

  ```haproxy
  backend nginx_webui
    server webui host.docker.internal:8080 check
  ```

- 這樣，容器裡不用管宿主機的實際 IP，只要用 `host.docker.internal` 就行。

---

## 5. 多個 Compose / 多個 VM 的實際場景

### 案例 B：同一台機器兩個 compose 專案互連（共用 external network）

- **VM1（IP 192.168.25.10）** 上有兩個專案：

  1. `nginx1.29.3-docker`（你現在這個）
  2. `app-backend`（另一個 compose，跑 API）
- 想要讓 `elf-nginx` 可以用 `http://app-backend:9000` 連到後端 API，就可以這樣做：

#### 步驟 1：在宿主機先建立共用網路

```bash
docker network create elf-net
```

#### 步驟 2：每個 compose 都宣告使用這個 external network

[nginx1.29.3-docker/docker-compose.yml](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/docker-compose.yml:0:0-0:0)：

```yaml
services:
  elf-nginx:
    ...
    networks:
      - elf-net
  haproxy:
    ...
    networks:
      - elf-net

networks:
  elf-net:
    external: true
```

`app-backend/docker-compose.yml`：

```yaml
services:
  app-backend:
    image: my-api:latest
    ports:
      - "9000:9000"
    networks:
      - elf-net

networks:
  elf-net:
    external: true
```

**結果：**

- 兩個專案都是連到同一個 `elf-net`。
- `elf-nginx` 容器裡可以用 `http://app-backend:9000` 連到後端。
- 外部使用者一樣打 `VM1:80/443` → haproxy → elf-nginx → app-backend。

### 案例 C：兩台 VM，各自跑 Docker

- **VM1**：`192.168.25.10`，跑 `elf-nginx + haproxy`
- **VM2**：`192.168.25.11`，跑某個後端服務 `app-api`，port 9000

這種「跨 VM」的情況，Docker 的 network 只能內部用，**跨機就回到正常 IP/路由概念**：

- 在 VM1 的 haproxy 設定：

  ```haproxy
  backend app_api_remote
    server api1 192.168.25.11:9000 check
  ```

- 或在 VM1 的 `elf-nginx`：

  ```nginx
  upstream app_api {
      server 192.168.25.11:9000;
  }
  ```

這裡用的是 **實體 IP 192.168.25.11**，不會透過 Docker network 直接「跨 host」。

---

## 6. 回到你這個專案，建議怎麼用

### 6.1 目前 [docker-compose.yml](cci:7://file:///d:/app/docker-operation/nginx1.29.3-docker/docker-compose.yml:0:0-0:0)（給別人用）

```yaml
services:
  elf-nginx:
    image: tw199501/elf-nginx:1.29.3
    ...
    networks:
      - elf-internal

  haproxy:
    image: haproxy:trixie
    ...
    networks:
      - elf-internal

networks:
  elf-internal:
    internal: true
```

- 這樣對外只開 haproxy 的 `ports 80/443`。
- `elf-nginx` 完全不對外，安全性很好。
- 如果 `update_geoip.sh` 需要穩定對外下載，建議：
  - 給 `elf-nginx` 再掛一個非 internal 的 network（例如 `default`）
  - 或像你說的，直接交給宿主機排程（你後來測試也 OK）。

### 6.2 給別的 compose / VM 用的做法

- **同一台機器、不同 compose 專案互連** → 用 external network（如 `elf-net`）。
- **容器打宿主機服務** → 用 `host.docker.internal:port`。
- **兩台 VM** → 用實體 IP（如 `192.168.25.10` / `192.168.25.11`），不靠 Docker network 過隧道。

---

### 總結（給你快速記）

- `ports`：外面進來。
- `networks`：容器之間。
- `internal: true`：只給容器互連，不給外網。
- `external: true`：讓多個 compose 專案共用同一個網路。
- `host.docker.internal`：容器打宿主機。

如果你接下來告訴我「nginxWebUI 會跑在宿主機 / 另一個 compose / 另一台 VM 哪一種」，我可以直接幫你畫一個**專屬拓樸 + network / IP 寫法**給你抄。

我先把「設計方案B架構」這個 TODO 標成完成，然後用極短文字說明架構與路徑，先不改任何 compose 檔，等你下一步指示再動。

# 方案B 共用架構設計（已完成「設計」這一步）

- **設定目錄共用**

  - 宿主：`/opt/nginx-stack/nginx`
  - `elf-nginx`：掛載成 `/etc/nginx`
  - `nginx-ui`：同樣掛載成 `/etc/nginx`（`NGINX_UI_NGINX_CONFIG_DIR=/etc/nginx` 不變）
- **UI 自己的資料**

  - 宿主：`/opt/nginx-stack/nginx-ui`
  - `nginx-ui`：掛載成 `/etc/nginx-ui`
- **流量路徑**

  - 使用者 → `haproxy`（host 80/443）→ `elf-nginx:80`
  - `nginx-ui` 只跑管理介面：`http://<host>:8080` / `https://<host>:8443`
    不直接吃正式 80/443 流量，只改 `/opt/nginx-stack/nginx` 裡的設定檔供 `elf-nginx` 使用。

如果你同意這個架構，下一步我再幫你「修改兩個 compose 的 volumes」。
