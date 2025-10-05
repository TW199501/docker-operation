```
mkdir -p ./config/mysql/docker-entrypoint-initdb.d

cat > ./config/mysql/docker-entrypoint-initdb.d/01-onlyoffice.sql <<'SQL'
-- ONLYOFFICE 專用資料庫
CREATE DATABASE IF NOT EXISTS onlyoffice
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

-- 應用帳號（僅用於 ONLYOFFICE，不含郵件模組）
-- 請把密碼改成你自己的強密碼
CREATE USER IF NOT EXISTS 'onlyoffice'@'%'
  IDENTIFIED WITH mysql_native_password BY 'onlyoffice';

-- 最小權限：只授權 onlyoffice 這個 DB
GRANT ALL PRIVILEGES ON onlyoffice.* TO 'onlyoffice'@'%';

FLUSH PRIVILEGES;
SQL

```
