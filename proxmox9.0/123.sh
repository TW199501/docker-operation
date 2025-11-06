#!/usr/bin/env bash
# Debian 13 VM Toolkit（PVE VM + Docker，無 VLAN 版）
# 功能：
#   1) 設定 root 密碼 + 啟用 SSH（允許 root 密碼登入）
#   2) 配置固定 IP（只輸入最後一碼；自動偵測網段與 gateway；含衝突檢查）
#   3) 禁用 IPv6（只問一次；使用 sysctl 持久化）
#   4) 優化大檔處理（sysctl）
#   5) 擴展硬碟（支援傳統分割區與常見 LVM 佈署）
#   6) 優化網路傳輸（BBR/fq、socket buffer、TFO、txqueuelen、GRO/GSO/TSO）
#   7) Docker 調優（daemon.json：MTU/IPv6/default-ulimits nofile；服務 LimitNOFILE）
# 注意：
#   - 本腳本假設「未使用 VLAN」，PVE 以 vmbr0 ⇄ eno1 橋接至 LAN。
#   - 請用 Bash 執行；若誤用 sh，腳本會自動以 bash 重新啟動。

# --- 強制使用 bash ---
if [ -z "${BASH_VERSION:-}" ]; then exec /usr/bin/env bash "$0" "$@"; fi

set -Eeuo pipefail

# --- 基本輸出 ---
info(){ echo "[INFO] $*"; }
ok(){ echo "[OK] $*"; }
err(){ echo "[ERROR] $*" >&2; }

# --- 等待 systemd 就緒（避免早期服務未起） ---
i=1
while [ $i -le 30 ]; do
  s=$(systemctl is-system-running 2>/dev/null || true)
  [ "$s" = "running" ] && break
  sleep 1
  i=$((i+1))
done
ok "系統就緒。"

# --- 共用工具 ---
ensure_pkg(){
  # 簡單裝套件（存在就略過）
  local pkgs=("$@")
  local need_install=()
  for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || need_install+=("$p"); done
  if [ ${#need_install[@]} -gt 0 ]; then
    apt-get update || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${need_install[@]}" || true
  fi
}

ensure_line(){ # 若檔案內不存在該「完整行」，則追加
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >>"$file"
}

first_nameserver(){ awk '/^nameserver[ 	]+([0-9]+\.){3}[0-9]+/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true; }

prefix_to_netmask(){
  # 參數：CIDR 數字 → netmask；無或不合法回 24
  local p="${1:-24}" mask="" full rem
  [[ "$p" =~ ^[0-9]+$ ]] || p=24
  (( p>=0 && p<=32 )) || p=24
  full=$((p/8)); rem=$((p%8))
  # 不用大括號展開，避免相容性問題
  for i in 1 2 3 4; do
    if (( i<=full )); then mask+="${mask:+.}255"
    elif (( rem>0 )); then mask+="${mask:+.}$((256-2**(8-rem)))"; rem=0
    else mask+="${mask:+.}0"; fi
  done
  echo "$mask"
}

# ========== 1) root 密碼 + SSH ==========
set_root_password_and_ssh(){
  if [ "$EUID" -ne 0 ]; then err "請以 root 身分執行。"; return 1; fi
  info "設定 root 密碼"
  while :; do
    read -rs -p "輸入新密碼: " p1; echo
    read -rs -p "再次輸入確認: " p2; echo
    [ -z "$p1" ] && { err "密碼不可為空。"; continue; }
    [ "$p1" != "$p2" ] && { err "兩次輸入不一致。"; continue; }
    echo "root:$p1" | chpasswd
    ok "root 密碼已更新。"; break
  done
  info "配置 SSH（允許密碼登入與 root 登入）"
  ensure_pkg openssh-server
  local cfg=/etc/ssh/sshd_config
  touch "$cfg"
  sed -i -E 's/^[# ]*PasswordAuthentication[ 	]+.*/PasswordAuthentication yes/' "$cfg" || true
  sed -i -E 's/^[# ]*PermitRootLogin[ 	]+.*/PermitRootLogin yes/' "$cfg" || true
  ensure_line "PasswordAuthentication yes" "$cfg"
  ensure_line "PermitRootLogin yes" "$cfg"
  ssh-keygen -A >/dev/null 2>&1 || true
  systemctl restart ssh || service ssh restart || true
  ok "SSH 已配置完成。"
}

# ========== 2) 固定 IP（只輸入最後一碼） ==========
configure_static_ip_last_octet(){
  info "偵測目前網路介面與網段（無 VLAN）"
  # 介面：先抓 default route，其次抓第一個有全域 IPv4 的介面
  local iface gw ip_cidr ip base prefix mask
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  [ -z "${iface:-}" ] && iface=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2; exit}')
  [ -z "${iface:-}" ] && { err "找不到可用網路介面（無 default route / 無全域 IPv4）。"; return 1; }
  ip_cidr=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | head -1)
  ip=$(echo "$ip_cidr" | cut -d/ -f1)
  prefix=$(echo "$ip_cidr" | cut -d/ -f2)
  gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')
  if [ -n "${ip:-}" ]; then base=$(echo "$ip" | awk -F. '{print $1"."$2"."$3}')
  elif [ -n "${gw:-}" ]; then base=$(echo "$gw" | awk -F. '{print $1"."$2"."$3}')
  else err "無法從系統偵測到網段。"; return 1; fi
  [[ -n "${prefix:-}" ]] || prefix=24
  [[ "$prefix" =~ ^[0-9]+$ ]] || prefix=24
  (( prefix>=0 && prefix<=32 )) || prefix=24
  mask=$(prefix_to_netmask "$prefix")
  [ -n "${gw:-}" ] || gw="${base}.1"
  echo "介面：$iface"; echo "偵測到網段：${base}.X/${prefix}（netmask $mask）"; echo "偵測到 gateway：$gw"; echo
  local x
  while :; do
    read -rp "請輸入最後一碼 X（1-254，不與 gateway 相同）： " x
    [[ "$x" =~ ^[0-9]+$ ]] || { err "請輸入數字。"; continue; }
    (( x>=1 && x<=254 )) || { err "範圍需在 1~254。"; continue; }
    if [[ "$gw" =~ ^([0-9]+\.){3}([0-9]+)$ ]]; then gw_last=${BASH_REMATCH[2]}; [ "$x" = "$gw_last" ] && { err "X 不可與 gateway 相同（$gw）。"; continue; }; fi
    break
  done
  local static_ip="${base}.${x}"; echo "將設定靜態 IP：$static_ip/$prefix（gateway: $gw）"
  info "檢查 IP 是否衝突：$static_ip"
  local conflict=0
  if command -v arping >/dev/null 2>&1; then ensure_pkg iputils-arping >/dev/null 2>&1 || true; arping -D -I "$iface" -c 2 "$static_ip" >/dev/null 2>&1 || conflict=1
  else ping -c1 -W1 "$static_ip" >/dev/null 2>&1 && conflict=1; fi
  [ $conflict -eq 1 ] && { err "偵測到 $static_ip 可能已被使用（衝突）。"; return 1; }
  ok "無衝突。"
  local default_dns dns_input; default_dns=$(first_nameserver); [ -z "${default_dns:-}" ] && default_dns=1.1.1.1
  read -rp "輸入 DNS（預設 $default_dns，可留空；多個以空白分隔）: " dns_input
  [ -z "${dns_input:-}" ] && dns_input="$default_dns"
  [ -f /etc/network/interfaces ] && cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s) || true
  cat >/etc/network/interfaces <<EOF
# 由腳本產生：靜態 IPv4（無 VLAN）
auto lo
iface lo inet loopback

auto $iface
iface $iface inet static
    address $static_ip
    netmask $mask
    gateway $gw
    dns-nameservers $dns_input
EOF
  info "重新啟動 networking 服務..."
  systemctl restart networking || { err "networking 重啟失敗；改用 ifdown/ifup。"; ifdown "$iface" || true; ifup "$iface" || true; }
  ok "靜態 IP 設定完成。"; ip -4 addr show dev "$iface" || true
  if ! command -v resolvectl >/dev/null 2>&1; then : >/etc/resolv.conf; for ns in $dns_input; do echo "nameserver $ns" >>/etc/resolv.conf; done; ok "resolv.conf 已更新。"; fi
}

# ========== 3) 禁用 IPv6（只問一次；sysctl） ==========
disable_ipv6_once(){
  info "禁用 IPv6（sysctl）"
  local f=/etc/sysctl.d/99-no-ipv6.conf
  mkdir -p /etc/sysctl.d
  cat >"$f" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true
  ok "IPv6 已禁用（持久化於 $f；重開後仍生效）。"
}

# ========== 4) 優化大檔處理 ==========
optimize_for_large_files(){
  info "寫入 sysctl 優化參數（大檔）」
  local f=/etc/sysctl.d/99-io-tuning.conf
  mkdir -p /etc/sysctl.d
  cat >"$f" <<'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true
  ok "完成（$f）。"
}

# ========== 5) 擴展硬碟（傳統分割區 + 常見 LVM） ==========
expand_disk(){
  info "擴展根分割與檔案系統"
  ensure_pkg cloud-guest-utils lvm2 xfsprogs btrfs-progs || true
  local rootdev fstype
  rootdev=$(findmnt -no SOURCE /)
  fstype=$(findmnt -no FSTYPE /)
  info "根裝置：$rootdev；檔案系統：$fstype"
  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    # LVM：找出 LV 與底層 PV 分割，growpart → pvresize → lvextend -r
    local lv pv disk part
    lv="$rootdev"
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | awk 'NF{print $1; exit}')
    [ -z "${pv:-}" ] && { err "找不到 PV，可能非 LVM 或需手動。"; return 1; }
    if [[ "$pv" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$pv" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else err "無法解析 PV：$pv"; return 1; fi
    info "擴分割：$disk 第 $part 分割 → pvresize → lvextend"
    growpart "$disk" "$part" || { err "growpart 失敗"; return 1; }
    pvresize "$pv" || { err "pvresize 失敗"; return 1; }
    lvextend -r -l +100%FREE "$lv" || { err "lvextend 失敗"; return 1; }
    ok "LVM 擴容完成。"; df -h /
    return 0
  fi
  # 非 LVM：直接 growpart + 對應檔案系統成長
  local disk part
  if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
  elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
  else err "不支援的根裝置：$rootdev"; return 1; fi
  info "擴分割：$disk 第 $part 分割"
  growpart "$disk" "$part" || { err "growpart 失敗"; return 1; }
  case "$fstype" in
    ext2|ext3|ext4) resize2fs "$rootdev" ;;
    xfs) xfs_growfs -d / ;;
    btrfs) btrfs filesystem resize max / ;;
    *) err "不支援的檔案系統：$fstype"; return 1 ;;
  esac
  ok "擴容完成。"; df -h /
}

# ========== 6) 優化網路傳輸 ==========
optimize_network_stack(){
  info "優化 Linux 網路傳輸參數"
  local f=/etc/sysctl.d/99-net-opt.conf
  mkdir -p /etc/sysctl.d
  # 判斷是否支援 BBR
  local cc="cubic"
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then cc="bbr"; fi
  cat >"$f" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = $cc
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 1048576 67108864
net.ipv4.tcp_wmem = 4096 1048576 67108864
net.ipv4.ip_forward = 1
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true
  ok "sysctl 網路參數已寫入（$f）。"
  # 介面層調整
  local iface; iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  if [ -n "${iface:-}" ]; then
    info "調整介面 $iface（txqueuelen / GRO/GSO/TSO / ring buffer）"
    ip link set dev "$iface" txqueuelen 10000 || true
    ensure_pkg ethtool >/dev/null 2>&1 || true
    ethtool -K "$iface" gro on gso on tso on >/dev/null 2>&1 || true
    ethtool -G "$iface" rx 4096 tx 4096 >/dev/null 2>&1 || true
    ok "介面層優化完成。"
  else
    err "找不到預設路由介面，略過介面層調整。"
  fi
}

# ========== 7) Docker 調優 ==========
tune_docker_daemon(){
  info "Docker 調優（daemon.json：MTU/IPv6、default-ulimits nofile、服務 LimitNOFILE）"
  if ! command -v docker >/dev/null 2>&1; then err "找不到 docker 指令，請先安裝 Docker。"; return 1; fi
  ensure_pkg jq || true
  local iface mtu_default mtu_input
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  if [ -n "${iface:-}" ]; then mtu_default=$(ip link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if ($i=="mtu") {print $(i+1); exit}}'); fi
  [ -z "${mtu_default:-}" ] && mtu_default=1500
  read -p "Docker bridge MTU（預設 ${mtu_default}）: " mtu_input
  [ -z "${mtu_input:-}" ] && mtu_input="$mtu_default"
  local enable_ipv6=false cidrv6_default="fd00:dead:beef::/64" cidrv6_input
  read -p "啟用 Docker IPv6? (y/N): " ans
  [[ "$ans" =~ ^[Yy]$ ]] && enable_ipv6=true
  if $enable_ipv6; then
    read -p "fixed-cidr-v6（預設 ${cidrv6_default}）: " cidrv6_input
    [ -z "${cidrv6_input:-}" ] && cidrv6_input="$cidrv6_default"
  fi
  local nofile_default=1048576 dnofile_default=1048576 nofile_input dnofile_input
  read -p "容器 default nofile（預設 ${nofile_default}）: " nofile_input
  [ -z "${nofile_input:-}" ] && nofile_input=$nofile_default
  read -p "Docker 服務 LimitNOFILE（預設 ${dnofile_default}）: " dnofile_input
  [ -z "${dnofile_input:-}" ] && dnofile_input=$dnofile_default
  # 轉送
  ensure_line "net.ipv4.ip_forward = 1" /etc/sysctl.d/99-net-opt.conf
  if $enable_ipv6; then ensure_line "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.d/99-net-opt.conf; fi
  sysctl --system >/dev/null 2>&1 || true
  # systemd drop-in
  mkdir -p /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
LimitNOFILE=${dnofile_input}
EOF
  systemctl daemon-reload || true
  # 更新 daemon.json（保留其他鍵）
  mkdir -p /etc/docker
  [ -f /etc/docker/daemon.json ] && cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s) || true
  local existing; existing=$(cat /etc/docker/daemon.json 2>/dev/null || echo '{}')
  if $enable_ipv6; then
    echo "$existing" | jq \
      --argjson mtu "$mtu_input" \
      --argjson ipv6 true \
      --arg cidrv6 "$cidrv6_input" \
      --argjson nf "$nofile_input" \
      '.mtu=$mtu | .ipv6=true | .ip6tables=true | .["fixed-cidr-v6"]=$cidrv6 |
       .["default-ulimits"].nofile = {"Name":"nofile","Soft":$nofile_input,"Hard":$nofile_input}' \
      >/etc/docker/daemon.json
  else
    echo "$existing" | jq \
      --argjson mtu "$mtu_input" \
      --argjson ipv6 false \
      --argjson nf "$nofile_input" \
      '.mtu=$mtu | .ipv6=false | del(.ip6tables) | del(.["fixed-cidr-v6"]) |
       .["default-ulimits"].nofile = {"Name":"nofile","Soft":$nofile_input,"Hard":$nofile_input}' \
      >/etc/docker/daemon.json
  fi
  # 套用設定（盡量嘗試，不讓腳本卡住）
  systemctl restart docker 2>/dev/null || systemctl --user restart docker 2>/dev/null || pkill -HUP dockerd 2>/dev/null || true
  ok "daemon.json 與 LimitNOFILE 已更新並嘗試重啟 Docker。"
}

# ========== 主選單 ==========
main(){
  echo ""; echo "=== Debian 13 VM 工具（PVE VM + Docker，無 VLAN 版）==="
  echo "1) 設定 root 密碼 + 啟用 SSH（允許 root 密碼登入）"
  echo "2) 配置固定 IP（只輸入最後一碼；自動偵測網段與 gateway）"
  echo "3) 禁用 IPv6（只問一次；sysctl）"
  echo "4) 優化大檔處理（sysctl）"
  echo "5) 擴展硬碟（傳統分割區 + 常見 LVM）"
  echo "6) 優化網路傳輸（BBR/fq、socket buffer、TFO、txqueuelen、GRO/GSO/TSO）"
  echo "7) Docker 調優（daemon.json：MTU/IPv6、default-ulimits nofile、服務 LimitNOFILE）"
  echo "0) 結束"
  while :; do
    read -p "請選擇要執行的項目： " sel
    case "$sel" in
      1) set_root_password_and_ssh ;;
      2) configure_static_ip_last_octet ;;
      3) disable_ipv6_once ;;
      4) optimize_for_large_files ;;
      5) expand_disk ;;
      6) optimize_network_stack ;;
      7) tune_docker_daemon ;;
      0) ok "完成。"; break ;;
      *) err "無效選項。" ;;
    esac
  done
}

main
