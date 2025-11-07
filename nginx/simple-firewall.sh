#!/usr/bin/env bash
# ================================================================
# simple-firewall.sh
# 目標：快速套用一個精簡的 UFW 基線設定。
# 使用方式：sudo bash simple-firewall.sh
# 可用環境變數覆寫的設定項目見下方「可調參數」。
# ================================================================
set -euo pipefail

# ----- 可調參數（可用環境變數覆寫） -----
LAN_CIDR="${LAN_CIDR:-192.168.25.0/24}"          # 內網 CIDR
SSH_PORT="${SSH_PORT:-22}"                       # SSH 埠
ALLOWED_TCP_FROM_LAN="${ALLOWED_TCP_FROM_LAN:-}" # 內網需額外放行的 TCP 埠（空白分隔）
ALLOW_HTTP_WORLD="${ALLOW_HTTP_WORLD:-yes}"      # yes/no：對全世界放行 80/tcp
ALLOW_HTTPS_WORLD="${ALLOW_HTTPS_WORLD:-yes}"    # yes/no：對全世界放行 443/tcp
ALLOW_LLMNR="${ALLOW_LLMNR:-no}"                 # yes/no：允許 LAN -> 224.0.0.252:5355/udp
ALLOW_IGMP="${ALLOW_IGMP:-no}"                   # yes/no：允許 LAN -> 224.0.0.0/4 的 IGMP
ENABLE_LOGGING="${ENABLE_LOGGING:-on}"           # on/off：UFW logging

# ----- 共用函式 -----
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "缺少指令：$1" >&2; exit 1; }
}

allow_if_yes() {
  local flag="$1" cmd="$2"
  shift 2
  if [[ "$flag" == "yes" ]]; then
    echo "  -> $cmd $*"
    ufw "$cmd" "$@"
  fi
}

# ----- 主流程 -----
[[ $EUID -eq 0 ]] || { echo "請用 root 權限執行此腳本" >&2; exit 1; }
need ufw
need awk
need sort

echo "[1/5] 設定預設政策"
ufw default deny incoming
ufw default allow outgoing

echo "[2/5] 放行內網 SSH 與必要 TCP 埠"
mapfile -t del_ssh < <(ufw status numbered | awk -v cidr="$LAN_CIDR" -v p="${SSH_PORT}/tcp" '
  $0 ~ /^\[/ && $2==p && index($0,cidr)>0 { gsub(/[\[\]]/,"",$1); print $1 }' | sort -nr)
for idx in "${del_ssh[@]:-}"; do ufw --force delete "$idx" || true; done
ufw limit from "$LAN_CIDR" to any port "$SSH_PORT" proto tcp comment "ssh from LAN"

if [[ -n "${ALLOWED_TCP_FROM_LAN// /}" ]]; then
  # shellcheck disable=SC2206
  ports=( ${ALLOWED_TCP_FROM_LAN} )
  for p in "${ports[@]}"; do
    [[ -z "$p" ]] && continue
    ufw allow from "$LAN_CIDR" to any port "$p" proto tcp comment "tcp ${p} from LAN"
  done
fi

if [[ "$ALLOW_LLMNR" == "yes" ]]; then
  ufw allow proto udp from "$LAN_CIDR" to 224.0.0.252 port 5355 comment "LLMNR"
fi

if [[ "$ALLOW_IGMP" == "yes" ]]; then
  ufw allow proto 2 from "$LAN_CIDR" to 224.0.0.0/4 comment "IGMP"
fi

echo "[3/5] 對外服務放行"
allow_if_yes "$ALLOW_HTTP_WORLD" allow 80/tcp comment "http open to world"
allow_if_yes "$ALLOW_HTTPS_WORLD" allow 443/tcp comment "https open to world"

echo "[4/5] 套用設定"
ufw logging "$ENABLE_LOGGING"
ufw --force enable

echo "[5/5] 檢視狀態"
ufw status verbose

echo "完成 ✅ 可透過覆寫環境變數調整策略，例如："
echo "  ALLOW_HTTP_WORLD=no LAN_CIDR=10.0.0.0/24 bash simple-firewall.sh"
