#!/usr/bin/env bash#
# ===============================================
# 編譯 25-nginxwebui-install.sh
# 版本：v1.5（整合 UFW 基線；update 腳本可選同步 UFW）
# 說明：安裝 nginxWebUI + SQLite
# 日期：2025-10-03
# ===============================================
set -euo pipefail

# === 基本參數（可用環境變數覆寫）===
INSTALL_DIR="${INSTALL_DIR:-/home/nginxWebUI}"
SERVICE_NAME="${SERVICE_NAME:-nginxwebui}"
PORT="${PORT:-8080}"
LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"

echo "[1/4] 安裝必要工具"
sudo apt-get update -y
sudo apt-get install -y wget unzip curl gnupg ca-certificates

echo "[2/4] 安裝 Java（優先 OpenJDK 11；無則 Temurin 11；再不行用 OpenJDK 17 備案）"
if ! command -v java >/dev/null 2>&1; then
  if apt-cache show openjdk-11-jdk >/dev/null 2>&1; then
    sudo apt-get install -y openjdk-11-jdk
  else
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
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

echo "[3/4] 下載並部署 nginxWebUI"
sudo mkdir -p "$INSTALL_DIR"
sudo chown root:root "$INSTALL_DIR"
sudo chmod 755 "$INSTALL_DIR"

echo "  取得最新版版本號..."
LATEST_VERSION="$(curl -fsSL https://gitee.com/cym1102/nginxWebUI/releases \
  | grep -oP 'releases/download/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr | head -n 1)"
if [ -z "${LATEST_VERSION:-}" ]; then
  echo "!! 取不到最新版本號，請檢查網路/鏡像"; exit 1
fi
echo "  最新版：v$LATEST_VERSION"

JAR_URL="https://gitee.com/cym1102/nginxWebUI/releases/download/${LATEST_VERSION}/nginxWebUI-${LATEST_VERSION}.jar"
JAR_PATH="$INSTALL_DIR/nginxWebUI.jar"
wget -O "$JAR_PATH" "$JAR_URL"

echo "[4/4] 建立 systemd 服務：$SERVICE_NAME"
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=NginxWebUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${JDK_PATH} -jar -Dfile.encoding=UTF-8 ${JAR_PATH} --server.port=${PORT} --project.home=${INSTALL_DIR}
Restart=always
RestartSec=3
LimitNOFILE=65535
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}.service"

# 可選：若已啟用 UFW，確保 LAN 可存取 WebUI 介面
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow from "${LAN_CIDR}" to any port "${PORT}" proto tcp comment 'nginxWebUI from LAN' || true
fi

echo
echo "✅ nginxWebUI 已啟動： http://<這台IP>:${PORT}"
echo "👉 首次登入後到【設定】填入："
echo "   • Nginx 可執行檔：/usr/sbin/nginx"
echo "   • 主配置檔：      /etc/nginx/nginx.conf"
echo "   （這樣就能控制你剛編譯的同一個 Nginx 實例）"
