#!/usr/bin/env bash
# Debian 13 VM 工具腳本（Checklist UI 版 / 適合上傳 GitHub）
#
# 規則：
#   - 「勾選」= 執行 / 安裝；「不勾選」= 跳過
#   - 每個項目預設：已設定 -> OFF；未設定 -> ON（避免重跑一直重做）
#
# 內容：
#   1) 持久化性能調優：CPU governor / sysctl / THP / I/O scheduler+queue / fstrim / irqbalance / DNS / 停用服務(mysql除外)
#   2) 固定 IP / DNS：自動取當下 iface / gateway / prefix；有現有 IP 時可只輸入最後一碼
#   3) SSH：允許 root 密碼登入
#   4) qemu-guest-agent
#   5) root 密碼
#   6) Docker / Compose
#   7) 大檔 I/O 調優（dirty_ratio 等）
#   8) 擴展硬碟（含 LVM）
#   9) 網路傳輸優化（BBR/fq 等）
#  10) Log 清理排程
#
# Log：
#   - 執行細節寫到 /var/log/elf-tools.log
#
# 注意：
#   - 本腳本需要互動式 TTY（因為使用 whiptail）
#   - 若系統未安裝 whiptail，請先手動：
#       apt-get update && apt-get install -y whiptail

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# -------- 一次性 ulimit（不持久化）--------
ulimit -n 65536 2>/dev/null || true
ulimit -f unlimited 2>/dev/null || true

# -------- Locale / whiptail 顏色 --------
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}"
export NEWT_COLORS='root=white,blue border=white,blue title=white,blue window=white,blue textbox=black,white button=white,blue actbutton=yellow,blue entry=black,white actsellist=white,blue sellist=black,white'

# ================= 可調參數 =================
LOG_FILE="/var/log/elf-tools.log"

DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"

# mysql 除外：不要放 mysql/mariadb 相關 service 在這裡
SERVICES_TO_DISABLE=(bluetooth cups apache2)

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
GRUB_FILE="/etc/default/grub"

# ================= UI / util =================
header_info() {
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

YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
msg_info()    { echo -e "${YW}${BOLD}$1${CL}"; }
msg_ok()      { echo -e "${GN}${BOLD}$1${CL}"; }
msg_error()   { echo -e "${RD}${BOLD}$1${CL}"; }
msg_warning() { echo -e "${YW}${BOLD}$1${CL}"; }

ensure_log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
}

log_block() {
  ensure_log
  {
    echo
    echo "=================================================="
    echo "[$(date '+%F %T')] $1"
    echo "=================================================="
  } >>"$LOG_FILE" 2>&1
}

install_package_if_needed() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get update -qq >>"$LOG_FILE" 2>&1 || true
    apt-get install -y "$pkg" >>"$LOG_FILE" 2>&1
  fi
}

backup_file_ts() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  cp -a "$f" "${f}.bak.${ts}" >>"$LOG_FILE" 2>&1 || true
}

write_file_if_changed() {
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

# 讓 checklist 的「執行」不會把畫面跳回 shell：所有 stdout/stderr 都寫 log
run_one() {
  local tag="$1"; shift
  local desc="$1"; shift

  whiptail --backtitle "ELF Debian13 ALL IN" --title "執行中" \
    --infobox "正在執行：${desc}\n\nLog：${LOG_FILE}\n\n請稍候..." 12 70

  log_block "START [$tag] $desc"

  set +e
  "$@" >>"$LOG_FILE" 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    log_block "FAIL  [$tag] rc=$rc"
    whiptail --backtitle "ELF Debian13 ALL IN" --title "失敗" \
      --msgbox "執行失敗：${desc}\n\nexit code：${rc}\n\n請看 log：${LOG_FILE}" 12 70
    return "$rc"
  fi

  log_block "OK    [$tag]"
  return 0
}

selected() {
  local chosen="$1"
  local key="$2"
  echo "$chosen" | grep -qw "$key"
}

# ================= 狀態偵測（預設 OFF 用） =================
is_ipv6_disabled() {
  local rt=0 gr=0
  [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" = "1" ]] && rt=1
  [[ -f "$GRUB_FILE" ]] && grep -q "ipv6.disable=1" "$GRUB_FILE" 2>/dev/null && gr=1
  [[ "$rt" = "1" && "$gr" = "1" ]]
}

is_ssh_configured_root_pw_login() {
  systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1 || return 1
  [[ -f /etc/ssh/sshd_config ]] || return 1
  grep -Eq '^\s*PermitRootLogin\s+yes\b' /etc/ssh/sshd_config || return 1
  grep -Eq '^\s*PasswordAuthentication\s+yes\b' /etc/ssh/sshd_config || return 1
  return 0
}

is_static_ip_configured_any() {
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

is_largefile_tuned() {
  [[ -f /etc/sysctl.d/99-io-tuning.conf ]] || return 1
  grep -Eq '^\s*vm\.dirty_ratio\s*=\s*5\b' /etc/sysctl.d/99-io-tuning.conf || return 1
  grep -Eq '^\s*vm\.dirty_background_ratio\s*=\s*2\b' /etc/sysctl.d/99-io-tuning.conf || return 1
  return 0
}

is_net_opt_tuned() {
  [[ -f /etc/sysctl.d/99-net-opt.conf ]] || return 1
  grep -Eq '^\s*net\.core\.default_qdisc\s*=\s*fq\b' /etc/sysctl.d/99-net-opt.conf || return 1
  grep -Eq '^\s*net\.ipv4\.tcp_fastopen\s*=\s*3\b' /etc/sysctl.d/99-net-opt.conf || return 1
  return 0
}

is_persistent_tuning_applied() {
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

# ================= 功能：root 密碼 =================
set_root_password() {
  while true; do
    local p1 p2
    p1=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請輸入 root 用戶的新密碼" 10 60 3>&1 1>&2 2>&3) || return 0
    p2=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請再次輸入以確認" 10 60 3>&1 1>&2 2>&3) || return 0
    if [ -z "$p1" ]; then
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "密碼不能為空" 8 50
      continue
    fi
    if [ "$p1" != "$p2" ]; then
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "兩次輸入不一致，請重試" 8 60
      continue
    fi
    echo "root:$p1" | chpasswd >>"$LOG_FILE" 2>&1 && return 0
  done
}

# ================= 功能：SSH =================
configure_ssh() {
  install_package_if_needed openssh-client
  install_package_if_needed openssh-server

  sed -i \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' \
    -e 's/^PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config

  ssh-keygen -A >>"$LOG_FILE" 2>&1 || true
  systemctl restart sshd >>"$LOG_FILE" 2>&1 || systemctl restart ssh >>"$LOG_FILE" 2>&1 || true
}

# ================= 功能：禁用 IPv6 =================
disable_ipv6() {
  echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
  echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true

  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    if grep -q "GRUB_CMDLINE_LINUX=" "$GRUB_FILE"; then
      grep -q "ipv6.disable=1" "$GRUB_FILE" || sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' "$GRUB_FILE"
    else
      echo 'GRUB_CMDLINE_LINUX="ipv6.disable=1"' >> "$GRUB_FILE"
    fi
    command -v update-grub >/dev/null 2>&1 && update-grub >>"$LOG_FILE" 2>&1 || true
  fi
}

# ================= 工具：prefix -> netmask =================
prefix2netmask() {
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

# ================= 功能：固定 IP / DNS =================
configure_static_ip() {
  # 只問一次：是否禁用 IPv6
  local ipv6_prompt="是否同時禁用 IPv6？\n\n目前狀態："
  if is_ipv6_disabled; then
    ipv6_prompt+="已禁用\n\n建議：選 NO（除非你想重新套一次）"
  else
    ipv6_prompt+="未禁用\n\n建議：選 YES（若你確定不需要 IPv6）"
  fi
  if whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP - IPv6" \
    --yesno "$ipv6_prompt" 14 70; then
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
      --inputbox "介面：$iface\n目前 IP：$current_ip/$prefix\n\n請輸入「最後一碼」(1~254)\n例如輸入 50 => ${base3}.50" 13 75 "" \
      3>&1 1>&2 2>&3) || return 0

    if [[ "$last" =~ ^[0-9]{1,3}$ ]] && (( last>=1 && last<=254 )); then
      target_ip="${base3}.${last}"
    else
      whiptail --backtitle "ELF Debian13 ALL IN" --title "錯誤" --msgbox "最後一碼格式無效" 8 50
      return 1
    fi
  else
    target_ip=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" \
      --inputbox "找不到目前 IPv4，請輸入完整固定 IP (例如 192.168.25.50)" 10 75 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  if [[ -n "${gateway:-}" ]]; then
    if ! whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" \
      --yesno "偵測到目前 Gateway：${gateway}\n\n是否使用此設定？" 12 70; then
      gateway=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" \
        --inputbox "請輸入 Gateway (例如 192.168.25.254)" 10 75 "" \
        3>&1 1>&2 2>&3) || return 0
    fi
  else
    gateway=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Gateway" \
      --inputbox "偵測不到 default gateway，請手動輸入 (例如 192.168.25.254)" 10 75 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  local netmask
  netmask="$(prefix2netmask "$prefix")"

  local dns1 dns
  dns1="$(echo "$DNS_PRIMARY" | awk '{print $1}')"
  dns="${dns1}"

  [[ -f /etc/network/interfaces ]] && cp /etc/network/interfaces /etc/network/interfaces.backup >>"$LOG_FILE" 2>&1 || true

  local network_manager=""
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    network_manager="systemd-networkd"
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    network_manager="NetworkManager"
  else
    network_manager="interfaces"
  fi

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
      systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
      systemctl restart systemd-networkd >>"$LOG_FILE" 2>&1 || true
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
      nmcli connection reload >>"$LOG_FILE" 2>&1 || true
      nmcli connection up "$iface" >>"$LOG_FILE" 2>&1 || true
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
        systemctl restart networking >>"$LOG_FILE" 2>&1 || true
      elif [ -f /etc/init.d/networking ]; then
        /etc/init.d/networking restart >>"$LOG_FILE" 2>&1 || true
      else
        ip addr flush dev "$iface" >>"$LOG_FILE" 2>&1 || true
        ip addr add "$target_ip/$prefix" dev "$iface" >>"$LOG_FILE" 2>&1 || true
        ip route replace default via "$gateway" dev "$iface" >>"$LOG_FILE" 2>&1 || true
      fi
      ;;
  esac
}

# ================= 功能：大檔 I/O 調優 =================
optimize_for_large_files() {
  local f=/etc/sysctl.d/99-io-tuning.conf
  mkdir -p /etc/sysctl.d
  cat >"$f" <<'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF
  sysctl --system >>"$LOG_FILE" 2>&1 || sysctl -p >>"$LOG_FILE" 2>&1 || true
}

# ================= 功能：擴展硬碟（含 LVM） =================
expand_disk() {
  install_package_if_needed cloud-guest-utils
  install_package_if_needed lvm2
  install_package_if_needed xfsprogs
  install_package_if_needed btrfs-progs
  install_package_if_needed bc

  local rootdev fstype
  rootdev=$(findmnt -no SOURCE /)
  fstype=$(findmnt -no FSTYPE /)

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
    return 0
  fi

  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local lv pv disk part
    lv="$rootdev"
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | awk 'NF{print $1; exit}')
    [[ -n "${pv:-}" ]] || return 1

    if [[ "$pv" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$pv" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      return 1
    fi

    growpart "$disk" "$part" >>"$LOG_FILE" 2>&1
    pvresize "$pv" >>"$LOG_FILE" 2>&1
    lvextend -r -l +100%FREE "$lv" >>"$LOG_FILE" 2>&1
  else
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      return 1
    fi

    growpart "$disk" "$part" >>"$LOG_FILE" 2>&1
    case "$fstype" in
      ext2|ext3|ext4) resize2fs "$rootdev" >>"$LOG_FILE" 2>&1 ;;
      xfs) xfs_growfs -d / >>"$LOG_FILE" 2>&1 ;;
      btrfs) btrfs filesystem resize max / >>"$LOG_FILE" 2>&1 ;;
      *) return 1 ;;
    esac
  fi
}

# ================= 功能：網路傳輸優化 =================
optimize_network_stack() {
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

  sysctl --system >>"$LOG_FILE" 2>&1 || sysctl -p >>"$LOG_FILE" 2>&1 || true

  local iface
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  if [ -n "${iface:-}" ]; then
    install_package_if_needed ethtool
    ip link set dev "$iface" txqueuelen 10000 >>"$LOG_FILE" 2>&1 || true
    ethtool -K "$iface" gro on gso on tso on >>"$LOG_FILE" 2>&1 || true
    ethtool -G "$iface" rx 4096 tx 4096 >>"$LOG_FILE" 2>&1 || true
  fi
}

# ================= 功能：qemu-guest-agent =================
install_guest_agent() {
  install_package_if_needed qemu-guest-agent
  systemctl enable --now qemu-guest-agent >>"$LOG_FILE" 2>&1 || true
}

# ================= 功能：Docker / Compose =================
install_docker_stack() {
  install_package_if_needed apt-transport-https
  install_package_if_needed ca-certificates
  install_package_if_needed curl
  install_package_if_needed gnupg
  install_package_if_needed lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >>"$LOG_FILE" 2>&1 || true

  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list

  apt-get update -qq >>"$LOG_FILE" 2>&1 || true
  apt-get install -y docker-ce docker-ce-cli containerd.io >>"$LOG_FILE" 2>&1

  curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose >>"$LOG_FILE" 2>&1
  chmod +x /usr/local/bin/docker-compose

  systemctl enable --now docker >>"$LOG_FILE" 2>&1 || true

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

  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  systemctl restart docker >>"$LOG_FILE" 2>&1 || true
}

# ================= 功能：Log 清理排程 =================
cleanup_log_cron() {
  rm -f /usr/local/sbin/elf-log-cleanup.sh /etc/cron.d/elf-log-cleanup >>"$LOG_FILE" 2>&1 || true
}

schedule_log_cleanup() {
  local choice
  choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "LOG MAINTENANCE" --menu "選擇 log 清理排程" 12 60 5 \
    "monthly" "每月一次" \
    "quarterly" "每 3 個月一次" \
    "semiannual" "每 6 個月一次" \
    "disable" "停用排程" \
    3>&1 1>&2 2>&3) || return 0

  if [ "$choice" = "disable" ]; then
    cleanup_log_cron
    return 0
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
}

# ================= 功能：持久化性能調優（核心） =================
disable_thp_runtime_only() {
  local base="/sys/kernel/mm/transparent_hugepage"
  [[ -d "$base" ]] || return 0
  echo never > "$base/enabled" 2>/dev/null || true
  echo never > "$base/defrag"  2>/dev/null || true
}

grub_add_param_once() {
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

set_cpu_governor_performance() {
  install_package_if_needed cpufrequtils
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    echo performance > "$f" 2>/dev/null || true
  done
  write_file_if_changed /etc/default/cpufrequtils 'GOVERNOR="performance"'
  systemctl enable --now cpufrequtils >>"$LOG_FILE" 2>&1 || true
}

enable_irqbalance_service() {
  install_package_if_needed irqbalance
  systemctl enable --now irqbalance >>"$LOG_FILE" 2>&1 || true
}

apply_sysctl_baseline() {
  write_file_if_changed "$SYSCTL_TUNE_FILE" "$SYSCTL_TUNE_CONTENT"
  sysctl --system >>"$LOG_FILE" 2>&1 || sysctl -p >>"$LOG_FILE" 2>&1 || true
}

ensure_systemd_resolved_dns() {
  # 如果有 systemd-resolved，就用 resolved.conf；否則直接寫 /etc/resolv.conf
  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved\.service'; then
    # Debian 可能未啟用 resolved，但 package 通常存在；這裡保守：安裝需要時才安裝
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

    systemctl enable --now systemd-resolved >>"$LOG_FILE" 2>&1 || true
    systemctl restart systemd-resolved >>"$LOG_FILE" 2>&1 || true

    # Debian 的 resolv.conf 常見是 stub-resolv.conf
    if [[ -e /run/systemd/resolve/stub-resolv.conf ]]; then
      ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    elif [[ -e /run/systemd/resolve/resolv.conf ]]; then
      ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    fi
  else
    backup_file_ts /etc/resolv.conf || true
    {
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $1}')"
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $2}')"
    } > /etc/resolv.conf
  fi
}

install_io_tune_boot_service() {
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

  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  systemctl enable --now elf-io-tune.service >>"$LOG_FILE" 2>&1 || true
}

enable_fstrim_timer() {
  systemctl enable --now fstrim.timer >>"$LOG_FILE" 2>&1 || true
}

disable_fixed_services_except_mysql() {
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable --now "$s" >>"$LOG_FILE" 2>&1 || true
  done
}

apply_persistent_tuning_all() {
  # 1) CPU governor
  set_cpu_governor_performance

  # 2) irqbalance
  enable_irqbalance_service

  # 3) sysctl baseline
  apply_sysctl_baseline

  # 4) THP：runtime + grub
  disable_thp_runtime_only
  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    grub_add_param_once "GRUB_CMDLINE_LINUX_DEFAULT" "transparent_hugepage=never"
    command -v update-grub >/dev/null 2>&1 && update-grub >>"$LOG_FILE" 2>&1 || true
  fi

  # 5) I/O tuning service (boot apply)
  install_io_tune_boot_service

  # 6) fstrim
  enable_fstrim_timer

  # 7) DNS（你要求一定要做）
  ensure_systemd_resolved_dns

  # 8) disable services (mysql 제외)
  disable_fixed_services_except_mysql
}

# ================= Checklist UI =================
select_tasks() {
  local guest_status="ON"; systemctl is-enabled qemu-guest-agent >/dev/null 2>&1 && guest_status="OFF"
  local ssh_status="ON";  is_ssh_configured_root_pw_login && ssh_status="OFF"
  local ip_status="ON";   is_static_ip_configured_any && ip_status="OFF"
  local tune_status="ON"; is_persistent_tuning_applied && tune_status="OFF"
  local net_status="ON";  is_net_opt_tuned && net_status="OFF"
  local lf_status="ON";   is_largefile_tuned && lf_status="OFF"
  local log_status="ON";  [[ -f /etc/cron.d/elf-log-cleanup ]] && log_status="OFF"

  local opts=(
    "tune"   "持久化性能調優 + DNS + 停用服務(mysql除外)" "$tune_status"
    "ipdns"  "固定 IP / DNS（取當下 gateway/prefix；可只輸入最後一碼）" "$ip_status"
    "ssh"    "SSH（允許 root 密碼登入）" "$ssh_status"
    "guest"  "qemu-guest-agent" "$guest_status"
    "rootpw" "設定 root 密碼" "OFF"
    "docker" "Docker / Compose" "OFF"
    "large"  "大文件 I/O 優化（dirty_ratio 等）" "$lf_status"
    "expand" "擴展硬碟（含 LVM）" "OFF"
    "net"    "網路傳輸優化（BBR/fq 等）" "$net_status"
    "log"    "Log 定期清理排程" "$log_status"
  )

  whiptail --backtitle "ELF Debian13 ALL IN" \
    --title "選擇要執行的項目（空白鍵勾選；Enter 執行）" \
    --checklist "勾選 = 執行；不勾選 = 跳過" 22 92 12 \
    "${opts[@]}" 3>&1 1>&2 2>&3
}

run_selected_tasks() {
  local chosen="$1"

  selected "$chosen" "tune"   && run_one "tune"   "持久化性能調優 + DNS + 停用服務(mysql除外)" apply_persistent_tuning_all
  selected "$chosen" "ipdns"  && run_one "ipdns"  "固定 IP / DNS（取當下 gateway/prefix）"       configure_static_ip
  selected "$chosen" "ssh"    && run_one "ssh"    "SSH（允許 root 密碼登入）"                    configure_ssh
  selected "$chosen" "guest"  && run_one "guest"  "qemu-guest-agent"                             install_guest_agent
  selected "$chosen" "rootpw" && run_one "rootpw" "設定 root 密碼"                                set_root_password
  selected "$chosen" "docker" && run_one "docker" "Docker / Compose"                              install_docker_stack
  selected "$chosen" "large"  && run_one "large"  "大文件 I/O 優化"                                optimize_for_large_files
  selected "$chosen" "expand" && run_one "expand" "擴展硬碟（含 LVM）"                             expand_disk
  selected "$chosen" "net"    && run_one "net"    "網路傳輸優化（BBR/fq 等）"                      optimize_network_stack
  selected "$chosen" "log"    && run_one "log"    "Log 定期清理排程"                               schedule_log_cleanup
}

# ================= Main =================
header_info
ensure_log
log_block "SCRIPT START"

# root 檢查
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "請以 root 身份運行此腳本"
  exit 1
fi

# TTY 檢查（沒有 TTY，whiptail 很容易「看似跳出」）
if ! [ -t 0 ] || ! [ -t 1 ]; then
  echo "[ERROR] 偵測到非互動式環境（沒有 TTY），無法顯示 UI。"
  echo "請用：sudo -i ; bash script.sh"
  echo "或 SSH：ssh -t user@host 'sudo -i bash script.sh'"
  exit 1
fi

# whiptail 檢查
if ! command -v whiptail >/dev/null 2>&1; then
  echo "[ERROR] 缺少 whiptail。請先執行：apt-get update && apt-get install -y whiptail"
  exit 1
fi

# 等待 systemd ready（接受 running 或 degraded）
echo "等待系統初始化完成..."
for i in {1..30}; do
  st="$(systemctl is-system-running 2>/dev/null || true)"
  if [[ "$st" = "running" || "$st" = "degraded" ]]; then
    echo "系統已準備就緒（$st）"
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

# Checklist + 可返回重選
while true; do
  if ! chosen="$(select_tasks)"; then
    # Cancel/ESC：正常退出
    log_block "USER CANCELLED"
    exit 0
  fi

  if [[ -z "${chosen// }" ]]; then
    whiptail --backtitle "ELF Debian13 ALL IN" --title "提示" \
      --msgbox "你沒有勾選任何項目。\n\n請至少勾選一個項目，或按 Cancel 離開。" 10 60
    continue
  fi

  if whiptail --backtitle "ELF Debian13 ALL IN" --title "確認" \
    --yesno "即將執行以下項目：\n\n$chosen\n\n確定開始？\n\n選 No 可返回重新勾選。" 16 84; then
    break
  fi
done

run_selected_tasks "$chosen"

whiptail --backtitle "ELF Debian13 ALL IN" --title "完成" --msgbox \
"已完成你勾選的項目。\n\nLog：${LOG_FILE}\n\n若你有套用：持久化調優（GRUB/THP），建議重啟一次讓設定完整生效。" 12 78

log_block "SCRIPT END"
exit 0
