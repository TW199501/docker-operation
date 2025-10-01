#!/usr/bin/env bash
# keepalived-install.sh (auto-detect iface + health-check)
# 一鍵安裝 Keepalived 2.3.4（原始碼）+ Unicast VRRP + 健康檢查
# A 節點：
#   sudo bash keepalived-install.sh \
#     --iface=auto --src-ip=192.168.25.24 --peer-ip=192.168.25.25 \
#     --vip=192.168.25.26/24 --vrid=26 --state=MASTER --priority=150
# B 節點：
#   sudo bash keepalived-install.sh \
#     --iface=auto --src-ip=192.168.25.25 --peer-ip=192.168.25.24 \
#     --vip=192.168.25.26/24 --vrid=26 --state=BACKUP --priority=100

set -euo pipefail

# ===== 可調參數 =====
VERSION="2.3.4"
ROUTER_ID="${ROUTER_ID:-VRRP01}"
IFACE="${IFACE:-auto}"          # auto = 自動偵測
SRC_IP="${SRC_IP:-192.168.25.24}"
PEER_IP="${PEER_IP:-192.168.25.25}"
VIP="${VIP:-192.168.25.26/24}"
VRID="${VRID:-26}"
STATE="${STATE:-MASTER}"        # MASTER/BACKUP
PRIORITY="${PRIORITY:-150}"
AUTH_PASS="${AUTH_PASS:-S3curePa55}"  # 會自動裁成 8 碼

PREFIX="/usr"
SYSCONFDIR="/etc/keepalived"

# ===== 參數解析 =====
for ARG in "$@"; do
  case "$ARG" in
    --iface=*)     IFACE="${ARG#*=}";;
    --src-ip=*)    SRC_IP="${ARG#*=}";;
    --peer-ip=*)   PEER_IP="${ARG#*=}";;
    --vip=*)       VIP="${ARG#*=}";;
    --vrid=*)      VRID="${ARG#*=}";;
    --state=*)     STATE="${ARG#*=}";;
    --priority=*)  PRIORITY="${ARG#*=}";;
    --auth-pass=*) AUTH_PASS="${ARG#*=}";;
    --router-id=*) ROUTER_ID="${ARG#*=}";;
    --version=*)   VERSION="${ARG#*=}";;
    *) echo "未知參數: $ARG"; exit 2;;
  esac
done

# ===== 權限 =====
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
  command -v sudo >/dev/null 2>&1 || { echo "需要 root 或 sudo"; exit 1; }
  SUDO="sudo"
fi

# ===== 工具函式 =====
trim8() { printf '%s' "${1:0:8}"; }
route_dev() { ip -o route get "$1" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
default_dev() { ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
iface_exists() { ip link show "$1" >/dev/null 2>&1; }

# 自動偵測介面：peer → vip → default
detect_iface() {
  local vip_ip="${VIP%%/*}"
  local dev=""
  if [ "${IFACE}" != "auto" ]; then
    dev="$IFACE"
  else
    dev="$(route_dev "$PEER_IP")"
    [ -n "$dev" ] || dev="$(route_dev "$vip_ip")"
    [ -n "$dev" ] || dev="$(default_dev)"
  fi
  if [ -z "$dev" ] || ! iface_exists "$dev"; then
    echo "無法自動偵測網卡；請用 --iface=<介面名> 指定。可用介面："
    ip -o link show | awk -F': ' '{print " - "$2}'
    exit 1
  fi
  echo "$dev"
}

# ===== 相依 =====
echo "[1/6] 安裝編譯相依..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y
  $SUDO apt-get install -y build-essential pkg-config libssl-dev \
    libnl-3-dev libnl-genl-3-dev libnl-route-3-dev curl
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y gcc make pkgconfig openssl-devel libnl3-devel curl
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y gcc make pkgconfig openssl-devel libnl3-devel curl
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add --no-cache build-base pkgconfig openssl-dev libnl3-dev curl
else
  echo "未知套件管理器，請手動安裝：編譯工具、OpenSSL-devel、libnl3-devel、curl"; exit 1
fi

# ===== systemd unit 目錄 =====
if   [ -d /lib/systemd/system ]; then UNITDIR="/lib/systemd/system"
elif [ -d /usr/lib/systemd/system ]; then UNITDIR="/usr/lib/systemd/system"
else UNITDIR="/lib/systemd/system"; fi

# ===== 下載/編譯/安裝 Keepalived =====
echo "[2/6] 下載並編譯 Keepalived ${VERSION}..."
BUILD_DIR="/usr/local/src"
$SUDO mkdir -p "$BUILD_DIR" && $SUDO chown -R "$(id -u)":"$(id -g)" "$BUILD_DIR"
cd "$BUILD_DIR"

TARBALL="keepalived-${VERSION}.tar.gz"
URL="https://www.keepalived.org/software/${TARBALL}"
curl -fL --retry 3 -o "$TARBALL" "$URL"
tar -xzf "$TARBALL"
cd "keepalived-${VERSION}"

./configure \
  --prefix="$PREFIX" \
  --sysconfdir="$SYSCONFDIR" \
  --with-init=systemd \
  --with-systemdsystemunitdir="$UNITDIR"

make -j"$(nproc)"
$SUDO make install
$SUDO systemctl daemon-reload

# ===== 偵測介面 & 修正密碼長度 =====
IFACE="$(detect_iface)"
AUTH_PASS="$(trim8 "$AUTH_PASS")"
echo "[3/6] 使用介面：$IFACE ；auth_pass（8碼）：$AUTH_PASS"

# ===== 健康檢查腳本 =====
echo "[4/6] 建立健康檢查腳本 /etc/keepalived/check_nginx.sh ..."
$SUDO tee /etc/keepalived/check_nginx.sh >/dev/null <<'CHK'
#!/usr/bin/env bash
set -euo pipefail
pidof nginx >/dev/null 2>&1 || exit 1
# 有 /health 就用 /health，否則對首頁做 HEAD
if ! curl -fsS --max-time 1 http://127.0.0.1/health >/dev/null 2>&1; then
  curl -fsS -I --max-time 1 http://127.0.0.1/ >/dev/null 2>&1 || exit 1
fi
exit 0
CHK
$SUDO chmod +x /etc/keepalived/check_nginx.sh

# ===== 產生設定 =====
echo "[5/6] 產生 /etc/keepalived/keepalived.conf ..."
$SUDO mkdir -p "$SYSCONFDIR"
$SUDO tee "$SYSCONFDIR/keepalived.conf" >/dev/null <<EOF
global_defs {
  router_id ${ROUTER_ID}
  vrrp_skip_check_adv_addr
}

vrrp_script chk_nginx {
  script "/etc/keepalived/check_nginx.sh"
  interval 2
  timeout  2
  fall     3
  rise     2
  weight  -30
}

vrrp_instance VI_ELF_NGINX {
  state ${STATE}
  interface ${IFACE}
  virtual_router_id ${VRID}
  priority ${PRIORITY}
  advert_int 1
  preempt_delay 5
  garp_master_delay 1
  garp_master_refresh 10

  unicast_src_ip ${SRC_IP}
  unicast_peer {
    ${PEER_IP}
  }

  authentication {
    auth_type PASS
    auth_pass ${AUTH_PASS}
  }

  virtual_ipaddress {
    ${VIP} dev ${IFACE} label ${IFACE}:vip
  }

  track_script {
    chk_nginx
  }
}
EOF

# 先驗證設定
sudo keepalived -t -f "$SYSCONFDIR/keepalived.conf"

# ===== 啟用 =====
echo "[6/6] 啟用並啟動 keepalived ..."
$SUDO systemctl enable --now keepalived
$SUDO systemctl --no-pager status keepalived || true

echo
echo "完成。建議在 Nginx 加： location = /health { access_log off; return 200; }"
echo "檢查 VIP： ip addr | grep -F \"${VIP%%/*}\""
echo "切換測試： systemctl stop nginx   # 應漂移到對端"
