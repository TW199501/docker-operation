#!/usr/bin/env bash
# ELF Debian 13 VM Tools (Stable UI + Safe Logging)
# - UI: whiptail Yes/No per feature (YES=do, NO=skip)
# - All command outputs go to /var/log/elf-tools.log (no UI break)
# - Non-critical failures do not abort the whole script
# - MySQL is never disabled
# - DNS is applied when "Persistent Tuning" is selected (as requested)

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -u
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}"

LOG_FILE="/var/log/elf-tools.log"

DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"

# mysql excluded on purpose
SERVICES_TO_DISABLE=(bluetooth cups apache2)

SYSCTL_TUNE_FILE="/etc/sysctl.d/99-elf-tuning.conf"
SYSCTL_TUNE_CONTENT=$(cat <<'EOF'
# ---- ELF baseline tuning ----
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
vm.page-cluster=3
vm.min_free_kbytes=65536

net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216

net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3

net.core.netdev_max_backlog=5000
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8192
net.netfilter.nf_conntrack_max=131072
EOF
)

IO_TUNE_SCRIPT="/usr/local/sbin/elf-io-tune.sh"
IO_TUNE_SERVICE="/etc/systemd/system/elf-io-tune.service"
GRUB_FILE="/etc/default/grub"

# ----------------- helpers -----------------
ensure_log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
}

log() {
  ensure_log
  echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"
}

run_quiet() {
  # run command, redirect all output to log, return exit code
  # usage: run_quiet cmd args...
  "$@" >>"$LOG_FILE" 2>&1
  return $?
}

msgbox() {
  whiptail --backtitle "ELF Debian13 Tools" --title "$1" --msgbox "$2" 12 78
}

infobox() {
  whiptail --backtitle "ELF Debian13 Tools" --title "$1" --infobox "$2" 12 78
}

yesno() {
  # returns 0 on YES, 1 on NO
  whiptail --backtitle "ELF Debian13 Tools" --title "$1" --yesno "$2" 12 78
}

require_root_tty() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[ERROR] Please run as root (sudo -i)."
    exit 1
  fi
  if ! [ -t 0 ] || ! [ -t 1 ]; then
    echo "[ERROR] No TTY detected; whiptail UI cannot run."
    exit 1
  fi
}

install_pkg() {
  local pkg="$1"
  dpkg -s "$pkg" >/dev/null 2>&1 && return 0
  infobox "Installing" "Installing package: $pkg\n\nLogging to: $LOG_FILE"
  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y "$pkg"
}

backup_file_ts() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
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

safe_step() {
  # safe_step "Title" "Description" command...
  local title="$1"; shift
  local desc="$1"; shift
  infobox "$title" "$desc\n\nPlease wait...\nLog: $LOG_FILE"
  log "START: $title - $desc"
  if run_quiet "$@"; then
    log "OK: $title"
    return 0
  else
    local rc=$?
    log "FAIL: $title rc=$rc"
    msgbox "Failed" "$title failed (rc=$rc).\n\nSee log:\n$LOG_FILE"
    return $rc
  fi
}

# ----------------- feature: persistent tuning -----------------
disable_thp_runtime() {
  local base="/sys/kernel/mm/transparent_hugepage"
  [[ -d "$base" ]] || return 0
  echo never > "$base/enabled" 2>/dev/null || true
  echo never > "$base/defrag"  2>/dev/null || true
  return 0
}

grub_add_param_once() {
  local key="$1"
  local param="$2"
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
  install_pkg cpufrequtils || return 1
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    echo performance > "$f" 2>/dev/null || true
  done
  write_file_if_changed /etc/default/cpufrequtils 'GOVERNOR="performance"'
  run_quiet systemctl enable --now cpufrequtils || true
  return 0
}

enable_irqbalance() {
  install_pkg irqbalance || return 1
  run_quiet systemctl enable --now irqbalance || true
  return 0
}

apply_sysctl_baseline() {
  write_file_if_changed "$SYSCTL_TUNE_FILE" "$SYSCTL_TUNE_CONTENT"
  run_quiet sysctl --system || run_quiet sysctl -p || true
  return 0
}

ensure_dns() {
  # prefer systemd-resolved if exists, else write resolv.conf
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
    } >/etc/resolv.conf
  fi
  return 0
}

pick_sched_from_file() {
  local sched_file="$1"
  shift
  local candidates=("$@")
  local available
  available="$(cat "$sched_file" 2>/dev/null || true)"
  local s
  for s in "${candidates[@]}"; do
    # available format: "mq-deadline [none] kyber bfq"
    if echo "$available" | grep -Eq "(^|[[:space:]])\[$s\]([[:space:]]|$)|(^|[[:space:]])$s([[:space:]]|$)"; then
      echo "$s"
      return 0
    fi
  done
  echo ""
  return 0
}

install_io_tune_service() {
  cat >"$IO_TUNE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

pick_sched() {
  local sched_file="$1"
  local preferred=("$@")
  local available
  available="$(cat "$sched_file" 2>/dev/null || true)"
  local s
  for s in "${preferred[@]:1}"; do
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

enable_fstrim() {
  run_quiet systemctl enable --now fstrim.timer || true
  return 0
}

disable_services_except_mysql() {
  local s
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    run_quiet systemctl disable --now "$s" || true
  done
  return 0
}

apply_persistent_tuning_all() {
  # never let a sub-step kill whole script
  set_cpu_governor_performance || true
  enable_irqbalance || true
  apply_sysctl_baseline || true

  disable_thp_runtime || true
  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    grub_add_param_once "GRUB_CMDLINE_LINUX_DEFAULT" "transparent_hugepage=never" || true
    run_quiet update-grub || true
  fi

  install_io_tune_service || true
  enable_fstrim || true
  ensure_dns || true
  disable_services_except_mysql || true

  return 0
}

# ----------------- feature: large file tuning -----------------
optimize_for_large_files() {
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

# ----------------- feature: static IP / DNS -----------------
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
    last=$(whiptail --backtitle "ELF Debian13 Tools" --title "Static IP" \
      --inputbox "Interface: $iface\nCurrent: $current_ip/$prefix\n\nEnter last octet (1~254):\nExample: 50 => ${base3}.50" 13 75 "" \
      3>&1 1>&2 2>&3) || return 0
    [[ "$last" =~ ^[0-9]{1,3}$ ]] && (( last>=1 && last<=254 )) || return 1
    target_ip="${base3}.${last}"
  else
    target_ip=$(whiptail --backtitle "ELF Debian13 Tools" --title "Static IP" \
      --inputbox "No current IPv4 detected. Enter full static IP (e.g., 192.168.25.50)" 10 75 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  if [[ -n "${gateway:-}" ]]; then
    if ! yesno "Gateway" "Detected gateway: $gateway\n\nUse it?"; then
      gateway=$(whiptail --backtitle "ELF Debian13 Tools" --title "Gateway" \
        --inputbox "Enter gateway (e.g., 192.168.25.254)" 10 75 "" \
        3>&1 1>&2 2>&3) || return 0
    fi
  else
    gateway=$(whiptail --backtitle "ELF Debian13 Tools" --title "Gateway" \
      --inputbox "Gateway not detected. Enter gateway (e.g., 192.168.25.254)" 10 75 "" \
      3>&1 1>&2 2>&3) || return 0
  fi

  local netmask
  netmask="$(prefix2netmask "$prefix")"

  local dns
  dns="$(echo "$DNS_PRIMARY" | awk '{print $1}')"

  # detect manager
  local network_manager=""
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    network_manager="systemd-networkd"
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    network_manager="NetworkManager"
  else
    network_manager="interfaces"
  fi

  log "Static IP apply: iface=$iface ip=$target_ip/$prefix gw=$gateway dns=$dns manager=$network_manager"

  case "$network_manager" in
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

# ----------------- feature: guest agent -----------------
install_guest_agent() {
  install_pkg qemu-guest-agent || return 1
  run_quiet systemctl enable --now qemu-guest-agent || true
  return 0
}

# ----------------- feature: docker -----------------
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

# ----------------- feature: disk expand -----------------
expand_disk() {
  install_pkg cloud-guest-utils || true
  install_pkg lvm2 || true
  install_pkg xfsprogs || true
  install_pkg btrfs-progs || true
  install_pkg bc || true

  local rootdev fstype
  rootdev=$(findmnt -no SOURCE /)
  fstype=$(findmnt -no FSTYPE /)

  # Quick check: if no free space, just return OK
  local has_free_space=false
  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    local vg_free
    vg_free=$(vgs --noheadings -o vg_free --units G 2>/dev/null | awk '{print $1}' | sed 's/G//' | head -1)
    if [ -n "$vg_free" ] && [ "$(echo "$vg_free > 0" | bc 2>/dev/null)" = "1" ]; then
      has_free_space=true
    fi
  fi

  if [ "$has_free_space" = false ]; then
    return 0
  fi

  # LVM expansion only (safe)
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

  run_quiet growpart "$disk" "$part" || return 1
  run_quiet pvresize "$pv" || return 1
  run_quiet lvextend -r -l +100%FREE "$lv" || return 1
  return 0
}

# ----------------- feature: network optimize -----------------
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
EOF

  run_quiet sysctl --system || run_quiet sysctl -p || true

  local iface
  iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -n "${iface:-}" ]]; then
    install_pkg ethtool || true
    run_quiet ip link set dev "$iface" txqueuelen 10000 || true
    run_quiet ethtool -K "$iface" gro on gso on tso on || true
  fi
  return 0
}

# ----------------- MAIN -----------------
require_root_tty
ensure_log
log "========== SCRIPT START =========="

# Ensure whiptail exists
if ! command -v whiptail >/dev/null 2>&1; then
  # allow minimal non-UI install prompt
  echo "whiptail not found. Installing..."
  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y whiptail || true
fi

# Wait systemd ready (running or degraded)
infobox "Boot" "Waiting for system ready..."
for i in {1..30}; do
  st="$(systemctl is-system-running 2>/dev/null || true)"
  if [[ "$st" = "running" || "$st" = "degraded" ]]; then
    break
  fi
  sleep 2
done

# ---- Menu: YES=DO, NO=SKIP ----
if yesno "Persistent Tuning" \
"Apply persistent tuning + DNS + disable services (except mysql)?\n\nIncludes:\n- CPU governor performance\n- sysctl baseline\n- THP disable (runtime + grub param)\n- I/O scheduler+queue via systemd oneshot\n- fstrim.timer, irqbalance\n- DNS (required)\n- disable: bluetooth/cups/apache2\n\nYES=Apply, NO=Skip"; then
  safe_step "Persistent Tuning" "Applying tuning..." apply_persistent_tuning_all || true
fi

if yesno "Static IP / DNS" \
"Configure static IPv4 using current interface/gateway/prefix?\n\nYES=Configure, NO=Skip"; then
  safe_step "Static IP" "Configuring static IP..." configure_static_ip || true
fi

if yesno "SSH" \
"Install & configure SSH to allow root password login?\n\nYES=Configure, NO=Skip"; then
  safe_step "SSH" "Configuring SSH..." configure_ssh || true
fi

if yesno "qemu-guest-agent" \
"Install & enable qemu-guest-agent?\n\nYES=Install, NO=Skip"; then
  safe_step "Guest Agent" "Installing guest agent..." install_guest_agent || true
fi

if yesno "Root Password" \
"Set root password now?\n\nYES=Set, NO=Skip"; then
  safe_step "Root Password" "Setting root password..." set_root_password || true
fi

if yesno "Docker" \
"Install Docker Engine + docker-compose?\n\nYES=Install, NO=Skip"; then
  safe_step "Docker" "Installing Docker..." install_docker_stack || true
fi

if yesno "Large File I/O" \
"Apply large-file dirty_ratio tuning (sysctl)?\n\nYES=Apply, NO=Skip"; then
  safe_step "Large File I/O" "Applying sysctl..." optimize_for_large_files || true
fi

if yesno "Expand Disk" \
"Try to expand disk (LVM-focused safe path)?\n\nYES=Expand, NO=Skip"; then
  safe_step "Expand Disk" "Expanding disk..." expand_disk || true
fi

if yesno "Network Optimize" \
"Apply network stack sysctl optimizations (BBR/fq etc)?\n\nYES=Apply, NO=Skip"; then
  safe_step "Network Optimize" "Applying network settings..." optimize_network_stack || true
fi

msgbox "Done" "All selected steps finished.\n\nLog:\n$LOG_FILE\n\nIf you applied GRUB param (THP), reboot is recommended."
log "========== SCRIPT END =========="
exit 0

