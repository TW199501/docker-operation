#!/bin/bash

set -euo pipefail

INSTALL_DIR="/home/nginxWebUI"
SERVICE_NAME="nginxWebUI"
PORT=8080
JAR_NAME="nginxWebUI.jar"
JAR_PATH="$INSTALL_DIR/$JAR_NAME"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
JDK_PATH="/usr/bin/java"

# 存檔：install_java.sh；執行：sudo bash install_java.sh
#!/usr/bin/env bash
set -euo pipefail

echo "[1/3] 安裝常用工具"
sudo apt-get update
sudo apt-get install -y wget unzip curl gnupg

echo "[2/3] 嘗試安裝 openjdk-11-jdk（官方庫）"
if apt-cache show openjdk-11-jdk >/dev/null 2>&1; then
  sudo apt-get install -y openjdk-11-jdk
else
  echo "[2b] 官方庫沒有 11，用 Adoptium（Temurin 11）"
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null

  . /etc/os-release
  CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

  echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null

  sudo apt-get update
  if ! sudo apt-get install -y temurin-11-jdk; then
    echo "[2c] Temurin 11 失敗，改裝 OpenJDK 17 作為備案"
    sudo apt-get install -y openjdk-17-jdk
  fi
fi

echo "[3/3] 驗證 Java"
JAVA_BIN="$(command -v java)"
echo "java 路徑：$JAVA_BIN"
"$JAVA_BIN" -version
  
echo "建立資料夾 $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

echo "🌐 抓取最新版 nginxWebUI 版本號..."
LATEST_VERSION=$(curl -s https://gitee.com/cym1102/nginxWebUI/releases | grep -oP 'releases/download/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr | head -n 1)

if [ -z "$LATEST_VERSION" ]; then
  echo "無法取得最新版號，請檢查網路"
  exit 1
fi

echo "最新版為 v$LATEST_VERSION，下載中..."
JAR_URL="https://gitee.com/cym1102/nginxWebUI/releases/download/${LATEST_VERSION}/nginxWebUI-${LATEST_VERSION}.jar"
wget -O "$JAR_PATH" "$JAR_URL"

echo "建立 systemd 服務：$SERVICE_NAME"
sudo tee "$SYSTEMD_FILE" >/dev/null <<EOF
[Unit]
Description=NginxWebUI
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$JDK_PATH -jar -Dfile.encoding=UTF-8 $JAR_PATH --server.port=$PORT --project.home=$INSTALL_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "重新載入 systemd 並啟用 $SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME
