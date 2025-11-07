# Vaultwarden 使用 MariaDB (MySQL) 後端配置指南

## 一、環境準備與基本設定

### 1.1 使用 MariaDB 客戶端庫的注意事項

- 雖然 MySQL 功能正常，但 Debian 系統預設使用 MariaDB 客戶端庫
- 若需使用 MySQL，請自行安裝對應的客戶端工具
- 建議參考 [官方頁面](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-MariaDB-\(MySQL\)-Backend) 确認兼容性

### 1.2 連接字符串語法

```systemd
DATABASE_URL=mysql://[[user]:[password]@]host[:port][/database]
```

- 若密碼含特殊字符，需使用百分號編碼（例如 `#` → `%23`）
-
- 常見特殊字符對應表：  | 特殊字符 | 百分號編碼 |
  | -------- | ---------- |
  | !        | %21        |
  | #        | %23        |
  | $        | %24        |
  | %        | %25        |
  | &        | %26        |
  | '        | %27        |
  | (        | %28        |
  | )        | %29        |
  | *        | %2A        |
  | +        | %2B        |
  | ,        | %2C        |
  | :        | %3A        |
  | ;        | %3B        |
  | =        | %3D        |
  | ?        | %3F        |
  | @        | %40        |
  | [        | %5B        |
  | ]        | %5D        |

> 有關完整編碼對照表，可參閱 [Wikipedia 百分號編碼頁](https://zh.wikipedia.org/wiki/%E7%99%BE%E5%88%86%E5%88%A5%E7%BC%96%E7%A0%81)

---

## 二、Docker 部署範例

### 2.1 單獨啟動 MySQL 容器

```shell
docker run --name mysql --net <some-docker-network> \
  -e MYSQL_ROOT_PASSWORD=<my-secret-pw> \
  -e MYSQL_DATABASE=vaultwarden \
  -e MYSQL_USER=<vaultwarden_user> \
  -e MYSQL_PASSWORD=<vaultwarden_pw> -d mysql:5.7
```

- `MYSQL_ROOT_PASSWORD`：MySQL 根帳號密碼
- `MYSQL_DATABASE`：建立 Vaultwarden 使用的資料庫
- `MYSQL_USER` 和 `MYSQL_PASSWORD`：指定 Vaultwarden 的資料庫帳號密碼

### 2.2 啟動 Vaultwarden 容器

```shell
docker run -d --name vaultwarden --net <some-docker-network> \
  -v $(pwd)/vw-data/:/data/ -v <Path to ssl certs>:/ssl/ \
  -p 443:80 \
  -e ROCKET_TLS='{certs="/ssl/<your ssl cert>",key="/ssl/<your ssl key>"}' \
  -e RUST_BACKTRACE=1 \
  -e DATABASE_URL='mysql://<vaultwarden_user>:<vaultwarden_pw>@mysql/vaultwarden' \
  -e ADMIN_TOKEN=<some_random_token> \
  <you vaultwarden image name>
```

- `ROCKET_TLS`：設定 TLS 證書路徑（需提前準備 SSL 檔案）
- `ADMIN_TOKEN`：需依 [官方說明](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page) 產生隨機 token
- `ENABLE_DB_WAL`：若需啟用 WAL（Write-Ahead Logging）功能，設為 `true`

### 2.3 Docker Compose 部署示例

```yaml
version: '3.8'

services:
  vaultwarden-db:
    image: "mariadb" # 或 "mysql"
    container_name: "vaultwarden-db"
    restart: always
    env_file:
      - ".env"
    volumes:
      - "vaultwarden-db_vol:/var/lib/mysql"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      - MYSQL_ROOT_PASSWORD=<my-secret-pw>
      - MYSQL_PASSWORD=<vaultwarden_pw>
      - MYSQL_DATABASE=vaultwarden_db
      - MYSQL_USER=<vaultwarden_user>
    healthcheck:
      test: mariadb-admin ping -h 127.0.0.1 -u $$MYSQL_USER --password=$$MYSQL_PASSWORD
      start_period: 5s
      interval: 5s
      timeout: 5s
      retries: 55

  vaultwarden:
    image: "vaultwarden/server-mysql:latest"
    container_name: "vaultwarden"
    hostname: "vaultwarden"
    depends_on:
      vaultwarden-db:
        condition: service_healthy
    restart: always
    env_file:
      - ".env"
    volumes:
      - "vaultwarden_vol:/data/"
    environment:
      - DATABASE_URL=mysql://<vaultwarden_user>:${VAULTWARDEN_MYSQL_PASSWORD}@vaultwarden-db/vaultwarden
      - ADMIN_TOKEN=<some_random_token>
      - RUST_BACKTRACE=1
    ports:
      - "80:80"
```

> 注意：`.env` 檔案需包含環境變數設定，例如 `VAULTWARDEN_MYSQL_PASSWORD`

---

## 三、手動建立資料庫步驟

### 3.1 建立資料庫

```sql
CREATE DATABASE vaultwarden CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

- `utf8mb4`：支援完整的 Unicode 字元（包括 Emoji）
- `utf8mb4_unicode_ci`：建議使用 Unicode 排序規則以避免字符編碼問題

### 3.2 建立資料庫使用者

```sql
CREATE USER 'vaultwarden'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON `vaultwarden`.* TO 'vaultwarden'@'localhost';
FLUSH PRIVILEGES;
```

- 若需限制權限，可改用：

  ```sql
  GRANT ALTER, CREATE, DELETE, DROP, INDEX, INSERT, REFERENCES, SELECT, UPDATE ON `vaultwarden`.* TO 'vaultwarden'@'localhost';
  FLUSH PRIVILEGES;
  ```

- 建議使用 `FLUSH PRIVILEGES;` 確認權限立即生效

### 3.3 驗證設定

執行以下查詢確認資料庫和表的字符集：

```sql
SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = "vaultwarden";
SELECT CHARACTER_SET_NAME, COLLATION_NAME FROM information_schema.`COLUMNS` WHERE TABLE_SCHEMA = "vaultwarden" AND CHARACTER_SET_NAME IS NOT NULL;
```

- 正確結果應為 `utf8mb4` 和 `utf8mb4_unicode_ci`

---

## 四、SQLite 到 MySQL 的遷移步驟

### 4.1 前置條件

- 需備份現有資料（SQLite 的 `db.sqlite`）
- 确認已安裝 `sqlite3` 命令列工具

### 4.2 轉換資料庫格式

1. **轉儲 SQLite 資料**

   ```bash
   sqlite3 db.sqlite3 .dump | grep "^INSERT INTO" | grep -v "__diesel_schema_migrations" > sqlitedump.sql
   echo "SET FOREIGN_KEY_CHECKS=0;" > mysqldump.sql
   cat sqlitedump.sql >> mysqldump.sql
   ```

   - `SET FOREIGN_KEY_CHECKS=0`：暫時禁用外鍵檢查以避免遷移錯誤
   - 若需修正語法錯誤，可執行：

     ```bash
     sed -i s#\"#\"#g mysqldump.sql
     ```

2. **載入 MySQL 資料**

   ```bash
   mysql --force --password --user=vaultwarden --database=vaultwarden < mysqldump.sql
   ```

   - 若出現 `Column count doesn't match value count` 錯誤，說明資料庫結構已更新，需先升級至最新版本再執行遷移
3. **重新啟動 Vaultwarden**

   - 遷移後需重新啟動服務以應用新設定

---

## 五、常見錯誤與解決方案

### 5.1 外鍵約束錯誤

- **錯誤訊息**：`Cannot add or update a child row: a foreign key constraint fails`
- **解決方法**：
  1. 暫時禁用外鍵檢查：

     ```sql
     SET foreign_key_checks=0;
     ```

  2. 執行所有表的字符集轉換（見 3.3 節）
  3. 重新啟用外鍵檢查：

     ```sql
     SET foreign_key_checks=1;
     ```

### 5.2 字元集不匹配問題

- **錯誤訊息**：`Data truncated for column 'created_at'` 或 `Row size too large`
- **解決方法**：
  1. 确認所有表的字符集為 `utf8mb4`：

     ```sql
     ALTER DATABASE `vaultwarden` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
     ```

  2. 轉換所有表的字符集：

     ```sql
     SET foreign_key_checks=0;
     ALTER TABLE `users` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
     -- 執行所有表的轉換語句（需根據實際表名調整）
     SET foreign_key_checks=1;
     ```

  3. 驗證轉換結果：

     ```sql
     SHOW CREATE TABLE `users`;
     SHOW CREATE DATABASE `vaultwarden`;
     ```

     - 預期輸出應包含 `CHARSET=utf8mb4` 和 `COLLATE=utf8mb4_unicode_ci`

---

## 六、其他相關資訊

### 6.1 資料庫連接字符串格式

- 基本格式：`mysql://<user>:<password>@<host>:<port>/<database>`
- 進階設定：
  - `ssl_mode=disabled|required|preferred`：控制 SSL 連接行為
  - `ssl_ca=/path/to/ca.crt`：指定 CA 檔案路徑（若需 SSL 驗證）

### 6.2 二進制構建說明

- 可參考 [官方構建指南](https://rs.ppgg.in/deployment/building-binary#mysql-backend) 自行編譯啟用 MySQL 的 Vaultwarden 二進制檔

---

## 參考連結

1. [Vaultwarden MariaDB/MySQL 後端設定](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-MariaDB-\(MySQL\)-Backend)
2. [百分號編碼標準](https://zh.wikipedia.org/wiki/%E7%99%BE%E5%88%86%E5%88%A5%E7%BC%96%E7%A0%81)
