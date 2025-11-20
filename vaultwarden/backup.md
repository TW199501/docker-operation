# 目的

在 Docker 裝好 MySQL 8，建立：

* `MYSQL_DATABASE=vaultwarden_db`
* `MYSQL_USER=vaultwarden`
* `MYSQL_PASSWORD=mypassword`
  並限制僅允許區網 `192.168.25.0/24` 主機以 `vaultwarden` 登入。

# 事前準備

1. 選一台要跑 MySQL 的主機 IP（例：`192.168.25.3`，自行替換）。
2. 規劃資料目錄（沿用你的慣例）：`/opt/mysql_data/vaultwarden/`
3. 自訂 root 密碼：`RootPassHere!`（請換成強密碼）

# A. 一次到位：docker run 指令

```bash
# 建立資料目錄
sudo mkdir -p /opt/mysql_data/vaultwarden
sudo chown -R 999:999 /opt/mysql_data/vaultwarden || true  # MySQL 容器常用 999 UID/GID

# 啟動 MySQL 8（請替換 <HOST_IP> 與 RootPassHere!）
docker run -d \
  --name vaultwarden-mysql \
  -e MYSQL_ROOT_PASSWORD='RootPassHere!' \
  -e MYSQL_DATABASE='vaultwarden_db' \
  -e MYSQL_USER='vaultwarden' \
  -e MYSQL_PASSWORD='mypassword' \
  -v /opt/mysql_data/vaultwarden:/var/lib/mysql \
  -p 192.168.25.3:3306:3306 \
  --restart unless-stopped \
  mysql:8.0
```

說明：

* `-p 192.168.25.3:3306:3306` 只綁在該主機的 192.168.25.3 介面，避免被其他網段掃到。
* 官方 MySQL 映像預設會監聽 0.0.0.0，因此只要做了 IP 綁定與防火牆限制即可。

# B. 首次啟動後：限制使用者只允許 192.168.25.\*

官方環境變數會幫你建好 `vaultwarden@'%'`。為了安全，建議改成只允許 `192.168.25.%`：

```bash
# 1) 查看目前使用者的 host 維度
docker exec -i vaultwarden-mysql mysql -uroot -p'RootPassHere!' -e "SELECT user, host FROM mysql.user WHERE user='vaultwarden';"

# 2) 如果存在 'vaultwarden'@'%'，先移除它（避免任何來源都能連）
docker exec -i vaultwarden-mysql mysql -uroot -p'RootPassHere!' -e "DROP USER IF EXISTS 'vaultwarden'@'%'; FLUSH PRIVILEGES;"

# 3) 建立僅允許 192.168.25.* 的帳號與授權（若帳號已存在會被覆蓋設定）
docker exec -i vaultwarden-mysql mysql -uroot -p'RootPassHere!' <<'SQL'
CREATE USER IF NOT EXISTS 'vaultwarden'@'192.168.25.%' IDENTIFIED BY 'mypassword';
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'192.168.25.%';
FLUSH PRIVILEGES;
SQL
```

# C. 開放防火牆（建議）

若主機用 firewalld（Rocky/Alma/RHEL 類）：

```bash
# 僅允許 192.168.25.0/24 連到 3306/TCP
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.25.0/24" port protocol="tcp" port="3306" accept'
# 確保沒有開放 3306 給其他來源（如既有規則有開放，請刪除）
sudo firewall-cmd --reload
```

# D. 測試連線

LAN 內任一台測試：

```bash
mysql -h 192.168.25.3 -u vaultwarden -p'mypassword' -D vaultwarden_db -e "SELECT VERSION();"
```

應能看到 MySQL 版本，代表帳號限制與授權 OK。

# E. 可選：docker-compose 版本

`docker-compose.yml` 內容：

```yaml
services:
  mysql:
    image: mysql:8.0
    container_name: vaultwarden-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "RootPassHere!"   # 請改強密碼
      MYSQL_DATABASE: "vaultwarden_db"
      MYSQL_USER: "vaultwarden"
      MYSQL_PASSWORD: "mypassword"
    volumes:
      - /opt/mysql_data/vaultwarden:/var/lib/mysql
    ports:
      - "192.168.25.3:3306:3306"  # 只綁內網 IP
```

啟動：

```bash
docker compose up -d
```

啟動後，請依照「B. 首次啟動後」步驟，調整使用者的 Host 限制為 `192.168.25.%`。

# F. 可選：明確指定 bind-address

一般不必改，若你想明確宣告：

```bash
# 建立自訂設定檔（容器會自動讀取 /etc/mysql/conf.d/*.cnf）
sudo tee /opt/mysql_data/vaultwarden/bind.cnf >/dev/null <<'EOF'
[mysqld]
bind-address=0.0.0.0
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
EOF

# 重新以掛載方式啟動（docker run 範例）
docker rm -f vaultwarden-mysql

docker run -d \
  --name vaultwarden-mysql \
  -e MYSQL_ROOT_PASSWORD='RootPassHere!' \
  -e MYSQL_DATABASE='vaultwarden_db' \
  -e MYSQL_USER='vaultwarden' \
  -e MYSQL_PASSWORD='mypassword' \
  -v /opt/mysql_data/vaultwarden:/var/lib/mysql \
  -v /opt/mysql_data/vaultwarden/bind.cnf:/etc/mysql/conf.d/bind.cnf:ro \
  -p 192.168.25.3:3306:3306 \
  --restart unless-stopped \
  mysql:8.0
```

# G. Vaultwarden 連線字串

* 同主機 Docker 網路互連（假設 Vaultwarden 與 MySQL 在同一自訂網路，且 MySQL 服務名為 `mysql`）：
  * `DATABASE_URL=mysql://vaultwarden:mypassword@mysql:3306/vaultwarden_db`
* 區網其他主機連過來：
  * `DATABASE_URL=mysql://vaultwarden:mypassword@192.168.25.3:3306/vaultwarden_db`

# 小提醒

* 若你先前已設定過 `vaultwarden@'%'`，務必照 B 步驟移除，避免任何來源都能連。
* 不要把 root 密碼存在腳本或版本庫；建議改用 `.env` 或 Secret 管理。
* 若客戶端太舊導致認證外掛問題，可在自訂設定加：`default_authentication_plugin=mysql_native_password`，但一般不需要。

---

## 附錄：MariaDB 11.8（你的現況）快速指令

你目前執行的是 `mariadb:11.8` 容器。以下是針對 **MariaDB** 的最短路徑設定，達成：

* 建立 `vaultwarden_db`
* 建立 `vaultwarden` 使用者、密碼 `mypassword`
* **僅允許 192.168.25.* 連線*\*

> 註：MariaDB 官方映像同時接受 `MARIADB_*` 與 `MYSQL_*` 環境變數；建議改用 `MARIADB_*` 命名。

### 0) 找出容器名稱與目前連接埠是否有對外

```bash
docker ps --filter "ancestor=mariadb:11.8" \
  --format "table {{.ID}}	{{.Image}}	{{.Names}}	{{.Ports}}	{{.Status}}"
```

* 若 `Ports` 欄位只顯示 `3306/tcp`（沒有 `0.0.0.0:3306->3306/tcp` 或 `192.168.25.X:3306->3306/tcp`），代表 **尚未對外發布埠**，區網無法連進來。

### 1)（可選但強烈建議）確認是否有掛載資料卷

```bash
docker inspect <你的容器名> --format '{{json .Mounts}}'
```

* 若無對應的 host 目錄（例如 `/opt/mysql_data/vaultwarden`），**重建容器前請先備份**：

```bash
docker exec -i <你的容器名> mariadb-dump -uroot -p'RootPassHere!' --all-databases > /opt/mysql_data/vaultwarden/backup-$(date +%F).sql
```

### 2) 以 IP 綁定方式重新建立（或新建）容器

> 將 `192.168.25.3` 換成你要綁定的主機 IP；`RootPassHere!` 換成強密碼。

```bash
# 停用舊容器（若需要）
docker rm -f <你的容器名> 2>/dev/null || true

# 確保資料目錄存在
sudo mkdir -p /opt/mysql_data/vaultwarden
sudo chown -R 999:999 /opt/mysql_data/vaultwarden || true

# 重新建立 MariaDB 11.8
docker run -d \
  --name vaultwarden-mariadb \
  -e MARIADB_ROOT_PASSWORD='RootPassHere!' \
  -e MARIADB_DATABASE='vaultwarden_db' \
  -e MARIADB_USER='vaultwarden' \
  -e MARIADB_PASSWORD='mypassword' \
  -v /opt/mysql_data/vaultwarden:/var/lib/mysql \
  -p 192.168.25.3:3306:3306 \
  --health-cmd='healthcheck.sh --connect --innodb_initialized' \
  --restart unless-stopped \
  mariadb:11.8
```

* 以上 `-p 192.168.25.3:3306:3306` 僅綁 **內網 IP**，避免外部掃描。

### 3) 將 `vaultwarden` 使用者主機限制為 192.168.25.%

> MariaDB 容器內建 `mariadb` 用戶端，以下用這個指令。

```bash
docker exec -i vaultwarden-mariadb mariadb -uroot -p'RootPassHere!' <<'SQL'
-- 移除任何來源都能連的帳號（若存在）
DROP USER IF EXISTS 'vaultwarden'@'%';

-- 建立僅允許 192.168.25.* 的帳號
CREATE USER IF NOT EXISTS 'vaultwarden'@'192.168.25.%' IDENTIFIED BY 'mypassword';

-- 確保資料庫存在並使用 utf8mb4
CREATE DATABASE IF NOT EXISTS `vaultwarden_db`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 授權
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'192.168.25.%';
FLUSH PRIVILEGES;
SQL
```

### 4)（建議）主機防火牆僅放行 192.168.25.0/24 進 3306/TCP

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.25.0/24" port protocol="tcp" port="3306" accept'
sudo firewall-cmd --reload
```

### 5) 驗證（區網任一台）

```bash
mariadb -h 192.168.25.3 -u vaultwarden -p'mypassword' -D vaultwarden_db -e "SELECT VERSION();"
```

### 6)（可選）自訂設定檔 bind 與字元集

MariaDB 映像允許將 `*.cnf` 放到 `/etc/mysql/conf.d/`：

```bash
sudo tee /opt/mysql_data/vaultwarden/bind.cnf >/dev/null <<'EOF'
[mysqld]
bind-address=0.0.0.0
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
EOF

# 重新啟動並掛載設定檔（若尚未掛載）
docker rm -f vaultwarden-mariadb

docker run -d \
  --name vaultwarden-mariadb \
  -e MARIADB_ROOT_PASSWORD='RootPassHere!' \
  -e MARIADB_DATABASE='vaultwarden_db' \
  -e MARIADB_USER='vaultwarden' \
  -e MARIADB_PASSWORD='mypassword' \
  -v /opt/mysql_data/vaultwarden:/var/lib/mysql \
  -v /opt/mysql_data/vaultwarden/bind.cnf:/etc/mysql/conf.d/bind.cnf:ro \
  -p 192.168.25.3:3306:3306 \
  --health-cmd='healthcheck.sh --connect --innodb_initialized' \
  --restart unless-stopped \
  mariadb:11.8
```

### 7) Vaultwarden 連線字串

* 若 Vaultwarden 與 DB 在同台或同 Docker 網路（服務名 `vaultwarden-mariadb`）：
  * `DATABASE_URL=mysql://vaultwarden:mypassword@vaultwarden-mariadb:3306/vaultwarden_db`
* 區網其他主機連入：
  * `DATABASE_URL=mysql://vaultwarden:mypassword@192.168.25.3:3306/vaultwarden_db`

> 小提醒：避免在版本控管中明文保存密碼。可用 `.env` 或密碼保管。

## 針對你現有容器（ID: df6065c78648）立即生效指令

> 將 `RootPassHere!` 改成你當初設定的 root 密碼。

```bash
# 1) 將 vaultwarden 的萬用 host 刪除（若存在）
docker exec -i df6065c78648 mariadb -uroot -p'RootPassHere!' -e "DROP USER IF EXISTS 'vaultwarden'@'%'; FLUSH PRIVILEGES;"

# 2) 僅允許 192.168.25.*
docker exec -i df6065c78648 mariadb -uroot -p'RootPassHere!' <<'SQL'
CREATE USER IF NOT EXISTS 'vaultwarden'@'192.168.25.%' IDENTIFIED BY 'mypassword';
CREATE DATABASE IF NOT EXISTS `vaultwarden_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'192.168.25.%';
FLUSH PRIVILEGES;
SQL

# 3) 若外部還是連不到，代表當初沒對外映射 3306，需重建：
#    先備份、確認掛載，然後用 -p 192.168.25.3:3306:3306 重新 run（畫布上方已有完整範例）。
```

## docker-compose 範本（已套用 192.168.25.3 與雙網段授權）

此版本達成三件事：

1. 對外只在 192.168.25.3:3306 開放資料庫給區網主機。
2. Vaultwarden 服務可透過 Docker 內部網路連線（來源會是 172.\* 網段）。
3. 使用初始化 SQL 將使用者限定為 192.168.25.% 與 172.% 兩個授權，並移除萬用 %。

docker-compose.yml：

```yaml
services:
  vaultwarden-db:
    image: mariadb:11.8
    container_name: vaultwarden-db
    restart: always
    env_file:
      - .env
    volumes:
      - ./vaultwarden-db:/var/lib/mysql
      - ./vaultwarden-db-init:/docker-entrypoint-initdb.d:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      MARIADB_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MARIADB_USER: ${MYSQL_USER}
      MARIADB_PASSWORD: ${MYSQL_PASSWORD}
      MARIADB_DATABASE: ${MYSQL_DATABASE}
    ports:
      - "192.168.25.3:3306:3306"
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -h 127.0.0.1 -u $$MYSQL_USER --password=$$MYSQL_PASSWORD"]
      start_period: 5s
      interval: 5s
      timeout: 5s
      retries: 55

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    hostname: vaultwarden
    depends_on:
      vaultwarden-db:
        condition: service_healthy
    restart: always
    env_file:
      - .env
    volumes:
      - ./vaultwarden:/data/
      - /etc/localtime:/etc/localtime:ro
    environment:
      DATABASE_URL: mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@vaultwarden-db:3306/${MYSQL_DATABASE}
      ADMIN_TOKEN: ${ADMIN_TOKEN}
      RUST_BACKTRACE: 1
    ports:
      - "80:80"

volumes:
  vaultwarden:
  vaultwarden-db:
```

`.env` 範例：

```env
MYSQL_ROOT_PASSWORD=RootPassHere!
MYSQL_USER=vaultwarden
MYSQL_PASSWORD=mypassword
MYSQL_DATABASE=vaultwarden_db
ADMIN_TOKEN=請改為隨機長權杖
```

初始化 SQL（路徑 `./vaultwarden-db-init/01-grants.sql`，首度建立資料目錄時自動套用）：

```sql
DROP USER IF EXISTS 'vaultwarden'@'%';
CREATE USER IF NOT EXISTS 'vaultwarden'@'192.168.25.%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'192.168.25.%';
CREATE USER IF NOT EXISTS 'vaultwarden'@'172.%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'172.%';
FLUSH PRIVILEGES;
```

首次部署步驟：

1. 建立資料夾 `mkdir -p ./vaultwarden-db ./vaultwarden-db-init ./vaultwarden`。
2. 將上面 SQL 存成 `./vaultwarden-db-init/01-grants.sql`。
3. 準備 `.env`，替換為你的密碼與權杖。
4. 執行 `docker compose up -d`。

若已有舊資料（`./vaultwarden-db` 不為空），初始化 SQL 不會自動執行，請改用一次性調整：

```bash
docker compose exec -T vaultwarden-db mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" <<'SQL'
DROP USER IF EXISTS 'vaultwarden'@'%';
CREATE USER IF NOT EXISTS 'vaultwarden'@'192.168.25.%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'192.168.25.%';
CREATE USER IF NOT EXISTS 'vaultwarden'@'172.%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON `vaultwarden_db`.* TO 'vaultwarden'@'172.%';
FLUSH PRIVILEGES;
SQL
```

驗證：

```bash
mariadb -h 192.168.25.3 -u vaultwarden -p"$MYSQL_PASSWORD" -D vaultwarden_db -e "SELECT VERSION();"
```

## `.env` 範本與可直接用的示例

### 範本（自行替換為強密碼／權杖）

```env
# MariaDB 基本設定（compose 會用這些）
MYSQL_ROOT_PASSWORD=
MYSQL_USER=vaultwarden
MYSQL_PASSWORD=
MYSQL_DATABASE=vaultwarden_db

# Vaultwarden 管理員權杖（用於 /admin 登入）
ADMIN_TOKEN=
```

### 快速可用示例（先用、上線後請儘快自行更換）

```env
MYSQL_ROOT_PASSWORD=Hddv3fQ5!qM2o6ZLx1k8V@7r#cN9pB4a
MYSQL_USER=vaultwarden
MYSQL_PASSWORD=vW_gR6bJk7uQ1pT2sN9xE3aZ0mL5hC8d
MYSQL_DATABASE=vaultwarden_db
ADMIN_TOKEN=bw_admin_3vX2iQ0hL9sU7pK5mN4eJ1dR8tC6aB3Yz
```

> 提醒：
>
> 1. `.env` 檔不要進版本控管；若需要，請使用私密儲存（如 Password Manager 或 Secrets）。
> 2. 密碼含特殊字元時，compose 仍可讀取；若在 shell 直接引用，建議以引號包住避免被解讀。

## 自動備份方案（不格式化資料，僅匯出備份）

提供兩種做法，選一種即可。

### 方案 A：主機 cron + docker compose exec

1. 建立腳本 `/opt/scripts/vaultwarden_db_backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
export TZ=Asia/Taipei
STACK_DIR="/path/to/your/compose"   # 請改成你的 compose 目錄
BACKUP_DIR="/opt/backup/vaultwarden-db"
RETENTION_DAYS=14
CONTAINER="vaultwarden-db"

mkdir -p "$BACKUP_DIR"
# 載入 .env（含 MYSQL_* 變數）
set -a; . "$STACK_DIR/.env"; set +a
STAMP=$(date +%F_%H%M%S)
OUT="$BACKUP_DIR/vaultwarden_db-$STAMP.sql.zst"

# 匯出（不鎖表）+ 壓縮
/usr/bin/docker compose -f "$STACK_DIR/docker-compose.yml" exec -T "$CONTAINER" \
  mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --databases "$MYSQL_DATABASE" \
  --single-transaction --quick --routines --triggers --events \
| zstd -T0 -19 -o "$OUT"

# 驗證壓縮檔可讀
zstd -t "$OUT"
ln -sfn "$OUT" "$BACKUP_DIR/latest.sql.zst"

# 依保存天數自動清理
find "$BACKUP_DIR" -type f -name '*.sql.zst' -mtime +"$RETENTION_DAYS" -delete
```

2. 加入 cron（每日 03:15）

```bash
echo "15 3 * * * /bin/bash /opt/scripts/vaultwarden_db_backup.sh >> /var/log/vw_db_backup.log 2>&1" | sudo tee /etc/cron.d/vw-db-backup >/dev/null
sudo chmod 644 /etc/cron.d/vw-db-backup && sudo systemctl restart cron || sudo systemctl restart crond
```

### 方案 B：Compose 側車備份容器（crond 內建排程）

目錄結構：

```
./
├─ docker-compose.yml
├─ .env
├─ scripts/
│  └─ db-backup.sh
└─ backups/
```

`scripts/db-backup.sh`：

```sh
#!/bin/sh
set -e
export TZ=Asia/Taipei
BACKUP_DIR=/backups
RETENTION_DAYS=${RETENTION_DAYS:-14}
STAMP=$(date +%F_%H%M%S)
OUT="$BACKUP_DIR/vaultwarden_db-$STAMP.sql.zst"

mysqldump -h vaultwarden-db -u root -p"$MYSQL_ROOT_PASSWORD" --databases "$MYSQL_DATABASE" \
  --single-transaction --quick --routines --triggers --events \
| zstd -T0 -19 > "$OUT"

zstd -t "$OUT" && ln -sfn "$OUT" "$BACKUP_DIR/latest.sql.zst"
find "$BACKUP_DIR" -type f -name '*.sql.zst' -mtime +"$RETENTION_DAYS" -delete
```

將其設為可執行：

```bash
chmod +x scripts/db-backup.sh
```

在 `docker-compose.yml` 追加服務：

```yaml
  db-backup:
    image: alpine:3.20
    container_name: vaultwarden-db-backup
    depends_on:
      vaultwarden-db:
        condition: service_healthy
    env_file:
      - .env
    environment:
      RETENTION_DAYS: 14
    volumes:
      - ./scripts/db-backup.sh:/usr/local/bin/db-backup.sh:ro
      - ./backups:/backups
      - /etc/localtime:/etc/localtime:ro
    entrypoint: ["/bin/sh","-c"]
    command: >
      apk add --no-cache mariadb-client zstd tzdata &&
      echo "15 3 * * * /usr/local/bin/db-backup.sh >> /var/log/db-backup.log 2>&1" > /etc/crontabs/root &&
      crond -f -l 8
```

重載：

```bash
docker compose up -d db-backup
```

### 復原（不會覆蓋資料夾，只將 SQL 匯入資料庫）

從最新備份恢復：

```bash
zstd -dc ./backups/latest.sql.zst | docker compose exec -T vaultwarden-db mariadb -uroot -p"$MYSQL_ROOT_PASSWORD"
```

或指定某檔案：

```bash
zstd -dc ./backups/vaultwarden_db-2025-11-11_031500.sql.zst | docker compose exec -T vaultwarden-db mariadb -uroot -p"$MYSQL_ROOT_PASSWORD"
```

驗證：

```bash
docker compose exec -T vaultwarden-db mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"
```

注意事項：

* 本流程為邏輯備份（dump），不會觸發初始化，也不會格式化資料目錄。
* 建議放到與 DB 不同的磁碟/資料池，並定期測試還原。
