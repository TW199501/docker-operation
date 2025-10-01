#!/usr/bin/env bash
set -euo pipefail

# ==== 可調參數 ====
LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"
LAN_SSH_PORT="${LAN_SSH_PORT:-22}"
LAN_EXTRA_PORTS=("8080")      # 內網需要放行的其他 TCP 埠
CF_PORTS=("80" "443")         # 只給 Cloudflare 的埠
UFW_BIN="${UFW_BIN:-/usr/sbin/ufw}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少指令：$1"; exit 1; }; }

# 0) 前置檢查
[[ $EUID -eq 0 ]] || { echo "請用 root 執行"; exit 1; }
need curl
need awk
need sed
[[ -x "$UFW_BIN" ]] || { echo "找不到 UFW（$UFW_BIN）。請先安裝 ufw。"; exit 1; }

echo "== 設定 UFW 預設策略（入封/出放） =="
$UFW_BIN default deny incoming
$UFW_BIN default allow outgoing

# 1) 內網放行 SSH (limit) 與 8080
echo "== 內網白名單（$LAN_CIDR）放行 SSH:$LAN_SSH_PORT（限速）與必要埠 =="
# 先刪掉同用途的舊規則（避免重複）
# 刪 SSH（內網）相關舊規則
mapfile -t DEL_SSH < <($UFW_BIN status numbered | awk -v cidr="$LAN_CIDR" -v p="$LAN_SSH_PORT/tcp" '
  $0 ~ /^\[/ && $2==p && index($0,cidr)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
for i in "${DEL_SSH[@]:-}"; do $UFW_BIN --force delete "$i" || true; done
# 新增限速 SSH（內網）
$UFW_BIN limit from "$LAN_CIDR" to any port "$LAN_SSH_PORT" proto tcp

# 新增 8080（或其他）內網放行（若重複 UFW 會自動略過）
for p in "${LAN_EXTRA_PORTS[@]}"; do
  $UFW_BIN allow from "$LAN_CIDR" to any port "$p" proto tcp
done

# 2) 移除殘留的 Anywhere 規則（80/443/22/8080），避免洩放
echo "== 清除殘留 Anywhere 規則（80/443/22/8080） =="
ANY_PORTS=("80" "443" "$LAN_SSH_PORT" "${LAN_EXTRA_PORTS[@]}")
for p in "${ANY_PORTS[@]}"; do
  mapfile -t DEL_ANY < <($UFW_BIN status numbered | awk -v p="$p/tcp" '
    $0 ~ /^\[/ && $2==p && ($0 ~ /Anywhere/ || $0 ~ /Anywhere \(v6\)/) { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
  for i in "${DEL_ANY[@]:-}"; do $UFW_BIN --force delete "$i" || true; done
done

# 3) 安裝/更新 Cloudflare 自動允許腳本
echo "== 安裝 ufw-cf-allow.sh（自動同步 Cloudflare 網段） =="
install -d -m 0755 /usr/local/sbin
cat >/usr/local/sbin/ufw-cf-allow.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="/var/lib/ufw-cf"
CF4_URL="https://www.cloudflare.com/ips-v4"
CF6_URL="https://www.cloudflare.com/ips-v6"
PORTS=("80" "443")
UFW="${UFW:-/usr/sbin/ufw}"
IPV6_ENABLED="no"
[[ -f /etc/default/ufw ]] && IPV6_ENABLED=$(awk -F= '/^IPV6=/{print tolower($2)}' /etc/default/ufw || echo "no")

mkdir -p "$STATE_DIR"
CF4_NEW="$(mktemp)"; CF6_NEW="$(mktemp)"
CF4_OLD="$STATE_DIR/cf4.prev"; CF6_OLD="$STATE_DIR/cf6.prev"

curl -fsS "$CF4_URL" | sort -u > "$CF4_NEW"
if [[ "$IPV6_ENABLED" == "yes" ]]; then
  curl -fsS "$CF6_URL" | sort -u > "$CF6_NEW"
else
  : > "$CF6_NEW"
fi

[[ -f "$CF4_OLD" ]] || : > "$CF4_OLD"
[[ -f "$CF6_OLD" ]] || : > "$CF6_OLD"

CF4_ADD=$(comm -13 "$CF4_OLD" "$CF4_NEW" || true)
CF4_DEL=$(comm -23 "$CF4_OLD" "$CF4_NEW" || true)
CF6_ADD=""; CF6_DEL=""
if [[ "$IPV6_ENABLED" == "yes" ]]; then
  CF6_ADD=$(comm -13 "$CF6_OLD" "$CF6_NEW" || true)
  CF6_DEL=$(comm -23 "$CF6_OLD" "$CF6_NEW" || true)
fi

delete_rules_for_net() {
  local net="$1" port="$2"
  mapfile -t IDX < <("$UFW" status numbered | awk -v n="$net" -v p="$port/tcp" '
    $0 ~ /^\[/ && $2==p && index($0,n)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
  for i in "${IDX[@]:-}"; do "$UFW" --force delete "$i" || true; done
}

# 刪除不再存在的 IPv4
if [[ -n "${CF4_DEL}" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do delete_rules_for_net "$net" "$port"; done
  done <<< "$CF4_DEL"
fi
# 刪除不再存在的 IPv6
if [[ "$IPV6_ENABLED" == "yes" && -n "${CF6_DEL}" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do delete_rules_for_net "$net" "$port"; done
  done <<< "$CF6_DEL"
fi

# 新增缺少的 IPv4
if [[ -n "${CF4_ADD}" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do
      "$UFW" allow proto tcp from "$net" to any port "$port" comment "cf-auto"
    done
  done <<< "$CF4_ADD"
fi
# 新增缺少的 IPv6
if [[ "$IPV6_ENABLED" == "yes" && -n "${CF6_ADD}" ]]; then
  while read -r net; do
    [[ -z "$net" ]] && continue
    for port in "${PORTS[@]}"; do
      "$UFW" allow proto tcp from "$net" to any port "$port" comment "cf-auto"
    done
  done <<< "$CF6_ADD"
fi

install -m 0644 "$CF4_NEW" "$CF4_OLD"
if [[ "$IPV6_ENABLED" == "yes" ]]; then install -m 0644 "$CF6_NEW" "$CF6_OLD"; fi
rm -f "$CF4_NEW" "$CF6_NEW"
echo "[OK] UFW Cloudflare rules synced."
BASH
chmod +x /usr/local/sbin/ufw-cf-allow.sh

# 4) 先同步一次 Cloudflare 規則
echo "== 同步 Cloudflare 白名單（首次） =="
/usr/local/sbin/ufw-cf-allow.sh

# 5) 建立/更新 crontab：每月 1、16 日 04:03 執行
echo "== 設定 crontab（每月 1、16 日 04:03） =="
sed -i '\#ufw-cf-allow.sh#d' /etc/crontab
echo '3 4 1,16 * * root /usr/local/sbin/ufw-cf-allow.sh >/var/log/ufw-cf-allow.log 2>&1' >> /etc/crontab
systemctl reload cron 2>/dev/null || service cron reload 2>/dev/null || true

# 6) 開啟 UFW 日誌並啟用 UFW（強制模式，避免互動）
echo "== 啟用 UFW 並開啟日誌 =="
$UFW_BIN logging on
$UFW_BIN --force enable
$UFW_BIN reload

echo "== 最終狀態 =="
$UFW_BIN status verbose
echo "完成 ✅"
