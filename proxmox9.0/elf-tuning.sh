#!/usr/bin/env bash
# ELF Debian 13 VM Tools (Stable UI + Safe Logging) - FIXED PATH/PKGS
# YES = DO, NO = SKIP
# Log: /var/log/elf-tools.log

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -u
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}"

# FIX: make sure admin commands are found
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

unit_exists() {
  local name="$1"
  systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${name}.service"
}

# ----------------- persistent tuning -----------------
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
  # FIX: sysctl comes from procps
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
  local sched_file="$1"
  shift
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

enable_fstrim() {
  run_quiet systemctl enable --now fstrim.timer || true
  return 0
}

disable_services_except_mysql() {
  local s
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    if unit_exists "$s"; then
      run_quiet systemctl disable --now "$s" || true
    fi
  done
  return 0
}

apply_persistent_tuning_all() {
  set_cpu_governor_performance || true
  enable_irqbalance || true
  apply_sysctl_baseline || true

  disable_thp_runtime || true
  if [[ -f "$GRUB_FILE" ]]; then
    backup_file_ts "$GRUB_FILE"
    grub_add_param_once "GRUB_CMDLINE_LINUX_DEFAULT" "transparent_hugepage=never" || true
    # FIX: update-grub may not exist; install grub2-common when needed
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

# ----------------- large file tuning -----------------
optimize_for_large_files() {
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

# ----------------- network optimize -----------------
optimize_network_stack() {
  install_pkg procps || true
  install_pkg ethtool || true

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
    run_quiet ip link set dev "$iface" txqueuelen 10000 || true
    run_quiet ethtool -K "$iface" gro on gso on tso on || true
  fi
  return 0
}

# ----------------- guest agent -----------------
install_guest_agent() {
  install_pkg qemu-guest-agent || return 1
  run_quiet systemctl enable --now qemu-guest-agent || true
  return 0
}

# ----------------- MAIN -----------------
require_root_tty
ensure_log
log "========== SCRIPT START =========="

# Ensure whiptail exists
if ! command -v whiptail >/dev/null 2>&1; then
  echo "whiptail not found. Installing..."
  run_quiet apt-get update -qq || true
  run_quiet apt-get install -y whiptail || true
fi

infobox "Boot" "Waiting for system ready..."
for i in {1..30}; do
  st="$(systemctl is-system-running 2>/dev/null || true)"
  if [[ "$st" = "running" || "$st" = "degraded" ]]; then
    break
  fi
  sleep 2
done

if yesno "Persistent Tuning" \
"Apply persistent tuning + DNS + disable services (except mysql)?\n\nYES=Apply, NO=Skip"; then
  safe_step "Persistent Tuning" "Applying tuning..." apply_persistent_tuning_all || true
fi

if yesno "Large File I/O" \
"Apply large-file sysctl tuning?\n\nYES=Apply, NO=Skip"; then
  safe_step "Large File I/O" "Applying sysctl..." optimize_for_large_files || true
fi

if yesno "Network Optimize" \
"Apply network sysctl optimizations?\n\nYES=Apply, NO=Skip"; then
  safe_step "Network Optimize" "Applying network settings..." optimize_network_stack || true
fi

if yesno "qemu-guest-agent" \
"Install & enable qemu-guest-agent?\n\nYES=Install, NO=Skip"; then
  safe_step "Guest Agent" "Installing guest agent..." install_guest_agent || true
fi

msgbox "Done" "Finished.\n\nLog:\n$LOG_FILE"
log "========== SCRIPT END =========="
exit 0
