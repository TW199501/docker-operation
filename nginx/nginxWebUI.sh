#!/bin/bash

set -e

INSTALL_DIR="/home/nginxWebUI"
SERVICE_NAME="nginxWebUI"
PORT=8080
JAR_NAME="nginxWebUI.jar"
JAR_PATH="$INSTALL_DIR/$JAR_NAME"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
JDK_PATH="/usr/bin/java"

echo "安裝 OpenJDK 11..."
sudo apt update
sudo apt install -y openjdk-11-jdk wget unzip curl

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
