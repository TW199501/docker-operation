#!/usr/bin/env bash
# keepalived-install.sh - 互動式安裝 Keepalived 2.3.4（Unicast VRRP + 健檢 + 自動網卡/角色）
# 在兩台新機上都執行，按提示輸入：
# 1) 主節點 IP（A）  2) 子節點 IP（B）  3) VIP(含CIDR, 例: 192.168.25.26/24)

set -euo pipefail

VERSION="2.3.4"
PREFIX="/usr"
SYSCONFDIR="/etc/keepalived"

# ---------- 小工具 ----------
trim8() { printf '%s' "${1:0:8}"; }
to_int() { local IFS=.; read -r a b c d <<<"$1"; echo $(( (a<<24)+(b<<16)+(c<<8)+d )); }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
iface_of_ip() { ip -o -4 addr show | awk -v ip="$1" '$4 ~ ip"/" {print $2; exit}'; }
route_dev() { ip -o route get "$1" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
default_dev() { ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
ip_only() { echo "${1%%/*}"; }
valid_ip() {
  local ip="$1"; local IFS=.; read -r a b c d <<<"$ip" || return 1
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] || return 1
  ((a<=255 && b<=255 && c<=255 && d<=255)) || return 1; return 0
}
valid_cidr() {
  local s="$1"; local ip="${s%%/*}"; local m="${s##*/}"
  valid_ip "$ip" && [[ "$m" =~ ^[0-9]+$ ]] && (( m>=0 && m<=32 ))
}

# ---------- 權限 ----------
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
  have_cmd sudo || { echo "需要 root 或 sudo"; exit 1; }
  SUDO="sudo"
fi

echo "=== Keepalived 2.3.4 一鍵安裝（互動式）==="

# ---------- 讀取輸入 ----------
read -rp "請輸入【主節點 A IP】: " IP_A
read -rp "請輸入【子節點 B IP】: " IP_B
read -rp "請輸入【VIP(含CIDR，例如 192.168.25.26/24)】: " VIP

if ! valid_ip "$IP_A"; then echo "主節點 IP 格式錯誤"; exit 1; fi
if ! valid_ip "$IP_B"; then echo "子節點 IP 格式錯誤"; exit 1; fi
if ! valid_cidr "$VIP"; then echo "VIP 格式錯誤（需含 CIDR）"; exit 1; fi

VIP_IP="$(ip_only "$VIP")"

# ---------- 自動判斷本機角色 ----------
LOCAL_IPS="$(hostname -I 2>/dev/null || true)"
ROLE="auto"
SRC_IP=""
PEER_IP=""
PRIORITY="auto"
STATE="BACKUP"  # 兩台都用 BACKUP，交給 VRRP 選主

if echo " $LOCAL_IPS " | grep -q " $IP_A "; then
  ROLE="MASTER(本機=A)"
  SRC_IP="$IP_A"; PEER_IP="$IP_B"
elif echo " $LOCAL_IPS " | grep -q " $IP_B "; then
  ROLE="BACKUP(本機=B)"
  SRC_IP="$IP_B"; PEER_IP="$IP_A"
else
  echo "未在本機網卡上發現 $IP_A / $IP_B。"
  select choice in "本機是主節點(A)" "本機是子節點(B)"; do
    case "$choice" in
      "本機是主節點(A)") ROLE="MASTER(手動)"; SRC_IP="$IP_A"; PEER_IP="$IP_B"; break;;
      "本機是子節點(B)") ROLE="BACKUP(手動)"; SRC_IP="$IP_B"; PEER_IP="$IP_A"; break;;
      *) echo "請選 1 或 2";;
    esac
  done
fi

# ---------- 設定優先權（IP 大者為主，需可改） ----------
if [ "$PRIORITY" = "auto" ]; then
  if (( $(to_int "$SRC_IP") > $(to_int "$PEER_IP") )); then
    PRIORITY=150
  else
    PRIORITY=100
  fi
fi

# ---------- 偵測網卡 ----------
IFACE="$(iface_of_ip "$SRC_IP")"
[ -z "$IFACE" ] && IFACE="$(route_dev "$PEER_IP")"
[ -z "$IFACE" ] && IFACE="$(route_dev "$VIP_IP")"
[ -z "$IFACE" ] && IFACE="$(default_dev)"
if [ -z "$IFACE" ]; then
  echo "自動偵測網卡失敗，請輸入網卡名稱（例如 ens192、eth0）"
  read -rp "網卡名稱: " IFACE
fi
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "介面 $IFACE 不存在"; exit 1
fi

# ---------- 顯示摘要並確認 ----------
echo
echo "=== 安裝摘要 ==="
echo "本機角色：$ROLE   （VRRP STATE 設為 BACKUP，由優先權決定主/備）"
echo "本機 IP ：$SRC_IP"
echo "對端 IP ：$PEER_IP"
echo "VIP     ：$VIP"
echo "網卡    ：$IFACE"
echo "優先權  ：$PRIORITY   （大者為主，preempt 開啟）"
read -rp "確認開始安裝？(y/N) " go
[[ "${go,,}" == "y" ]] || { echo "已取消"; exit 0; }

# ---------- 安裝相依 ----------
echo "[1/6] 安裝編譯相依..."
if have_cmd apt-get; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y
  $SUDO apt-get install -y build-essential pkg-config libssl-dev \
    libnl-3-dev libnl-genl-3-dev libnl-route-3-dev curl
elif have_cmd dnf; then
  $SUDO dnf install -y gcc make pkgconfig openssl-devel libnl3-devel curl
elif have_cmd yum; then
  $SUDO yum install -y gcc make pkgconfig openssl-devel libnl3-devel curl
elif have_cmd apk; then
  $SUDO apk add --no-cache build-base pkgconfig openssl-dev libnl3-dev curl
else
  echo "無法自動安裝相依，請手動準備：gcc/make/pkgconfig、openssl-devel、libnl3-devel、curl"; exit 1
fi

# ---------- systemd unit 目錄 ----------
if   [ -d /lib/systemd/system ]; then UNITDIR="/lib/systemd/system"
elif [ -d /usr/lib/systemd/system ]; then UNITDIR="/usr/lib/systemd/system"
else UNITDIR="/lib/systemd/system"; fi

# ---------- 下載/編譯/安裝 Keepalived ----------
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

# ---------- 健康檢查 ----------
echo "[3/6] 建立健康檢查腳本..."
$SUDO tee /etc/keepalived/check_nginx.sh >/dev/null <<'CHK'
#!/usr/bin/env bash
set -euo pipefail
pidof nginx >/dev/null 2>&1 || exit 1
if ! curl -fsS --max-time 1 http://127.0.0.1/health >/dev/null 2>&1; then
  curl -fsS -I --max-time 1 http://127.0.0.1/ >/dev/null 2>&1 || exit 1
fi
exit 0
CHK
$SUDO chmod +x /etc/keepalived/check_nginx.sh

# ---------- 產生設定 ----------
echo "[4/6] 產生 /etc/keepalived/keepalived.conf ..."
AUTH_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8 || echo 'ElfP@55!')" # VRRP PASS 只吃 8 碼
$SUDO mkdir -p "$SYSCONFDIR"
$SUDO tee "$SYSCONFDIR/keepalived.conf" >/dev/null <<EOF
global_defs {
  router_id VRRP01
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
  state BACKUP
  interface ${IFACE}
  virtual_router_id 26
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

# ---------- 驗證與啟動 ----------
echo "[5/6] 驗證設定..."
sudo keepalived -t -f "$SYSCONFDIR/keepalived.conf"

echo "[6/6] 開機自啟並立即啟動 keepalived ..."
$SUDO systemctl enable --now keepalived
$SUDO systemctl --no-pager status keepalived || true

echo
echo "完成。請在 Nginx 加入健康端點（兩台皆需）："
echo '  location = /health { access_log off; return 200; }'
echo
echo "目前本機角色推斷：$ROLE"
echo "本機 IP：$SRC_IP  對端 IP：$PEER_IP  VIP：$VIP  IFACE：$IFACE  PRIORITY：$PRIORITY"
echo "檢查 VIP： ip addr | grep -F \"${VIP%%/*}\""
echo "切換測試： systemctl stop nginx   # 應於 1~2 秒內漂移到對端"

