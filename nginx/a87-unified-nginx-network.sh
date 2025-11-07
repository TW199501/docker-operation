#!/usr/bin/env bash
# ============================================================================
# a87-unified-nginx-network.sh
# 功能：
#   1. 建立 UFW 基線並安裝 Cloudflare 網段自動同步（若偵測到 ufw）
#   2. 建立 firewalld Cloudflare ipset 自動同步（若偵測到 firewall-cmd）
#   3. 建立 nginx GeoIP2 + Cloudflare real_ip 更新機制（若偵測到 nginx）
#   4. 將上述 cron 排程寫入 /etc/cron.d/*（避免依賴 /etc/crontab）
# 可透過環境變數覆寫的設定參數請參考下方預設變數區。
# ============================================================================
set -euo pipefail

# ----- 可調整參數（都可用環境變數覆寫）-----
ENABLE_UFW="${ENABLE_UFW:-auto}"              # auto|yes|no
ENABLE_FIREWALLD="${ENABLE_FIREWALLD:-auto}"  # auto|yes|no
ENABLE_NGINX_GEOIP="${ENABLE_NGINX_GEOIP:-auto}" # auto|yes|no

LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"
LAN_SSH_PORT="${LAN_SSH_PORT:-22}"
LAN_EXTRA_PORTS="${LAN_EXTRA_PORTS:-8080}"      # 以空白分隔，可為空字串
CF_TCP_PORTS="${CF_TCP_PORTS:-80 443}"          # Cloudflare 要放行的 TCP 埠
ALLOW_LLMNR="${ALLOW_LLMNR:-no}"                # yes: 允許 LAN -> 224.0.0.252:5355
ALLOW_IGMP="${ALLOW_IGMP:-no}"                  # yes: 允許 IGMP 多播（proto 2）

GEOIP_DIR="${GEOIP_DIR:-/etc/nginx/geoip}"
CF_LOCAL_TRUST="${CF_LOCAL_TRUST:-127.0.0.1}"    # cloudflared / 本機來源（空白分隔）

UFW_CRON_SPEC="${UFW_CRON_SPEC:-3 4 1,16 * *}"
FIREWALLD_CRON_SPEC="${FIREWALLD_CRON_SPEC:-15 4 * * *}"
GEOIP_CRON_SPEC="${GEOIP_CRON_SPEC:-0 3 * * 3,6}"

LOG_DIR="${LOG_DIR:-/var/log}"                  # 放置排程輸出的目錄

# ----- 共用工具函式 -----
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "缺少指令：$1" >&2; exit 1; }
}

reload_cron_if_needed() {
  if (( CRON_RELOAD_NEEDED )); then
    systemctl reload cron 2>/dev/null || \
      systemctl reload crond 2>/dev/null || \
      service cron reload 2>/dev/null || \
      service crond reload 2>/dev/null || true
  fi
}

install_cron_job() {
  local name="$1"
  local spec="$2"
  local cmd="$3"
  local file="/etc/cron.d/$1"

  install -d -m 0755 /etc/cron.d
  printf '%s root %s\n' "$spec" "$cmd" >"$file"
  chmod 0644 "$file"
  CRON_RELOAD_NEEDED=1
}

ensure_log_dir() {
  install -d -m 0755 "$LOG_DIR"
}

setup_ufw() {
  echo "[UFW] 偵測到 ufw，執行 UFW 基線設定"
  need ufw
  need curl
  need awk
  need sed
  need sort
  need comm

  local -a extra_ports=()
  if [[ -n "${LAN_EXTRA_PORTS// /}" ]]; then
    # shellcheck disable=SC2206
    extra_ports=(${LAN_EXTRA_PORTS})
  fi

  # 預設策略
  ufw default deny incoming
  ufw default allow outgoing

  echo "  - 內網 ${LAN_CIDR} 放行 SSH:${LAN_SSH_PORT} (limit) 與額外埠"
  mapfile -t DEL_SSH < <(ufw status numbered | awk -v cidr="$LAN_CIDR" -v p="${LAN_SSH_PORT}/tcp" '
    $0 ~ /^\[/ && $2==p && index($0,cidr)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
  for idx in "${DEL_SSH[@]:-}"; do ufw --force delete "$idx" || true; done
  ufw limit from "$LAN_CIDR" to any port "$LAN_SSH_PORT" proto tcp

  for p in "${extra_ports[@]}"; do
    [[ -z "$p" ]] && continue
    ufw allow from "$LAN_CIDR" to any port "$p" proto tcp
  done

  if [[ "$ALLOW_LLMNR" == "yes" ]]; then
    echo "  - 允許 LLMNR（UDP 5355 多播）"
    ufw allow proto udp from "$LAN_CIDR" to 224.0.0.252 port 5355 comment 'LLMNR'
  fi

  if [[ "$ALLOW_IGMP" == "yes" ]]; then
    echo "  - 允許 IGMP 多播報文"
    ufw allow proto 2 from "$LAN_CIDR" to 224.0.0.0/4 comment 'IGMP'
  fi

  echo "  - 清除殘留 Anywhere 規則"
  local -a any_ports=(80 443 "$LAN_SSH_PORT")
  for p in "${extra_ports[@]}"; do any_ports+=("$p"); done
  for p in "${any_ports[@]}"; do
    mapfile -t DEL_ANY < <(ufw status numbered | awk -v port="${p}/tcp" '
      $0 ~ /^\[/ && $2==port && ($0 ~ /Anywhere/ || $0 ~ /Anywhere \(v6\)/) { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
    for idx in "${DEL_ANY[@]:-}"; do ufw --force delete "$idx" || true; done
  done

  echo "  - 安裝 /usr/local/sbin/ufw-cf-sync.sh"
  install -d -m 0755 /usr/local/sbin
  cat >/usr/local/sbin/ufw-cf-sync.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="/var/lib/ufw-cf"
CF4_URL="https://www.cloudflare.com/ips-v4"
CF6_URL="https://www.cloudflare.com/ips-v6"
UFW="${UFW:-/usr/sbin/ufw}"
PORT_STRING="${CF_PORTS:-80 443}"
IPV6_ENABLED="no"
[[ -f /etc/default/ufw ]] && IPV6_ENABLED=$(awk -F= '/^IPV6=/{print tolower($2)}' /etc/default/ufw || echo "no")

IFS=' ' read -r -a PORTS <<<"${PORT_STRING}"
mkdir -p "$STATE_DIR"
CF4_NEW="$(mktemp)"; CF6_NEW="$(mktemp)"
CF4_OLD="$STATE_DIR/cf4.prev"; CF6_OLD="$STATE_DIR/cf6.prev"

curl -fsS "$CF4_URL" | sort -u > "$CF4_NEW"
if [[ "$IPV6_ENABLED" == "yes" ]]; then
  curl -fsS "$CF6_URL" | sort -u > "$CF6_NEW"
else
  : >"$CF6_NEW"
fi

[[ -f "$CF4_OLD" ]] || : >"$CF4_OLD"
[[ -f "$CF6_OLD" ]] || : >"$CF6_OLD"

CF4_ADD=$(comm -13 "$CF4_OLD" "$CF4_NEW" || true)
CF4_DEL=$(comm -23 "$CF4_OLD" "$CF4_NEW" || true)
CF6_ADD=""; CF6_DEL=""
if [[ "$IPV6_ENABLED" == "yes" ]]; then
  CF6_ADD=$(comm -13 "$CF6_OLD" "$CF6_NEW" || true)
  CF6_DEL=$(comm -23 "$CF6_OLD" "$CF6_NEW" || true)
fi

delete_rules_for_net() {
  local net="$1" port="$2"
  mapfile -t IDX < <("$UFW" status numbered | awk -v n="$net" -v p="${port}/tcp" '
    $0 ~ /^\[/ && $2==p && index($0,n)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
  for i in "${IDX[@]:-}"; do "$UFW" --force delete "$i" || true; done
}

if [[ -n "$CF4_DEL" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do delete_rules_for_net "$net" "$port"; done
  done <<<"$CF4_DEL"
fi

if [[ "$IPV6_ENABLED" == "yes" && -n "$CF6_DEL" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do delete_rules_for_net "$net" "$port"; done
  done <<<"$CF6_DEL"
fi

if [[ -n "$CF4_ADD" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do
      "$UFW" allow proto tcp from "$net" to any port "$port" comment "cf-auto"
    done
  done <<<"$CF4_ADD"
fi

if [[ "$IPV6_ENABLED" == "yes" && -n "$CF6_ADD" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do
      "$UFW" allow proto tcp from "$net" to any port "$port" comment "cf-auto"
    done
  done <<<"$CF6_ADD"
fi

install -m 0644 "$CF4_NEW" "$CF4_OLD"
if [[ "$IPV6_ENABLED" == "yes" ]]; then install -m 0644 "$CF6_NEW" "$CF6_OLD"; fi
rm -f "$CF4_NEW" "$CF6_NEW"
echo "[OK] UFW Cloudflare rules synced."
BASH
  chmod +x /usr/local/sbin/ufw-cf-sync.sh

  echo "  - 首次同步 Cloudflare 網段"
  /usr/local/sbin/ufw-cf-sync.sh || true

  echo "  - 啟用 UFW 並開啟日誌"
  ufw logging on
  ufw --force enable
  ufw reload

  ensure_log_dir
  install_cron_job "ufw-cf-sync" "$UFW_CRON_SPEC" \
    "/usr/local/sbin/ufw-cf-sync.sh >$LOG_DIR/ufw-cf-sync.log 2>&1"
}

setup_firewalld() {
  echo "[firewalld] 偵測到 firewall-cmd，設定 Cloudflare ipset 排程"
  need firewall-cmd
  need curl
  need xargs

  if ! firewall-cmd --permanent --get-ipsets | grep -qw cloudflare4; then
    firewall-cmd --permanent --new-ipset=cloudflare4 --type=hash:net
  fi
  if ! firewall-cmd --permanent --get-ipsets | grep -qw cloudflare6; then
    firewall-cmd --permanent --new-ipset=cloudflare6 --type=hash:net
  fi

  install -d -m 0755 /usr/local/sbin
  cat >/usr/local/sbin/firewalld-cf-sync.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
v4=$(mktemp)
v6=$(mktemp)
trap 'rm -f "$v4" "$v6"' EXIT
curl -fsS https://www.cloudflare.com/ips-v4 >"$v4"
curl -fsS https://www.cloudflare.com/ips-v6 >"$v6"

for e in $(firewall-cmd --permanent --ipset=cloudflare4 --get-entries 2>/dev/null); do
  firewall-cmd --permanent --ipset=cloudflare4 --remove-entry="$e" || true
done
for e in $(firewall-cmd --permanent --ipset=cloudflare6 --get-entries 2>/dev/null); do
  firewall-cmd --permanent --ipset=cloudflare6 --remove-entry="$e" || true
done

xargs -r -I{} firewall-cmd --permanent --ipset=cloudflare4 --add-entry={} <"$v4"
xargs -r -I{} firewall-cmd --permanent --ipset=cloudflare6 --add-entry={} <"$v6"

firewall-cmd --reload
echo "[OK] firewalld Cloudflare ipsets synced."
BASH
  chmod +x /usr/local/sbin/firewalld-cf-sync.sh

  echo "  - 首次同步 Cloudflare ipset"
  /usr/local/sbin/firewalld-cf-sync.sh || true

  ensure_log_dir
  install_cron_job "firewalld-cf-sync" "$FIREWALLD_CRON_SPEC" \
    "/usr/local/sbin/firewalld-cf-sync.sh >$LOG_DIR/firewalld-cf-sync.log 2>&1"
}

setup_geoip2() {
  echo "[nginx] 偵測到 nginx，建立 GeoIP2 + CF real_ip 更新"
  need nginx
  need curl
  need awk

  install -d -m 0755 "$GEOIP_DIR"
  install -d -m 0755 /usr/local/sbin

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  fetch_mmdb() {
    local url="$1" name="$2"
    echo "  - 下載 $name"
    if curl -fL --retry 3 -o "$tmp/$name" "$url"; then
      install -m 0644 "$tmp/$name" "$GEOIP_DIR/$name"
    else
      echo "    !! 無法下載 $name（$url）" >&2
    fi
  }

  fetch_mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb" "GeoLite2-Country.mmdb"
  fetch_mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb" "GeoLite2-City.mmdb"
  fetch_mmdb "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb" "GeoLite2-ASN.mmdb"

  echo "  - 建立 Cloudflare real_ip 清單"
  curl -fsS https://www.cloudflare.com/ips-v4 | awk '{print "set_real_ip_from " $1 ";"}' >"$tmp/cloudflare_v4_realip.conf"
  curl -fsS https://www.cloudflare.com/ips-v6 | awk '{print "set_real_ip_from " $1 ";"}' >"$tmp/cloudflare_v6_realip.conf"
  install -m 0644 "$tmp/cloudflare_v4_realip.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
  install -m 0644 "$tmp/cloudflare_v6_realip.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"

  {
    IFS=' ' read -r -a LOCAL_TRUST_ARR <<<"$CF_LOCAL_TRUST"
    for ip in "${LOCAL_TRUST_ARR[@]}"; do
      [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"
    done
  } >"$tmp/cloudflared_realip.conf"
  install -m 0644 "$tmp/cloudflared_realip.conf" "$GEOIP_DIR/cloudflared_realip.conf"

  cat >/usr/local/sbin/update_geoip2.sh <<'UPD'
#!/usr/bin/env bash
set -euo pipefail
GEOIP_DIR="${GEOIP_DIR:-/etc/nginx/geoip}"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_LOCAL_TRUST="${CF_LOCAL_TRUST:-127.0.0.1}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少指令：$1" >&2; exit 1; }; }
need curl
need awk
need nginx

fetch() {
  local url="$1" name="$2"
  if curl -fL --retry 3 -o "$TMP/$name" "$url"; then
    install -m 0644 "$TMP/$name" "$GEOIP_DIR/$name"
  fi
}

fetch "$COUNTRY_URL" GeoLite2-Country.mmdb || true
fetch "$CITY_URL" GeoLite2-City.mmdb || true
fetch "$ASN_URL" GeoLite2-ASN.mmdb || true

curl -fsS "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' >"$TMP/cloudflare_v4_realip.conf"
curl -fsS "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' >"$TMP/cloudflare_v6_realip.conf"
install -m 0644 "$TMP/cloudflare_v4_realip.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
install -m 0644 "$TMP/cloudflare_v6_realip.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"

{
  IFS=' ' read -r -a LOCAL_TRUST <<<"$CF_LOCAL_TRUST"
  for ip in "${LOCAL_TRUST[@]}"; do
    [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"
  done
} >"$TMP/cloudflared_realip.conf"
install -m 0644 "$TMP/cloudflared_realip.conf" "$GEOIP_DIR/cloudflared_realip.conf"

if nginx -t; then
  nginx -s reload
  echo "[OK] GeoIP/CF 清單已更新並重新載入 NGINX"
else
  echo "[WARN] nginx -t 失敗，未重載" >&2
fi
UPD
  chmod +x /usr/local/sbin/update_geoip2.sh

  echo "  - 首次執行 update_geoip2.sh"
  /usr/local/sbin/update_geoip2.sh || true

  ensure_log_dir
  install_cron_job "update-geoip2" "$GEOIP_CRON_SPEC" \
    "/usr/local/sbin/update_geoip2.sh >$LOG_DIR/update_geoip2.log 2>&1"
}

# ----- 主流程 -----
[[ $EUID -eq 0 ]] || { echo "請用 root 權限執行此腳本" >&2; exit 1; }

CRON_RELOAD_NEEDED=0
ensure_log_dir

if [[ "$ENABLE_UFW" == "auto" ]]; then
  if command -v ufw >/dev/null 2>&1; then ENABLE_UFW="yes"; else ENABLE_UFW="no"; fi
fi
if [[ "$ENABLE_FIREWALLD" == "auto" ]]; then
  if command -v firewall-cmd >/dev/null 2>&1; then ENABLE_FIREWALLD="yes"; else ENABLE_FIREWALLD="no"; fi
fi
if [[ "$ENABLE_NGINX_GEOIP" == "auto" ]]; then
  if command -v nginx >/dev/null 2>&1; then ENABLE_NGINX_GEOIP="yes"; else ENABLE_NGINX_GEOIP="no"; fi
fi

[[ "$ENABLE_UFW" == "yes" ]] && setup_ufw || echo "[UFW] 略過"
[[ "$ENABLE_FIREWALLD" == "yes" ]] && setup_firewalld || echo "[firewalld] 略過"
[[ "$ENABLE_NGINX_GEOIP" == "yes" ]] && setup_geoip2 || echo "[nginx] 略過"

reload_cron_if_needed

echo "\n=== 完成 ==="
[[ "$ENABLE_UFW" == "yes" ]] && echo "  • UFW Cloudflare 同步排程：$UFW_CRON_SPEC"
[[ "$ENABLE_FIREWALLD" == "yes" ]] && echo "  • firewalld Cloudflare 同步排程：$FIREWALLD_CRON_SPEC"
[[ "$ENABLE_NGINX_GEOIP" == "yes" ]] && echo "  • nginx GeoIP2 更新排程：$GEOIP_CRON_SPEC"
echo "  • Cron job 位置：/etc/cron.d/"
