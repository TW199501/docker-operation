#!/usr/bin/env bash
set -euo pipefail

KEEPI_VER="${KEEPI_VER:-2.3.4}"
SRC_DIR="/usr/local/src"
BUILD_DIR="$SRC_DIR/keepalived-$KEEPI_VER"
TARBALL="keepalived-$KEEPI_VER.tar.gz"
URL="https://keepalived.org/software/$TARBALL"
SYSTEMD_UNIT="/etc/systemd/system/keepalived.service"
CHECK_SCRIPT="/usr/local/sbin/check_nginx.sh"
CONF="/etc/keepalived/keepalived.conf"
VRRP_PASS="23887711"   # 固定 8 碼
OPEN_HTTP="${OPEN_HTTP:-no}"    # yes=順便放行 80
OPEN_HTTPS="${OPEN_HTTPS:-no}"  # yes=順便放行 443
SKIP_KEEPALIVED_CONF="${SKIP_KEEPALIVED_CONF:-0}"

need_pkg() {
  command -v "$1" >/dev/null 2>&1 || return 0
  return 1
}

msg() { echo -e "\e[32m==>\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }
die() { echo -e "\e[31m[ERR]\e[0m $*"; exit 1; }

# ------------- 互動輸入（可被環境變數覆寫） -------------
if [ -z "${ROLE:-}" ]; then
  read -rp "節點角色 [MASTER/BACKUP] (預設 MASTER): " ROLE
  ROLE="${ROLE:-MASTER}"
fi
ROLE="$(echo "$ROLE" | tr '[:lower:]' '[:upper:]')"
[[ "$ROLE" == "MASTER" || "$ROLE" == "BACKUP" ]] || die "ROLE 只能是 MASTER 或 BACKUP"

# 自動猜介面（第一個有 IPv4 的介面）
if [ -z "${IFACE:-}" ]; then
  IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
  [ -n "$IFACE" ] || IFACE="$(ip -o link show | awk -F': ' '!/lo/ {print $2; exit}')"
  read -rp "VRRP 介面 (預設 ${IFACE:-eth0}): " tmp; IFACE="${tmp:-${IFACE:-eth0}}"
fi

# 本機介面 IPv4
LOCAL_CIDR="$(ip -o -f inet addr show dev "$IFACE" | awk '{print $4; exit}')"
LOCAL_IP="${LOCAL_CIDR%/*}"
[ -n "$LOCAL_IP" ] || die "無法取得 $IFACE 的 IPv4"

if [ -z "${VRID:-}" ]; then
  read -rp "Virtual Router ID (1-255, 預設 60): " VRID
  VRID="${VRID:-60}"
fi
[[ "$VRID" =~ ^[0-9]+$ ]] || die "VRID 必須是數字"
(( VRID>=1 && VRID<=255 )) || die "VRID 範圍 1..255"

# VIP（允許只填 IP，則自動套本機遮罩；或直接填 CIDR）
if [ -z "${VIP_CIDR:-}" ]; then
  read -rp "VIP（可填 192.168.25.250 或 192.168.25.250/24）: " VIP_CIDR
fi
if [[ "$VIP_CIDR" != */* ]]; then
  PREFIX="${LOCAL_CIDR#*/}"
  VIP_CIDR="$VIP_CIDR/$PREFIX"
fi
VIP_IP="${VIP_CIDR%/*}"

if [ "$ROLE" = "MASTER" ] && command -v ping >/dev/null 2>&1; then
  if ping -c1 -W1 "$VIP_IP" >/dev/null 2>&1; then
    warn "偵測到 VIP $VIP_IP 已可連線，可能已有其他 MASTER 在運行。"
    read -rp "仍要以 MASTER 安裝？[y/N]: " ans
    case "${ans:-N}" in
      y|Y) ;;
      *) die "請改用 ROLE=BACKUP 或先停止現有 MASTER 後再執行";;
    esac
  fi
fi

# 優先權
if [ -z "${PRIORITY:-}" ]; then
  if [ "$ROLE" = "MASTER" ]; then
    read -rp "優先權 (預設 200; BACKUP 請用較小): " PRIORITY
    PRIORITY="${PRIORITY:-200}"
  else
    read -rp "優先權 (預設 100; 需小於 MASTER): " PRIORITY
    PRIORITY="${PRIORITY:-100}"
  fi
fi
[[ "$PRIORITY" =~ ^[0-9]+$ ]] || die "PRIORITY 必須是數字"

# 單播對端（就算對端尚未上線也先填）
if [ -z "${PEER_IP:-}" ]; then
  read -rp "對端實體 IP（單播 unicast，用於 unicast_peer；可先填未上線的對端）: " PEER_IP
fi
[[ "$PEER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "PEER_IP 應是 IPv4 位址"

# 嘗試確認 PEER_IP 是否與本機在同一網段（最佳努力檢查）
if command -v ipcalc >/dev/null 2>&1; then
  LOCAL_NET=$(ipcalc -n "$LOCAL_CIDR" | awk '/Network/{print $2}')
  PEER_NET=$(ipcalc -n "$PEER_IP/${LOCAL_CIDR#*/}" | awk '/Network/{print $2}')
  if [ "$LOCAL_NET" != "$PEER_NET" ]; then
    warn "PEER_IP ($PEER_IP) 與本機 $LOCAL_CIDR 不在同一網段（$LOCAL_NET vs $PEER_NET）"
    read -rp "仍然繼續？[y/N]: " ans
    case "${ans:-N}" in
      y|Y) ;;
      *) die "請修正 PEER_IP 或網段後再執行";;
    esac
  fi
else
  PREFIX_CHECK="${LOCAL_CIDR#*/}"
  if [ "$PREFIX_CHECK" = "24" ]; then
    LOCAL_NET_24="${LOCAL_IP%.*}"
    PEER_NET_24="${PEER_IP%.*}"
    if [ "$LOCAL_NET_24" != "$PEER_NET_24" ]; then
      warn "PEER_IP ($PEER_IP) 可能不在與本機 $LOCAL_IP/$PREFIX_CHECK 相同的 /24 網段"
      read -rp "仍然繼續？[y/N]: " ans
      case "${ans:-N}" in
        y|Y) ;;
        *) die "請修正 PEER_IP 後再執行";;
      esac
    fi
  fi
fi

msg "[1/6] 安裝建置相依與工具"
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y build-essential \
    libssl-dev libnl-3-dev libnl-genl-3-dev libnfnetlink-dev \
    libnftnl-dev pkg-config libpopt-dev libsystemd-dev \
    iproute2 curl tar ca-certificates ufw
elif command -v dnf >/dev/null 2>&1; then
  dnf -y install gcc make openssl-devel libnl3-devel \
    libnfnetlink-devel libnftnl-devel pkgconfig popt-devel systemd-devel \
    iproute curl tar ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum -y install gcc make openssl-devel libnl3-devel \
    libnfnetlink-devel libnftnl-devel pkgconfig popt-devel systemd-devel \
    iproute curl tar ca-certificates
else
  die "不支援的套件管理器，請自行裝編譯相依（gcc/make/libnl/openssl 等）"
fi

msg "[2/6] 取得並安裝 keepalived $KEEPI_VER（來源編譯）"
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"
if [ ! -s "$TARBALL" ]; then
  curl -fSLo "$TARBALL" "$URL"
fi
rm -rf "$BUILD_DIR"
tar -xzf "$TARBALL"
cd "$BUILD_DIR"
./configure --prefix=/usr --sysconfdir=/etc --with-systemd
make -j"$(nproc)"
make install

if [ "$SKIP_KEEPALIVED_CONF" -eq 1 ]; then
  msg "SKIP_KEEPALIVED_CONF=1，僅編譯安裝 keepalived，略過後續配置"
  exit 0
fi

# 以我們安裝的 keepalived 為主，確保 systemd 使用 /usr/sbin/keepalived
if command -v systemctl >/dev/null 2>&1; then
  if [ ! -f "$SYSTEMD_UNIT" ]; then
    cat > "$SYSTEMD_UNIT" <<'UNIT'
[Unit]
Description=LVS and VRRP High Availability Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/keepalived -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/keepalived.pid
KillSignal=SIGTERM
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
UNIT
  fi
else
  warn "systemctl 不存在，略過建立 keepalived.service"
fi

msg "[3/6] 建立 Nginx 健康檢查腳本"
cat > "$CHECK_SCRIPT" <<'SH'
#!/usr/bin/env bash
# 回傳 0 表示健康；非 0 表示失敗
pgrep -x nginx >/dev/null 2>&1 && exit 0
# 若 master 以 nginxWebUI 自訂 -c 方式運行，你也可改成 curl 測試
# curl -fsI --max-time 1 http://127.0.0.1/ >/dev/null 2>&1 && exit 0
exit 1
SH
chmod +x "$CHECK_SCRIPT"

msg "[4/6] 產生 /etc/keepalived/keepalived.conf（單播）"
install -d -m 0755 /etc/keepalived

cat > "$CONF" <<EOF
global_defs {
    enable_script_security
    script_user root
    log_file /var/log/keepalived/keepalived.log
}

vrrp_script chk_nginx {
    script "$CHECK_SCRIPT"
    interval 2
    fall 3
    rise 2
}

vrrp_instance VI_${VRID} {
    state ${ROLE}
    interface ${IFACE}
    virtual_router_id ${VRID}
    priority ${PRIORITY}
    advert_int 1

    # 取得 VIP 時加強 ARP 公告，縮短收斂時間
    garp_master_delay 1
    garp_master_repeat 5

    # 單播設定（對端就算暫時未上線也能先當 MASTER）
    unicast_src_ip ${LOCAL_IP}
    unicast_peer {
        ${PEER_IP}
    }

    authentication {
        auth_type PASS
        auth_pass ${VRRP_PASS}
    }

    track_script {
        chk_nginx
    }

    virtual_ipaddress {
        ${VIP_CIDR} dev ${IFACE}
    }
}
EOF

# 檢查語法
keepalived -t -f "$CONF" || die "keepalived.conf 語法錯誤"

if command -v logrotate >/dev/null 2>&1; then
  install -d -m 0755 /var/log/keepalived
  cat > /etc/logrotate.d/keepalived <<'LOG'
/var/log/keepalived/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
LOG
fi

msg "[5/6] UFW 規則（若已啟用 UFW：放行 VRRP、可選放行 80/443）"
if command -v ufw >/dev/null 2>&1; then
  # 放行 80/443（可選）
  if [ "$OPEN_HTTP" = "yes" ]; then ufw allow 80/tcp  2>/dev/null || true; fi
  if [ "$OPEN_HTTPS" = "yes" ]; then ufw allow 443/tcp 2>/dev/null || true; fi

  # 允許 VRRP 協定（IP 協定 112），在 UFW before.rules / before6.rules 中加入一次性規則
  add_vrrp_rule() {
    local f="$1" fam="$2"
    [ -f "$f" ] || return 0
    if ! grep -q "ACCEPT .* -p 112 .* $IFACE" "$f"; then
      # 在 *filter 區塊的 COMMIT 之前插入
      awk -v iface="$IFACE" '
        BEGIN{added=0}
        /^\*filter/ {print; next}
        /^-A ufw-before-input/ {print; next}
        /^COMMIT$/ && added==0 {
          print "-A ufw-before-input -i " iface " -p 112 -j ACCEPT"
          added=1
        }
        {print}
        END{if(added==0) print "-A ufw-before-input -i " iface " -p 112 -j ACCEPT"}
      ' "$f" > "$f.new" && mv "$f.new" "$f"
    fi
  }

  add_vrrp_rule /etc/ufw/before.rules ipv4
  add_vrrp_rule /etc/ufw/before6.rules ipv6

  ufw --force enable >/dev/null 2>&1 || true
  ufw reload || true
fi

if command -v systemctl >/dev/null 2>&1; then
  msg "[6/6] 啟動 keepalived"
  systemctl daemon-reload
  systemctl enable --now keepalived
  sleep 1
  systemctl --no-pager --full status keepalived || true
else
  warn "systemctl 不存在，略過自動啟動 keepalived（請自行以 keepalived -n -f 啟動）"
fi

echo
echo "================= 摘要 ================="
echo "角色        : $ROLE"
echo "介面        : $IFACE (本機 $LOCAL_IP)"
echo "VRID        : $VRID"
echo "VIP         : $VIP_CIDR"
echo "對端(單播)  : $PEER_IP"
echo "優先權      : $PRIORITY"
echo "VRRP 密碼   : $VRRP_PASS"
echo "設定檔      : $CONF"
echo "健檢腳本    : $CHECK_SCRIPT"
echo "========================================"
echo
echo "檢查 VIP 是否掛上："
echo "  ip -4 addr show dev $IFACE | grep '$VIP_IP'"
echo
echo "檢查 VRRP 訊息："
echo "  journalctl -u keepalived -e -n 100 | egrep 'VRRP|Transition|STATE'"
echo
echo "備註："
echo " - 單播模式下，對端沒上線也能先當 MASTER、持有 VIP。"
echo " - 若你用 nginxWebUI 自訂 -c 啟動 Nginx，不影響本健檢（以進程為準）。"
