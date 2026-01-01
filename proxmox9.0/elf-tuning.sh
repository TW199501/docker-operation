#!/usr/bin/env bash
# Debian 13 VM 工具腳本（Checklist UI 版）
# 規則：勾選 = 執行；不勾選 = 跳過
# 特點：
# - 單一 checklist UI，一次選完要做的項目
# - 依「已設定偵測」預設 OFF，避免你重跑時一直重做
# - 固定 IP：自動取當下介面 / 當下 gateway / 當下 prefix；有現有 IP 時可只輸入最後一碼
# - 持久化調優：CPU governor、sysctl、THP、I/O scheduler/queue、fstrim、irqbalance、DNS、停用服務(mysql除外)

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

# ---- 當次 shell 的檔案上限（非持久化）----
ulimit -n 65536 2>/dev/null || true
ulimit -f unlimited 2>/dev/null || true

# ---- Locale / whiptail 顏色 ----
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"
export NEWT_COLORS='root=white,blue border=white,blue title=white,blue window=white,blue textbox=black,white button=white,blue actbutton=yellow,blue entry=black,white actsellist=white,blue sellist=black,white'

# ========== 可調參數 ==========
DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"
SERVICES_TO_DISABLE=(bluetooth cups apache2)   # mysql 不會被停用

SYSCTL_TUNE_FILE="/etc/sysctl.d/99-elf-tuning.conf"
SYSCTL_TUNE_CONTENT=$(cat <<'EOF'
# ---- ELF baseline tuning ----

# Memory
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
vm.page-cluster=3
vm.min_free_kbytes=65536

# Network buffers (baseline)
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216

# TCP
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3

# Queues
net.core.netdev_max_backlog=5000
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8192
net.netfilter.nf_conntrack_max=131072
EOF
)

IO_TUNE_SCRIPT="/usr/local/sbin/elf-io-tune.sh"
IO_TUNE_SERVICE="/etc/systemd/system/elf-io-tune.service"
NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

GRUB_FILE="/etc/default/grub"

# ========== UI ==========
function header_info {
  clear
  cat <<"EOF"
    ______ _       ______          _____       _      _           ______      _ _
   |  ____| |     |  ____|        |  __ \     (_)    | |         |  ____|    | | |
   | |__  | |     | |__  __ _  ___| |  | | ___ _  ___| |_ _ __   | |__  __  _| | |
   |  __| | |     |  __|/ _` |/ __| |  | |/ _ | |/ __| __| '_ \  |  __| \ \/ / | |
   | |____| |____ | |__| (_| | (__| |__| |  __| | (__| |_| | | | | |____ >  <| | |
   |______|______||______\__,_|\___|_____/ \___|_|\___|\__|_| |_| |______/_/\_\|_| |

            ELF Debian13 All-IN Tools (Checklist UI)
EOF
}

header_info
echo -e "\n Loading...\n"

# ---- root 檢查 ----
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "請以 root 身份運行此腳本"
  echo "使用 sudo 或切換到 root 用戶"
  exit 1
fi

# ---- whiptail 檢查 ----
if ! command -v whiptail >/dev/null 2>&1; then
  echo "[ERROR] 系統缺少 whiptail。請先手動安裝一次："
  echo "  apt-get update && apt-get install -y whiptail"
  exit 1
fi

# ---- 等待 systemd ready ----
echo "等待系統初始化完成..."
for i in {1..30}; do
  if systemctl is-system-running >/dev/null 2>&1; then
    if [ "$(systemctl is-system-running 2>/dev/null || true)" = "running" ]; then
      echo "系統已準備就緒"
      break
    fi
  fi
  echo -n "."
  sleep 2
done
echo ""

YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
function msg_info()    { echo -e "${YW}${BOLD}$1${CL}"; }
function msg_ok()      { echo -e "${GN}${BOLD}$1${CL}"; }
function msg_error()   { echo -e "${RD}${BOLD}$1${CL}"; }
function msg_warning() { echo -e "${YW}${BOLD}$1${CL}"; }

# ========== 基礎工具 ==========
function install_package_if_needed() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y "$pkg"
  fi
}

function backup_file_ts() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  cp -a "$f" "${f}.bak.${ts}"
}

function write_file_if_changed() {
  local path="$1"
  local content="$2"
  if [[ -e "$path" ]]; then
    if diff -q <(printf '%s\n' "$content") "$path" >/dev/null 2>&1; then
      return 0
    fi
    backup_file_ts "$path"
  fi
  install -D -m 0644 /dev/null "$path"
  printf '%s\n' "$content" > "$path"
}

# ========== 狀態偵測（用於 checklist 預設 OFF） ==========
function is_ipv6_disabled() {
  local rt=0 gr=0
  [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" = "1" ]] && rt=1
  [[ -f "$GRUB_FILE" ]] && grep -q "ipv6.disable=1" "$GRUB_FILE" 2>/dev/null && gr=1
  [[ "$rt" = "1" && "$gr" = "1" ]]
}

function is_ssh_configured_root_pw_login() {
  systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1 || return 1
  [[ -f /etc/ssh/sshd_config ]] || return 1
  grep -Eq '^\s*PermitRootLogin\s+yes\b' /etc/ssh/sshd_config || return 1
  grep -Eq '^\s*PasswordAuthentication\s+yes\b' /etc/ssh/sshd_config || return 1
  return 0
}

function is_static_ip_configured_any() {
  local iface
  iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  iface="${iface:-eth0}"

  [[ -f "/etc/systemd/network/10-${iface}.network" ]] && return 0
  if [[ -d /etc/NetworkManager/system-connections ]] && ls /etc/NetworkManager/system-connections/*.nmconnection >/dev/null 2>&1; then
    grep -Rqs "interface-name=${iface}" /etc/NetworkManager/system-connections 2>/dev/null && return 0 || true
  fi
  [[ -f /etc/network/interfaces ]] && grep -Eq "iface\s+${iface}\s+inet\s+static" /etc/network/interfaces 2>/dev/null && return 0
  return 1
}

function is_largefile_tuned() {
  [[ -f /etc/sysctl.d/99-io-tuning.conf ]] || return 1
  grep -Eq '^\s*vm\.dirty_ratio\s*=\s*5\b' /etc/sysctl.d/99-io-tuning.conf || return 1
  grep -Eq '^\s*vm\.dirty_background_ratio\s*=\s*2\b' /etc/sysctl.d/99-io-tuning.conf || return 1
  return 0
}

function is_net_opt_tuned() {
  [[ -f /etc/sysctl.d/99-net-opt.conf ]] || return 1
  grep -Eq '^\s*net\.core\.default_qdisc\s*=\s*fq\b' /etc/sysctl.d/99-net-opt.conf || return 1
  grep -Eq '^\s*net\.ipv4\.tcp_fastopen\s*=\s*3\b' /etc/sysctl.d/99-net-opt.conf || return 1
  return 0
}

function is_persistent_tuning_applied() {
  [[ -f /etc/default/cpufrequtils ]] && grep -q 'GOVERNOR="performance"' /etc/default/cpufrequtils || return 1
  [[ -f "$SYSCTL_TUNE_FILE" ]] || return 1
  systemctl is-enabled irqbalance >/dev/null 2>&1 || return 1
  systemctl is-enabled fstrim.timer >/dev/null 2>&1 || return 1
  systemctl is-enabled elf-io-tune.service >/dev/null 2>&1 || return 1
  [[ -f "$GRUB_FILE" ]] && grep -q "transparent_hugepage=never" "$GRUB_FILE" || return 1
  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved\.service'; then
    [[ -f /etc/systemd/resolved.conf ]] || return 1
    grep -q '^DNS=' /etc/systemd/resolved.conf 2>/dev/null || return 1
  fi
  return 0
}

# ========== 功能：root 密碼 ==========
function set_root_password() {
  while true; do
    ROOT_PASSWORD=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請輸入 root 用戶的新密碼" 10 60 3>&1 1>&2 2>&3) || return
    ROOT_PASSWORD_CONFIRM=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請再次輸入以確認" 10 60 3>&1 1>&2 2>&3) || return
    if [ -z "$ROOT_PASSWORD" ]; then
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "密碼不能為空" 8 50
      continue
    fi
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
      echo "root:$ROOT_PASSWORD" | chpasswd && msg_ok "root 用戶密碼設置成功" && break
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "密碼設置失敗，請再試一次" 8 60
    else
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "兩次輸入不一致，請重試" 8 60
    fi
  done
}

# ========== 功能：SSH ==========
function configure_ssh() {
  msg_info "正在配置 SSH..."
  apt-get update -qq
  apt-get install -y openssh-client openssh-server

  sed -i \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' \
    -e 's/^PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config

  ssh-keygen -A
  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  msg_ok "✓ SSH 配置完成"
}

# ========== 功能：禁用 IPv6 ==========
function disable_ipv6() {
  msg_info "正在關閉 IPv6 功能..."
  echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
  echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true

  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    if grep -q "GRUB_CMDLINE_LINUX=" "$GRUB_FILE"; then
      grep -q "ipv6.disable=1" "$GRUB_FILE" || sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' "$GRUB_FILE"
    else
      echo 'GRUB_CMDLINE_LINUX="ipv6.disable=1"' >> "$GRUB_FILE"
    fi
    command -v update-grub >/dev/null 2>&1 && update-grub >/dev/null 2>&1 || true
    msg_ok "✓ IPv6 功能已禁用（重啟後完全生效）"
  else
    msg_warning "⚠️ 找不到 GRUB 設定檔，僅停用 IPv6(runtime)"
  fi
}

# ========== 工具：prefix -> netmask ==========
function prefix2netmask() {
  local p="$1"
  local mask=""
  local i
  for i in 1 2 3 4; do
    if (( p >= 8 )); then
      mask+="255"
      p=$((p-8))
    else
      local v=$(( 256 - 2**(8-p) ))
      mask+="$v"
      p=0
    fi
    [[ "$i" -lt 4 ]] && mask+="."
  done
  echo "$mask"
}

# ========== 功能：固定 IP（gateway/網段取當下） ==========
function configure_static_ip() {
  # IPv6：在固定 IP 這個步驟內詢問一次（已禁用則預設不動）
  local ipv6_default="OFF"
  is_ipv6_disabled && ipv6_default="OFF" || ipv6_default="OFF"

  if whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP - IPv6" \
    --yesno "是否同時禁用 IPv6？（已禁用則選 NO）" 10 60; then
    disable_ipv6
  fi

  local iface current_cidr current_ip prefix gateway
  iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  iface="${iface:-eth0}"

  current_cidr="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2; exit}')"
  current_ip="${current_cidr%%/*}"
  prefix="${current_cidr##*/}"
  [[ "$current_cidr" = "$current_ip" ]] && prefix="24"

  gateway="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"

  local target_ip=""
  if [[ -n "${current_ip:-}" ]]; then
    local base3 last
    base3="$(echo "$current_ip" | awk -F. '{print $1"."$2"."$3}')"
    last=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" \
      --inputbox "介面：$iface\n目前 IP：$current_ip/$prefix\n請輸入「最後一碼」(1~254)\n\n例如輸入 50 => ${base3}.50" 12 70 "" \
      3>&1 1>&2 2>&3) || return

    if [[ "$last" =~ ^[0-9]{1,3}$ ]] && (( last>=1 && last<=254 )); then
      target_ip="${base3}.${last}"
    else
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "最後一碼格式無效" 8 50
      return 1
    fi
  else
    target_ip=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" \
      --inputbox "找不到目前 IPv4，請輸入完整固定 IP (例如 192.168.25.50)" 10 70 "" \
      3>&1 1>&2 2>&3) || return
  fi

  if [[ -n "${gateway:-}" ]]; then
    if ! whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" --yesno "偵測到目前 Gateway：${gateway}\n是否使用此設定？" 10 60; then
      gateway=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" \
        --inputbox "請輸入 Gateway (例如 192.168.25.254)" 10 70 "" \
        3>&1 1>&2 2>&3) || return
    fi
  else
    gateway=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" \
      --inputbox "偵測不到 default gateway，請手動輸入 (例如 192.168.25.254)" 10 70 "" \
      3>&1 1>&2 2>&3) || return
  fi

  local netmask
  netmask="$(prefix2netmask "$prefix")"

  local dns1 dns
  dns1="$(echo "$DNS_PRIMARY" | awk '{print $1}')"
  dns="${dns1}"

  [[ -f /etc/network/interfaces ]] && cp /etc/network/interfaces /etc/network/interfaces.backup 2>/dev/null || true

  local network_manager=""
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    network_manager="systemd-networkd"
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    network_manager="NetworkManager"
  else
    network_manager="interfaces"
  fi

  msg_info "套用固定 IP：$target_ip/$prefix  GW=$gateway  DNS=$dns  (manager=$network_manager)"

  case "$network_manager" in
    systemd-networkd)
      mkdir -p /etc/systemd/network
      cat > "/etc/systemd/network/10-${iface}.network" <<EOF
[Match]
Name=$iface

[Network]
Address=$target_ip/$prefix
Gateway=$gateway
DNS=$dns
EOF
      systemctl daemon-reload
      systemctl restart systemd-networkd
      ;;
    NetworkManager)
      mkdir -p /etc/NetworkManager/system-connections
      cat > "/etc/NetworkManager/system-connections/${iface}.nmconnection" <<EOF
[connection]
id=$iface
type=ethernet
interface-name=$iface

[ipv4]
method=manual
address1=$target_ip/$prefix,$gateway
dns=$dns;

[ipv6]
method=ignore
EOF
      chmod 600 "/etc/NetworkManager/system-connections/${iface}.nmconnection"
      nmcli connection reload
      nmcli connection up "$iface" || true
      ;;
    interfaces|*)
      cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $iface
iface $iface inet static
    address $target_ip
    netmask $netmask
    gateway $gateway
    dns-nameservers $dns
EOF
      if systemctl is-active --quiet networking 2>/dev/null; then
        systemctl restart networking || true
      elif [ -f /etc/init.d/networking ]; then
        /etc/init.d/networking restart || true
      else
        ip addr flush dev "$iface" || true
        ip addr add "$target_ip/$prefix" dev "$iface" || true
        ip route replace default via "$gateway" dev "$iface" || true
      fi
      ;;
  esac

  sleep 2
  msg_ok "✓ 固定 IP 設定完成（若連線中斷，請透過主控台/VM console 修復）"
}

# ========== 功能：大檔優化 ==========
function optimize_for_large_files() {
  msg_info "正在優化系統以處理大文件..."
  local f=/etc/sysctl.d/99-io-tuning.conf
  mkdir -p /etc/sysctl.d
  cat >"$f" <<'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true
  msg_ok "✓ 大文件處理優化完成"
}

# ========== 功能：擴展硬碟 ==========
function expand_disk() {
  msg_info "正在檢查硬碟空間..."
  apt-get update -qq
  apt-get install -y cloud-guest-utils lvm2 xfsprogs btrfs-progs bc

  local rootdev fstype
  rootdev=$(findmnt -no SOURCE /)
  fstype=$(findmnt -no FSTYPE /)

  msg_info "根設備: $rootdev"
  msg_info "文件系統: $fstype"

  local has_free_space=false

  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local vg_free
    vg_free=$(vgs --noheadings -o vg_free --units G 2>/dev/null | awk '{print $1}' | sed 's/G//' | head -1)
    if [ -n "$vg_free" ] && [ "$(echo "$vg_free > 0" | bc 2>/dev/null)" = "1" ]; then
      has_free_space=true
    fi
  else
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    fi

    if [ -n "${disk:-}" ]; then
      local disk_size part_size
      disk_size=$(lsblk -b -n -o SIZE "$disk" 2>/dev/null | head -1)
      part_size=$(lsblk -b -n -o SIZE "$rootdev" 2>/dev/null)
      if [ -n "$disk_size" ] && [ -n "$part_size" ] && [ "$disk_size" -gt "$part_size" ]; then
        local unused_space=$(( (disk_size - part_size) / 1024 / 1024 / 1024 ))
        if [ "$unused_space" -gt 1 ]; then
          has_free_space=true
        fi
      fi
    fi
  fi

  if [ "$has_free_space" = false ]; then
    msg_ok "✓ 硬碟已經是最大容量，無需擴充"
    df -h / || true
    return 0
  fi

  msg_info "檢測到可用空間，正在擴展硬碟空間..."

  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local lv pv disk part
    lv="$rootdev"
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | awk 'NF{print $1; exit}')
    [[ -n "${pv:-}" ]] || { msg_error "✗ 找不到 PV"; return 1; }

    if [[ "$pv" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$pv" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      msg_error "✗ 無法解析 PV: $pv"
      return 1
    fi

    growpart "$disk" "$part" || { msg_error "✗ growpart 失敗"; return 1; }
    pvresize "$pv" || { msg_error "✗ pvresize 失敗"; return 1; }
    lvextend -r -l +100%FREE "$lv" || { msg_error "✗ lvextend 失敗"; return 1; }
    df -h / || true
    msg_ok "✓ LVM 擴展完成"
  else
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      msg_error "✗ 不支援的根設備: $rootdev"
      return 1
    fi

    growpart "$disk" "$part" || { msg_error "✗ growpart 失敗"; return 1; }
    case "$fstype" in
      ext2|ext3|ext4) resize2fs "$rootdev" ;;
      xfs) xfs_growfs -d / ;;
      btrfs) btrfs filesystem resize max / ;;
      *) msg_error "✗ 不支援的文件系統: $fstype"; return 1 ;;
    esac
    df -h / || true
    msg_ok "✓ 擴展完成"
  fi
}

# ========== 功能：網路傳輸優化 ==========
function optimize_network_stack() {
  msg_info "正在優化網路傳輸參數..."
  local f=/etc/sysctl.d/99-net-opt.conf
  mkdir -p /etc/sysctl.d

  local cc="cubic"
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    cc="bbr"
  fi

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

  local iface
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  if [ -n "${iface:-}" ]; then
    apt-get update -qq
    apt-get install -y ethtool
    ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
    ethtool -K "$iface" gro on gso on tso on >/dev/null 2>&1 || true
    ethtool -G "$iface" rx 4096 tx 4096 >/dev/null 2>&1 || true
  fi
  msg_ok "✓ 網路優化完成"
}

# ========== 功能：guest agent ==========
function install_guest_agent() {
  msg_info "安裝 qemu-guest-agent..."
  install_package_if_needed qemu-guest-agent
  systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
  msg_ok "qemu-guest-agent 安裝完成"
}

# ========== 功能：docker ==========
function install_docker_stack() {
  msg_info "安裝 Docker 引擎與 Compose..."
  install_package_if_needed apt-transport-https
  install_package_if_needed ca-certificates
  install_package_if_needed curl
  install_package_if_needed gnupg
  install_package_if_needed lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io

  curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  systemctl enable --now docker >/dev/null 2>&1 || true
  msg_ok "Docker 與 Compose 安裝完成"

  local mem_kb mem_g docker_mem_g final_mem final_cpu
  mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem_g=$((mem_kb / 1024 / 1024))

  if [ "$mem_g" -gt 2 ]; then docker_mem_g=$((mem_g - 1)); else docker_mem_g=1; fi
  final_mem="${docker_mem_g}G"
  final_cpu="85%"

  mkdir -p /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
MemoryMax=${final_mem}
CPUQuota=${final_cpu}
EOF

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart docker >/dev/null 2>&1 || true
  msg_ok "Docker 資源額度已套用：MemoryMax=${final_mem}, CPUQuota=${final_cpu}"
}

# ========== Log 清理排程 ==========
function cleanup_log_cron() {
  rm -f /usr/local/sbin/elf-log-cleanup.sh /etc/cron.d/elf-log-cleanup
}
function schedule_log_cleanup() {
  local choice
  choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "LOG MAINTENANCE" --menu "選擇 log 清理排程" 12 60 5 \
    "monthly" "每月一次" \
    "quarterly" "每 3 個月一次" \
    "semiannual" "每 6 個月一次" \
    "disable" "停用排程" \
    3>&1 1>&2 2>&3) || return 0

  if [ "$choice" = "disable" ]; then
    cleanup_log_cron
    msg_ok "已停用 log 清理排程"
    return
  fi

  cat >/usr/local/sbin/elf-log-cleanup.sh <<'EOF'
#!/bin/bash
set -e
log_root="/var/log"
find "$log_root" -type f -name "*.log" -size +5M -exec truncate -s 0 {} \; || true
find "$log_root" -type f -name "*.gz" -mtime +30 -delete || true
journalctl --vacuum-time=30d >/dev/null 2>&1 || true
EOF
  chmod +x /usr/local/sbin/elf-log-cleanup.sh

  local cron_expr=""
  case "$choice" in
    monthly) cron_expr="0 3 1 * *" ;;
    quarterly) cron_expr="0 3 1 */3 *" ;;
    semiannual) cron_expr="0 3 1 */6 *" ;;
    *) return 1 ;;
  esac

  cat >/etc/cron.d/elf-log-cleanup <<EOF
$cron_expr root /usr/local/sbin/elf-log-cleanup.sh
EOF
  msg_ok "已設定 $choice 排程"
}

# ========== 持久化性能調優 ==========
function disable_thp_runtime_only() {
  local base="/sys/kernel/mm/transparent_hugepage"
  [[ -d "$base" ]] || return 0
  echo never > "$base/enabled" 2>/dev/null || true
  echo never > "$base/defrag"  2>/dev/null || true
}

function grub_add_param_once() {
  local key="$1"
  local param="$2"
  [[ -f "$GRUB_FILE" ]] || return 0
  grep -qE "^${key}=" "$GRUB_FILE" || echo "${key}=\"\"" >> "$GRUB_FILE"
  local current updated
  current="$(grep -E "^${key}=" "$GRUB_FILE" | head -n1 | sed -E 's/^'"$key"'="(.*)".*/\1/')"
  grep -qw -- "$param" <<<"$current" && return 0
  updated="$(echo "$current $param" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')"
  sed -i -E "s|^${key}=.*|${key}=\"${updated}\"|" "$GRUB_FILE"
}

function set_cpu_governor_performance() {
  install_package_if_needed cpufrequtils
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    echo performance > "$f" 2>/dev/null || true
  done
  write_file_if_changed /etc/default/cpufrequtils 'GOVERNOR="performance"'
  systemctl enable --now cpufrequtils >/dev/null 2>&1 || true
}

function enable_irqbalance_service() {
  install_package_if_needed irqbalance
  systemctl enable --now irqbalance >/dev/null 2>&1 || true
}

function apply_sysctl_baseline() {
  write_file_if_changed "$SYSCTL_TUNE_FILE" "$SYSCTL_TUNE_CONTENT"
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true
}

function ensure_systemd_resolved_dns() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved\.service'; then
    install_package_if_needed systemd-resolved
    local f="/etc/systemd/resolved.conf"
    [[ -f "$f" ]] || touch "$f"
    backup_file_ts "$f"
    grep -qE '^\s*\[Resolve\]\s*$' "$f" || printf '\n[Resolve]\n' >> "$f"

    if grep -qE '^\s*#?\s*DNS=' "$f"; then
      sed -i -E "s|^\s*#?\s*DNS=.*|DNS=${DNS_PRIMARY}|" "$f"
    else
      awk -v dns="DNS=${DNS_PRIMARY}" '{print} /^\[Resolve\]/{print dns}' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    fi

    if grep -qE '^\s*#?\s*FallbackDNS=' "$f"; then
      sed -i -E "s|^\s*#?\s*FallbackDNS=.*|FallbackDNS=${DNS_FALLBACK}|" "$f"
    else
      awk -v fdns="FallbackDNS=${DNS_FALLBACK}" '{print} /^\[Resolve\]/{print fdns}' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    fi

    systemctl enable --now systemd-resolved >/dev/null 2>&1 || true
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
    [[ -e /run/systemd/resolve/stub-resolv.conf ]] && ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
    [[ -e /run/systemd/resolve/resolv.conf ]]      && ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true
  else
    backup_file_ts /etc/resolv.conf || true
    {
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $1}')"
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $2}')"
    } > /etc/resolv.conf
  fi
}

function install_io_tune_boot_service() {
  cat > "$IO_TUNE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

pick_sched() {
  local sched_file="$1"
  local preferred="$2"
  local available
  available="$(cat "$sched_file" 2>/dev/null || true)"
  for s in $preferred; do
    if echo "$available" | grep -Eq "(^|[[:space:]])\[$s\]([[:space:]]|$)|(^|[[:space:]])$s([[:space:]]|$)"; then
      echo "$s"; return 0
    fi
  done
  echo ""
}

tune_one() {
  local dev="$1"
  local base="/sys/block/$dev"
  local sched_file="$base/queue/scheduler"
  local rot_file="$base/queue/rotational"
  [[ -e "$sched_file" ]] || return 0

  local rotational="1"
  [[ -e "$rot_file" ]] && rotational="$(cat "$rot_file" 2>/dev/null || echo 1)"

  local chosen=""
  if [[ "$rotational" = "0" ]]; then
    chosen="$(pick_sched "$sched_file" "none noop mq-deadline deadline kyber bfq")"
  else
    chosen="$(pick_sched "$sched_file" "mq-deadline deadline bfq kyber none noop")"
  fi
  [[ -n "$chosen" ]] && echo "$chosen" > "$sched_file" 2>/dev/null || true

  [[ -e "$base/queue/nr_requests" ]] && echo "$NR_REQUESTS_DEFAULT" > "$base/queue/nr_requests" 2>/dev/null || true
  [[ -e "$base/queue/read_ahead_kb" ]] && echo "$READ_AHEAD_KB_DEFAULT" > "$base/queue/read_ahead_kb" 2>/dev/null || true
}

for d in /sys/block/*; do
  [[ -d "$d" ]] || continue
  dev="$(basename "$d")"
  [[ "$dev" =~ ^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)$ ]] || continue
  tune_one "$dev"
done
exit 0
EOF
  chmod +x "$IO_TUNE_SCRIPT"

  cat > "$IO_TUNE_SERVICE" <<EOF
[Unit]
Description=ELF I/O Tuning (scheduler + queue)
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=$IO_TUNE_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now elf-io-tune.service >/dev/null 2>&1 || true
}

function enable_fstrim_timer() {
  systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
}

function disable_fixed_services_except_mysql() {
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable --now "$s" >/dev/null 2>&1 || true
  done
}

function apply_persistent_tuning_all() {
  msg_info "開始套用：持久化性能調優（含 DNS + 固定停用服務/mysql除外）..."
  apt-get update -qq
  apt-get install -y cpufrequtils irqbalance

  set_cpu_governor_performance
  enable_irqbalance_service
  apply_sysctl_baseline

  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    disable_thp_runtime_only
    grub_add_param_once "GRUB_CMDLINE_LINUX_DEFAULT" "transparent_hugepage=never"
    command -v update-grub >/dev/null 2>&1 && update-grub >/dev/null 2>&1 || true
  else
    disable_thp_runtime_only
  fi

  install_io_tune_boot_service
  enable_fstrim_timer
  ensure_systemd_resolved_dns
  disable_fixed_services_except_mysql

  msg_ok "✓ 持久化調優完成（建議重啟一次讓 GRUB/THP 完整生效）"
}

# ========== Checklist UI ==========
function select_tasks() {
  local opts=()

  # 預設策略：已設定 -> OFF；未設定 -> ON（避免重跑一直重做）
  local guest_status="ON"; systemctl is-enabled qemu-guest-agent >/dev/null 2>&1 && guest_status="OFF"
  local ssh_status="ON";  is_ssh_configured_root_pw_login && ssh_status="OFF"
  local ip_status="ON";   is_static_ip_configured_any && ip_status="OFF"
  local tune_status="ON"; is_persistent_tuning_applied && tune_status="OFF"
  local net_status="ON";  is_net_opt_tuned && net_status="OFF"
  local lf_status="ON";   is_largefile_tuned && lf_status="OFF"

  opts+=("tune"   "持久化性能調優 + DNS + 停用服務(mysql除外)" "$tune_status")
  opts+=("ipdns"  "固定 IP / DNS（取當下 gateway/prefix；可只輸入最後一碼）" "$ip_status")
  opts+=("ssh"    "SSH（允許 root 密碼登入）" "$ssh_status")
  opts+=("guest"  "qemu-guest-agent" "$guest_status")
  opts+=("rootpw" "設定 root 密碼" "OFF")
  opts+=("docker" "Docker / Compose" "OFF")
  opts+=("large"  "大文件 I/O 優化（dirty_ratio 等）" "$lf_status")
  opts+=("expand" "擴展硬碟（含 LVM）" "OFF")
  opts+=("net"    "網路傳輸優化（BBR/fq 等）" "$net_status")
  opts+=("log"    "Log 定期清理排程" "OFF")

  whiptail --backtitle "ELF Debian13 ALL IN" \
    --title "選擇要執行的項目（空白鍵勾選；Enter 執行）" \
    --checklist "勾選 = 執行；不勾選 = 跳過" 22 90 12 \
    "${opts[@]}" 3>&1 1>&2 2>&3
}

function run_selected_tasks() {
  local chosen="$1"

  [[ "$chosen" == *"tune"*   ]] && apply_persistent_tuning_all
  [[ "$chosen" == *"ipdns"*  ]] && configure_static_ip
  [[ "$chosen" == *"ssh"*    ]] && configure_ssh
  [[ "$chosen" == *"guest"*  ]] && install_guest_agent
  [[ "$chosen" == *"rootpw"* ]] && set_root_password
  [[ "$chosen" == *"docker"* ]] && install_docker_stack
  [[ "$chosen" == *"large"*  ]] && optimize_for_large_files
  [[ "$chosen" == *"expand"* ]] && expand_disk
  [[ "$chosen" == *"net"*    ]] && optimize_network_stack
  [[ "$chosen" == *"log"*    ]] && schedule_log_cleanup
}

# ========== Main ==========
chosen="$(select_tasks)" || exit 0

# 顯示摘要確認
if ! whiptail --backtitle "ELF Debian13 ALL IN" --title "確認" \
  --yesno "即將執行以下項目：\n\n$chosen\n\n確定開始？" 14 70; then
  exit 0
fi

run_selected_tasks "$chosen"

whiptail --backtitle "ELF Debian13 ALL IN" --title "完成" --msgbox \
"已完成你勾選的項目。\n\n若有套用持久化調優（GRUB/THP），建議重啟一次讓設定完整生效。" 10 70
