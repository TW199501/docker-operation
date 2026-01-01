#!/usr/bin/env bash
# ELF Debian 13 VM 全功能工具（整合版 / 中文選項 / 勾選執行 / 全程寫入 Log）
# - UI：whiptail checklist（勾選=執行；未勾選=跳過）
# - Log：/var/log/elf-tools.log（所有 apt/systemctl/命令輸出都進 log，不打爆 UI）
# - 修正：PATH 補齊 /usr/sbin /sbin，避免 sysctl / update-grub / ethtool 找不到
# - 重要：固定停用服務不包含 mysql（永遠不動 mysql）
# - DNS：只要你勾「持久化效能調優」，就一定會套 DNS
#
# 建議檔名：elf-debian13-allin.sh

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -u
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LOG_FILE="/var/log/elf-tools.log"

# ===== 可調參數 =====
DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"
SERVICES_TO_DISABLE=(bluetooth cups apache2)   # mysql 永遠不動

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

# ===== Helper =====
ensure_log() { mkdir -p "$(dirname "$LOG_FILE")"; touch "$LOG_FILE" 2>/dev/null || true; }
log() { ensure_log; echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"; }

run_quiet() { "$@" >>"$LOG_FILE" 2>&1; return $?; }

require_root_tty() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[ERROR] 請用 root 執行（sudo -i）"
    exit 1
  fi
  if ! [ -t 0 ] || ! [ -t 1 ]; then
    echo "[ERROR] 未偵測到 TTY，無法使用 whiptail UI"
    exit 1
  fi
}

install_pkg() {
  local pkg="$1"
  dpkg -s "$pkg" >/dev/null 2>&1 && return 0
  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y "$pkg"
}

backup_file_ts() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d_%H%M%S)"
  run_quiet cp -a "$f" "${f}.bak.${ts}" || true
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
  install -D -m 0644 /dev/null "$path" >>"$LOG_FILE" 2>&1 || true
  printf '%s\n' "$content" >"$path"
}

unit_exists() {
  local name="$1"
  systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${name}.service"
}

ui_msg() { whiptail --backtitle "ELF Debian13 全功能工具" --title "$1" --msgbox "$2" 12 78; }
ui_info() { whiptail --backtitle "ELF Debian13 全功能工具" --title "$1" --infobox "$2" 12 78; }

safe_step() {
  local title="$1"; shift
  local desc="$1"; shift
  ui_info "$title" "$desc\n\n請稍候...\nLog：$LOG_FILE"
  log "START: $title - $desc"
  if run_quiet "$@"; then
    log "OK: $title"
    return 0
  else
    local rc=$?
    log "FAIL: $title rc=$rc"
    ui_msg "執行失敗" "$title 執行失敗（rc=$rc）。\n\n請看 Log：\n$LOG_FILE"
    return $rc
  fi
}

wait_system_ready() {
  ui_info "等待系統就緒" "正在等待 systemd 就緒...\n（running 或 degraded 都算可繼續）"
  for i in {1..30}; do
    local st
    st="$(systemctl is-system-running 2>/dev/null || true)"
    if [[ "$st" = "running" || "$st" = "degraded" ]]; then
      return 0
    fi
    sleep 2
  done
  # 不強制失敗，直接繼續（避免你說的「等待就緒就結束」）
  return 0
}

# ===== 功能：ROOT 密碼 =====
set_root_password() {
  local p1 p2
  while true; do
    p1=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "ROOT 密碼" --passwordbox "請輸入 root 新密碼" 10 60 3>&1 1>&2 2>&3) || return 0
    p2=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "ROOT 密碼" --passwordbox "請再次輸入以確認" 10 60 3>&1 1>&2 2>&3) || return 0
    [[ -n "$p1" ]] || { ui_msg "輸入錯誤" "密碼不能為空"; continue; }
    [[ "$p1" = "$p2" ]] || { ui_msg "輸入錯誤" "兩次輸入不一致"; continue; }
    echo "root:$p1" | chpasswd >>"$LOG_FILE" 2>&1 || return 1
    return 0
  done
}

# ===== 功能：SSH（允許 root 密碼登入）=====
configure_ssh() {
  install_pkg openssh-server || true
  install_pkg openssh-client || true

  [[ -f /etc/ssh/sshd_config ]] || return 1
  backup_file_ts /etc/ssh/sshd_config

  sed -i \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' \
    -e 's/^PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config

  run_quiet ssh-keygen -A || true
  run_quiet systemctl restart sshd || run_quiet systemctl restart ssh || true
  run_quiet systemctl enable sshd || run_quiet systemctl enable ssh || true
  return 0
}

# ===== 功能：禁用 IPv6（runtime + grub 持久化）=====
disable_ipv6() {
  echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
  echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true

  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    if grep -q "GRUB_CMDLINE_LINUX=" "$GRUB_FILE"; then
      grep -q "ipv6.disable=1" "$GRUB_FILE" || sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' "$GRUB_FILE"
    else
      echo 'GRUB_CMDLINE_LINUX="ipv6.disable=1"' >>"$GRUB_FILE"
    fi

    if ! command -v update-grub >/dev/null 2>&1; then
      install_pkg grub2-common || true
    fi
    run_quiet update-grub || true
  fi
  return 0
}

# ===== 工具：prefix -> netmask =====
prefix2netmask() {
  local p="$1" mask="" i
  for i in 1 2 3 4; do
    if (( p >= 8 )); then
      mask+="255"; p=$((p-8))
    else
      local v=$(( 256 - 2**(8-p) ))
      mask+="$v"; p=0
    fi
    [[ "$i" -lt 4 ]] && mask+="."
  done
  echo "$mask"
}

# ===== 功能：固定 IP（自動取當下 iface/gateway/prefix；可只輸入最後一碼）=====
configure_static_ip() {
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
    last=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "固定 IP" \
      --inputbox "介面：$iface\n目前：$current_ip/$prefix\n\n請輸入最後一碼（1~254）\n例如 50 => ${base3}.50" 13 72 "" \
      3>&1 1>&2 2>&3) || return 0
    [[ "$last" =~ ^[0-9]{1,3}$ ]] && (( last>=1 && last<=254 )) || return 1
    target_ip="${base3}.${last}"
  else
    target_ip=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "固定 IP" \
      --inputbox "偵測不到目前 IPv4，請輸入完整固定 IP（例如 192.168.25.50）" 10 72 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  if [[ -n "${gateway:-}" ]]; then
    if ! whiptail --backtitle "ELF Debian13 全功能工具" --title "Gateway" --yesno "偵測到目前 Gateway：$gateway\n是否使用？" 10 60; then
      gateway=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "Gateway" \
        --inputbox "請輸入 Gateway（例如 192.168.25.254）" 10 72 "" \
        3>&1 1>&2 2>&3) || return 0
    fi
  else
    gateway=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "Gateway" \
      --inputbox "偵測不到 default gateway，請輸入（例如 192.168.25.254）" 10 72 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  local netmask; netmask="$(prefix2netmask "$prefix")"
  local dns; dns="$(echo "$DNS_PRIMARY" | awk '{print $1}')"

  local nm=""
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    nm="systemd-networkd"
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    nm="NetworkManager"
  else
    nm="interfaces"
  fi

  log "StaticIP apply: iface=$iface ip=$target_ip/$prefix gw=$gateway dns=$dns manager=$nm"

  case "$nm" in
    systemd-networkd)
      mkdir -p /etc/systemd/network
      cat >"/etc/systemd/network/10-${iface}.network" <<EOF
[Match]
Name=$iface
[Network]
Address=$target_ip/$prefix
Gateway=$gateway
DNS=$dns
EOF
      run_quiet systemctl daemon-reload || true
      run_quiet systemctl restart systemd-networkd || true
      ;;
    NetworkManager)
      mkdir -p /etc/NetworkManager/system-connections
      cat >"/etc/NetworkManager/system-connections/${iface}.nmconnection" <<EOF
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
      run_quiet nmcli connection reload || true
      run_quiet nmcli connection up "$iface" || true
      ;;
    *)
      backup_file_ts /etc/network/interfaces || true
      cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $iface
iface $iface inet static
    address $target_ip
    netmask $netmask
    gateway $gateway
    dns-nameservers $dns
EOF
      run_quiet systemctl restart networking || true
      ;;
  esac

  return 0
}

# ===== 功能：大檔 I/O sysctl =====
optimize_large_file_io() {
  install_pkg procps || true
  local f="/etc/sysctl.d/99-io-tuning.conf"
  mkdir -p /etc/sysctl.d
  cat >"$f" <<'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF
  run_quiet sysctl --system || run_quiet sysctl -p || true
  return 0
}

# ===== 功能：擴展硬碟（支援 LVM 與一般分割）=====
expand_disk() {
  install_pkg procps || true
  install_pkg cloud-guest-utils || true
  install_pkg lvm2 || true
  install_pkg xfsprogs || true
  install_pkg btrfs-progs || true
  install_pkg bc || true

  local rootdev fstype
  rootdev="$(findmnt -no SOURCE /)"
  fstype="$(findmnt -no FSTYPE /)"
  log "Disk expand: rootdev=$rootdev fstype=$fstype"

  # 判斷是否有可擴充空間
  local has_free=false
  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local vg_free
    vg_free=$(vgs --noheadings -o vg_free --units G 2>/dev/null | awk '{print $1}' | sed 's/G//' | head -1)
    if [ -n "${vg_free:-}" ] && [ "$(echo "$vg_free > 0" | bc 2>/dev/null)" = "1" ]; then
      has_free=true
    fi
  else
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      return 1
    fi

    local disk_size part_size
    disk_size=$(lsblk -b -n -o SIZE "$disk" 2>/dev/null | head -1)
    part_size=$(lsblk -b -n -o SIZE "$rootdev" 2>/dev/null | head -1)
    if [[ -n "${disk_size:-}" && -n "${part_size:-}" && "$disk_size" -gt "$part_size" ]]; then
      local unused=$(( (disk_size - part_size) / 1024 / 1024 / 1024 ))
      [[ "$unused" -gt 1 ]] && has_free=true
    fi
  fi

  if [[ "$has_free" != "true" ]]; then
    log "Disk expand: no free space detected, skip"
    return 0
  fi

  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local pv disk part
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | awk 'NF{print $1; exit}')
    [[ -n "${pv:-}" ]] || return 1

    if [[ "$pv" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$pv" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      return 1
    fi

    run_quiet growpart "$disk" "$part" || return 1
    run_quiet pvresize "$pv" || return 1
    run_quiet lvextend -r -l +100%FREE "$rootdev" || return 1
    return 0
  else
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      return 1
    fi

    run_quiet growpart "$disk" "$part" || return 1
    case "$fstype" in
      ext2|ext3|ext4) run_quiet resize2fs "$rootdev" || return 1 ;;
      xfs) run_quiet xfs_growfs -d / || return 1 ;;
      btrfs) run_quiet btrfs filesystem resize max / || return 1 ;;
      *) return 1 ;;
    esac
    return 0
  fi
}

# ===== 功能：網路堆疊優化 =====
optimize_network_stack() {
  install_pkg procps || true
  install_pkg ethtool || true

  local f="/etc/sysctl.d/99-net-opt.conf"
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
EOF

  run_quiet sysctl --system || run_quiet sysctl -p || true

  local iface
  iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -n "${iface:-}" ]]; then
    run_quiet ip link set dev "$iface" txqueuelen 10000 || true
    run_quiet ethtool -K "$iface" gro on gso on tso on || true
  fi
  return 0
}

# ===== 功能：QEMU guest agent =====
install_guest_agent() {
  install_pkg qemu-guest-agent || return 1
  run_quiet systemctl enable --now qemu-guest-agent || true
  return 0
}

# ===== 功能：Docker + Compose =====
install_docker_stack() {
  install_pkg apt-transport-https || true
  install_pkg ca-certificates || true
  install_pkg curl || true
  install_pkg gnupg || true
  install_pkg lsb-release || true

  mkdir -p /etc/apt/keyrings
  run_quiet bash -lc 'curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg' || return 1

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    >/etc/apt/sources.list.d/docker.list

  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y docker-ce docker-ce-cli containerd.io || return 1

  run_quiet bash -lc 'curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose' || return 1
  chmod +x /usr/local/bin/docker-compose

  run_quiet systemctl enable --now docker || true
  return 0
}

# ===== 功能：Log 清理排程 =====
cleanup_log_cron() {
  rm -f /usr/local/sbin/elf-log-cleanup.sh /etc/cron.d/elf-log-cleanup >>"$LOG_FILE" 2>&1 || true
}
schedule_log_cleanup() {
  local choice
  choice=$(whiptail --backtitle "ELF Debian13 全功能工具" --title "Log 清理排程" --menu "選擇 log 清理排程" 14 70 6 \
    "每月一次" "每月 1 號 03:00" \
    "每三個月" "每 3 個月 1 號 03:00" \
    "每半年" "每 6 個月 1 號 03:00" \
    "停用排程" "移除排程" \
    3>&1 1>&2 2>&3) || return 0

  if [[ "$choice" = "停用排程" ]]; then
    cleanup_log_cron
    return 0
  fi

  cat >/usr/local/sbin/elf-log-cleanup.sh <<'EOF'
#!/usr/bin/env bash
set -e
log_root="/var/log"
find "$log_root" -type f -name "*.log" -size +5M -exec truncate -s 0 {} \; || true
find "$log_root" -type f -name "*.gz" -mtime +30 -delete || true
journalctl --vacuum-time=30d >/dev/null 2>&1 || true
EOF
  chmod +x /usr/local/sbin/elf-log-cleanup.sh

  local cron_expr=""
  case "$choice" in
    "每月一次") cron_expr="0 3 1 * *" ;;
    "每三個月") cron_expr="0 3 1 */3 *" ;;
    "每半年") cron_expr="0 3 1 */6 *" ;;
    *) return 1 ;;
  esac

  cat >/etc/cron.d/elf-log-cleanup <<EOF
$cron_expr root /usr/local/sbin/elf-log-cleanup.sh
EOF
  return 0
}

# ===== 功能：持久化效能調優（含 DNS + 固定停用服務/mysql除外）=====
disable_thp_runtime() {
  local base="/sys/kernel/mm/transparent_hugepage"
  [[ -d "$base" ]] || return 0
  echo never > "$base/enabled" 2>/dev/null || true
  echo never > "$base/defrag"  2>/dev/null || true
  return 0
}

grub_add_param_once() {
  local key="$1" param="$2"
  [[ -f "$GRUB_FILE" ]] || return 0
  grep -qE "^${key}=" "$GRUB_FILE" || echo "${key}=\"\"" >>"$GRUB_FILE"
  local current updated
  current="$(grep -E "^${key}=" "$GRUB_FILE" | head -n1 | sed -E 's/^'"$key"'="(.*)".*/\1/')"
  grep -qw -- "$param" <<<"$current" && return 0
  updated="$(echo "$current $param" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')"
  sed -i -E "s|^${key}=.*|${key}=\"${updated}\"|" "$GRUB_FILE"
  return 0
}

set_cpu_governor_performance() {
  install_pkg cpufrequtils || true
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    echo performance > "$f" 2>/dev/null || true
  done
  write_file_if_changed /etc/default/cpufrequtils 'GOVERNOR="performance"'
  run_quiet systemctl enable --now cpufrequtils || true
  return 0
}

enable_irqbalance() {
  install_pkg irqbalance || true
  run_quiet systemctl enable --now irqbalance || true
  return 0
}

apply_sysctl_baseline() {
  install_pkg procps || true
  write_file_if_changed "$SYSCTL_TUNE_FILE" "$SYSCTL_TUNE_CONTENT"
  run_quiet sysctl --system || run_quiet sysctl -p || true
  return 0
}

ensure_dns() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved\.service'; then
    install_pkg systemd-resolved || true
    local f="/etc/systemd/resolved.conf"
    [[ -f "$f" ]] || touch "$f"
    backup_file_ts "$f"
    grep -qE '^\s*\[Resolve\]\s*$' "$f" || printf '\n[Resolve]\n' >>"$f"

    if grep -qE '^\s*#?\s*DNS=' "$f"; then
      sed -i -E "s|^\s*#?\s*DNS=.*|DNS=${DNS_PRIMARY}|" "$f"
    else
      awk -v dns="DNS=${DNS_PRIMARY}" '{print} /^\[Resolve\]/{print dns}' "$f" >"${f}.tmp" && mv "${f}.tmp" "$f"
    fi

    if grep -qE '^\s*#?\s*FallbackDNS=' "$f"; then
      sed -i -E "s|^\s*#?\s*FallbackDNS=.*|FallbackDNS=${DNS_FALLBACK}|" "$f"
    else
      awk -v fdns="FallbackDNS=${DNS_FALLBACK}" '{print} /^\[Resolve\]/{print fdns}' "$f" >"${f}.tmp" && mv "${f}.tmp" "$f"
    fi

    run_quiet systemctl enable --now systemd-resolved || true
    run_quiet systemctl restart systemd-resolved || true

    [[ -e /run/systemd/resolve/stub-resolv.conf ]] && ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    [[ -e /run/systemd/resolve/resolv.conf ]]      && ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  else
    backup_file_ts /etc/resolv.conf || true
    {
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $1}')"
      echo "nameserver $(echo "$DNS_PRIMARY" | awk '{print $2}')"
    } >/etc/resolv.conf
  fi
  return 0
}

install_io_tune_service() {
  cat >"$IO_TUNE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

pick_sched() {
  local sched_file="$1"; shift
  local available
  available="$(cat "$sched_file" 2>/dev/null || true)"
  local s
  for s in "$@"; do
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
    chosen="$(pick_sched "$sched_file" none noop mq-deadline deadline kyber bfq)"
  else
    chosen="$(pick_sched "$sched_file" mq-deadline deadline bfq kyber none noop)"
  fi

  [[ -n "$chosen" ]] && echo "$chosen" >"$sched_file" 2>/dev/null || true
  [[ -e "$base/queue/nr_requests" ]] && echo "$NR_REQUESTS_DEFAULT" >"$base/queue/nr_requests" 2>/dev/null || true
  [[ -e "$base/queue/read_ahead_kb" ]] && echo "$READ_AHEAD_KB_DEFAULT" >"$base/queue/read_ahead_kb" 2>/dev/null || true
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

  cat >"$IO_TUNE_SERVICE" <<EOF
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

  run_quiet systemctl daemon-reload || true
  run_quiet systemctl enable --now elf-io-tune.service || true
  return 0
}

enable_fstrim() { run_quiet systemctl enable --now fstrim.timer || true; return 0; }

disable_services_except_mysql() {
  local s
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    if unit_exists "$s"; then
      run_quiet systemctl disable --now "$s" || true
    fi
  done
  return 0
}

apply_persistent_tuning() {
  set_cpu_governor_performance || true
  enable_irqbalance || true
  apply_sysctl_baseline || true

  disable_thp_runtime || true
  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    grub_add_param_once "GRUB_CMDLINE_LINUX_DEFAULT" "transparent_hugepage=never" || true
    if ! command -v update-grub >/dev/null 2>&1; then
      install_pkg grub2-common || true
    fi
    run_quiet update-grub || true
  fi

  install_io_tune_service || true
  enable_fstrim || true
  ensure_dns || true
  disable_services_except_mysql || true
  return 0
}

# ===== 主流程 =====
require_root_tty
ensure_log
log "========== SCRIPT START =========="

# 確保 whiptail
if ! command -v whiptail >/dev/null 2>&1; then
  echo "whiptail 未安裝，正在安裝...（log: $LOG_FILE）"
  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y whiptail || true
fi

wait_system_ready

# 勾選式選單（勾選=執行）
CHOICES=$(
  whiptail --backtitle "ELF Debian13 全功能工具" --title "請勾選要執行的功能" \
  --checklist "空白鍵勾選/取消；Enter 確認；Esc 退出\n\nLog：$LOG_FILE" 22 78 12 \
  "持久化效能調優"      "CPU/sysctl/THP/I-O/DNS/停用服務(mysql除外)" OFF \
  "固定IP與DNS"         "自動取當下介面/網段/gateway；可輸入最後一碼" OFF \
  "禁用IPv6"            "runtime + GRUB 持久化（需重啟完整生效）" OFF \
  "設定ROOT密碼"        "設定 root 新密碼" OFF \
  "安裝並設定SSH"       "允許 root 密碼登入（sshd_config）" OFF \
  "安裝QEMU Guest Agent" "qemu-guest-agent enable --now" OFF \
  "安裝Docker與Compose" "安裝 Docker Engine + docker-compose" OFF \
  "大檔I-O優化"          "dirty_ratio/dirty_background_ratio/swappiness" OFF \
  "擴展硬碟"             "支援 LVM 與一般分割（有空間才會做）" OFF \
  "網路堆疊優化"         "BBR/fq/socket buffer/TFO/txqueuelen/GRO" OFF \
  "設定Log清理排程"      "每月/每三個月/每半年/停用" OFF \
  3>&1 1>&2 2>&3
) || { ui_msg "已取消" "你已取消執行。\n\nLog：$LOG_FILE"; exit 0; }

# 解析選擇
CHOICES="$(echo "$CHOICES" | tr -d '"')"

# 依序執行（你可自行調整順序）
echo "$CHOICES" | grep -q "持久化效能調優"      && safe_step "持久化效能調優" "套用持久化效能調優（含 DNS + 固定停用服務）" apply_persistent_tuning || true
echo "$CHOICES" | grep -q "固定IP與DNS"         && safe_step "固定IP與DNS" "設定固定 IP（取當下 gateway/網段）" configure_static_ip || true
echo "$CHOICES" | grep -q "禁用IPv6"            && safe_step "禁用IPv6" "禁用 IPv6（runtime + GRUB）" disable_ipv6 || true
echo "$CHOICES" | grep -q "設定ROOT密碼"        && safe_step "設定ROOT密碼" "設定 root 密碼" set_root_password || true
echo "$CHOICES" | grep -q "安裝並設定SSH"       && safe_step "安裝並設定SSH" "安裝並設定 SSH" configure_ssh || true
echo "$CHOICES" | grep -q "安裝QEMU Guest Agent" && safe_step "QEMU Guest Agent" "安裝並啟用 qemu-guest-agent" install_guest_agent || true
echo "$CHOICES" | grep -q "安裝Docker與Compose" && safe_step "Docker與Compose" "安裝 Docker Engine 與 Compose" install_docker_stack || true
echo "$CHOICES" | grep -q "大檔I-O優化"          && safe_step "大檔I-O優化" "套用大檔 I/O sysctl" optimize_large_file_io || true
echo "$CHOICES" | grep -q "擴展硬碟"             && safe_step "擴展硬碟" "擴展硬碟（有空間才做）" expand_disk || true
echo "$CHOICES" | grep -q "網路堆疊優化"         && safe_step "網路堆疊優化" "套用網路堆疊 sysctl/介面調整" optimize_network_stack || true
echo "$CHOICES" | grep -q "設定Log清理排程"      && safe_step "Log清理排程" "設定/停用 log 清理排程" schedule_log_cleanup || true

ui_msg "完成" "已完成你勾選的項目。\n\nLog：$LOG_FILE\n\n若你勾了「禁用IPv6」或「持久化效能調優（含 GRUB/THP）」：建議重啟一次讓設定完整生效。"
log "========== SCRIPT END =========="
exit 0
