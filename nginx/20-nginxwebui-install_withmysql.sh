#!/usr/bin/env bash
# ================================================
# 編譯 20-nginxwebui-install_withmysql.sh
# 版本：v1.5（整合 UFW 基線；update 腳本可選同步 UFW）
# 說明：安裝 nginxWebUI + MariaDB(與25-nginxwebui-install.sh不同二選一二選一)
# 日期：2025-10-03
# ===============================================
set -euo pipefail

# 可調參數
INSTALL_DIR="${INSTALL_DIR:-/home/nginxWebUI}"
SERVICE_NAME="${SERVICE_NAME:-nginxWebUI}"
PORT="${PORT:-8080}"
JAR_NAME="${JAR_NAME:-nginxWebUI.jar}"
JAR_PATH="$INSTALL_DIR/$JAR_NAME"

LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"   # 允許連 MySQL 的內網
DB_NAME="${DB_NAME:-nginxwebui}"
DB_USER="${DB_USER:-nginxwebui}"
DB_PASS="${DB_PASS:-}"                    # 空則自動產生
DB_HOST_LOCAL="127.0.0.1"

SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/nginxwebui.env"
CREDS_NOTE="/root/nginxwebui-db.txt"

[ "$(id -u)" -eq 0 ] || { echo "請用 root 執行"; exit 1; }

echo "[1/7] 基本工具與 UFW"
apt-get update -y
apt-get install -y wget curl unzip gnupg ca-certificates lsb-release ufw

# === 你要求「不要改動」的 Java 區塊 ===
echo "[2/7] 安裝 Java（優先 11，失敗則裝 17）"
if ! command -v java >/dev/null 2>&1; then
  if apt-cache show openjdk-11-jdk >/dev/null 2>&1; then
    sudo apt-get install -y openjdk-11-jdk
  else
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null
    CODENAME=""
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      # shellcheck source=/etc/os-release
      . /etc/os-release
      CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    fi
    if [ -z "$CODENAME" ]; then
      CODENAME="$(lsb_release -cs 2>/dev/null || echo "focal")"
    fi
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb ${CODENAME} main" \
      | sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null
    sudo apt-get update -y
    if ! sudo apt-get install -y temurin-11-jdk; then
      sudo apt-get install -y openjdk-17-jdk
    fi
  fi
fi
JDK_PATH="$(command -v java)"
echo "Java 在：$JDK_PATH"
"$JDK_PATH" -version || true
# === 以上保留原樣 ===

echo "[3/7] 安裝 MariaDB（Debian/Ubuntu 自帶，最單純）"
apt-get install -y mariadb-server mariadb-client
systemctl enable --now mariadb

# 對 LAN 監聽（防火牆限制來源）
MARIADB_CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$MARIADB_CNF" ]; then
  sed -i -E 's/^\s*bind-address\s*=.*/bind-address = 0.0.0.0/' "$MARIADB_CNF" || true
  grep -q 'bind-address' "$MARIADB_CNF" || echo 'bind-address = 0.0.0.0' >> "$MARIADB_CNF"
fi
systemctl restart mariadb

# 產生密碼
if [ -z "$DB_PASS" ]; then
  DB_PASS="$(tr -dc 'A-Za-z0-9!@#$%^&*_' </dev/urandom | head -c 20)"
fi
LAN_HOST_WILDCARD="$(echo "$LAN_CIDR" | awk -F'[./]' '{printf("%d.%d.%d.%%",$1,$2,$3)}')"

echo "[3b] 建 DB 與帳號（localhost + LAN）"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'$LAN_HOST_WILDCARD' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'$LAN_HOST_WILDCARD' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$LAN_HOST_WILDCARD';
FLUSH PRIVILEGES;
SQL

echo "[3c] UFW 僅放行 ${LAN_CIDR} -> 3306"
if [ -f /etc/default/ufw ]; then
  sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw || true
fi
ufw allow proto tcp from "$LAN_CIDR" to any port 3306 comment 'mysql from LAN' || true
ufw delete allow 3306/tcp 2>/dev/null || true
if ufw status 2>/dev/null | grep -qi inactive; then ufw --force enable; fi
ufw reload

echo "[4/7] 準備安裝目錄與帳號"
id -u nginxwebui >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M -d "$INSTALL_DIR" nginxwebui
mkdir -p "$INSTALL_DIR"
chown -R nginxwebui:nginxwebui "$INSTALL_DIR"

echo "[5/7] 下載 nginxWebUI Jar"
LATEST_VERSION="$(curl -fsSL https://gitee.com/cym1102/nginxWebUI/releases \
  | grep -oP 'releases/download/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr | head -n1 || true)"
if [ -n "$LATEST_VERSION" ]; then
  JAR_URL="https://gitee.com/cym1102/nginxWebUI/releases/download/${LATEST_VERSION}/nginxWebUI-${LATEST_VERSION}.jar"
  wget -O "$JAR_PATH" "$JAR_URL"
else
  wget -O "$JAR_PATH" "https://gitee.com/cym1102/nginxWebUI/releases/download/3.3.9/nginxWebUI-3.3.9.jar"
fi
test -s "$JAR_PATH" || { echo "!! 下載 Jar 失敗"; exit 1; }
chown nginxwebui:nginxwebui "$JAR_PATH"

echo "[6/7] 寫環境檔 + 輸出密碼筆記"
cat > "$ENV_FILE" <<EOF
SERVER_PORT=$PORT
PROJECT_HOME=$INSTALL_DIR
SPRING_DATABASE_TYPE=mysql
SPRING_DATASOURCE_URL=jdbc:mysql://$DB_HOST_LOCAL:3306/$DB_NAME?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC&useSSL=false&allowPublicKeyRetrieval=true
SPRING_DATASOURCE_USERNAME=$DB_USER
SPRING_DATASOURCE_PASSWORD=$DB_PASS
EOF
chmod 640 "$ENV_FILE"; chown root:nginxwebui "$ENV_FILE"

cat > "$CREDS_NOTE" <<NOTE
[nginxWebUI DB]
DB_HOST(local)= $DB_HOST_LOCAL
DB_NAME       = $DB_NAME
DB_USER       = $DB_USER
DB_PASS       = $DB_PASS

[LAN access]
LAN_CIDR      = $LAN_CIDR
Connect URL   = jdbc:mysql://<這台LAN IP>:3306/$DB_NAME?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC&useSSL=false&allowPublicKeyRetrieval=true
NOTE
chmod 600 "$CREDS_NOTE"

echo "[7/7] 建立 systemd 服務"
cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=NginxWebUI
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
User=nginxwebui
Group=nginxwebui
EnvironmentFile=$ENV_FILE
WorkingDirectory=$INSTALL_DIR
ExecStart=$JDK_PATH -jar -Dfile.encoding=UTF-8 $JAR_PATH \
  --server.port=\${SERVER_PORT} \
  --project.home=\${PROJECT_HOME} \
  --spring.database.type=\${SPRING_DATABASE_TYPE} \
  --spring.datasource.url=\${SPRING_DATASOURCE_URL} \
  --spring.datasource.username=\${SPRING_DATASOURCE_USERNAME} \
  --spring.datasource.password=\${SPRING_DATASOURCE_PASSWORD}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo
echo "✅ 完成"
echo "  - Web： http://<這台IP>:$PORT"
echo "  - 服務： systemctl status $SERVICE_NAME"
echo "  - DB 憑證： $CREDS_NOTE"
echo "  - 若要讓內網主機連 DB：請用這台的 LAN IP + 3306（UFW 已只放行 $LAN_CIDR）"
