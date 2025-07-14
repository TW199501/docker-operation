#!/bin/bash
#!/bin/bash

# ========== 基本設定 ==========
export CF_Token="你的_cloudflare_api_token"
DOMAIN="xiong-da.com"
CERT_DIR="/home/nginxWebUI/cert"
RELOAD_CMD="systemctl reload nginx"

# ========== 安裝 acme.sh（若未安裝） ==========
if ! command -v acme.sh >/dev/null 2>&1; then
  echo "[INFO] acme.sh 未安裝，開始安裝..."
  curl https://get.acme.sh | sh

  # 判斷是 root 還是普通用戶
  if [ "$USER" = "root" ]; then
    PROFILE="/root/.bashrc"
  else
    PROFILE="$HOME/.bashrc"
  fi

  # 寫入 PATH（避免重複）
  if ! grep -q 'acme.sh' "$PROFILE"; then
    echo 'export PATH="$HOME/.acme.sh:$PATH"' >> "$PROFILE"
    echo "[INFO] 已自動將 acme.sh 路徑加入 $PROFILE"
  else
    echo "[INFO] $PROFILE 已經有 acme.sh 路徑，無需再加"
  fi
fi


# ========== 確保 acme.sh 最新 ==========
$ACME --upgrade

# ========== 正式申請萬用域名憑證 ==========
$ACME --set-default-ca --server letsencrypt

$ACME --issue --dns dns_cf \
  -d "*.${DOMAIN}" -d "${DOMAIN}" --force

if [ $? -ne 0 ]; then
  echo "[ERROR] 憑證申請/續期失敗！"
  exit 1
fi

# ========== 安裝/複製憑證到 Nginx 目錄 ==========
$ACME --install-cert -d "*.${DOMAIN}" \
  --key-file       "${CERT_DIR}/wildcard.${DOMAIN}.key" \
  --fullchain-file "${CERT_DIR}/wildcard.${DOMAIN}.crt" \
  --reloadcmd      "${RELOAD_CMD}"

if [ $? -eq 0 ]; then
  echo "[OK] 憑證已安裝："
  echo "    私鑰      : ${CERT_DIR}/wildcard.${DOMAIN}.key"
  echo "    公鑰鏈憑證: ${CERT_DIR}/wildcard.${DOMAIN}.crt"
else
  echo "[ERROR] 憑證安裝失敗"
  exit 2
fi

exit 0
