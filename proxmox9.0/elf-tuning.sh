#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# One-shot Persistent Linux Tuning Script (DNS mandatory)
# - Persistent: cpufrequtils, sysctl, THP via GRUB, udev scheduler rules, fstrim.timer, irqbalance
# - Fixed service disable (mysql excluded): bluetooth, cups, apache2
# - DNS optimization ALWAYS applied (systemd-resolved) with resolv.conf fix
#
# Usage:
#   sudo bash this_script.sh
# ============================================================

# ---------- Config (edit if needed) ----------
DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"

# Services to disable (mysql excluded by design)
SERVICES_TO_DISABLE=(bluetooth cups apache2)

SYSCTL_FILE="/etc/sysctl.d/99-elf-tuning.conf"
SYSCTL_CONTENT=$(cat <<'EOF'
# ---- Memory ----
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
vm.page-cluster=3
vm.min_free_kbytes=65536

# ---- Network ----
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216

net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3

net.core.netdev_max_backlog=5000
net.netfilter.nf_conntrack_max=131072
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=32768
EOF
)

UDEV_RULE_FILE="/etc/udev/rules.d/60-elf-schedulers.rules"
UDEV_RULE_CONTENT=$(cat <<'EOF'
# Best-effort I/O scheduler selection based on rotational flag.
# rotational=0: SSD/NVMe -> prefer 'none' (or noop on older kernels)
# rotational=1: HDD      -> prefer 'mq-deadline' (or deadline on older kernels)
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|xvd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|xvd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
)

NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

GRUB_FILE="/etc/default/grub"
GRUB_TIMEOUT_VALUE="2"
GRUB_CMDLINE_ADD=("transparent_hugepage=never")
# -------------------------------------------

log()  { printf '%s\n' "[INFO] $*"; }
warn() { printf '%s\n' "[WARN] $*" >&2; }
die()  { printf '%s\n' "[ERROR] $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "请用 root 执行：sudo $0"
  fi
}

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local bak="${f}.bak.${ts}"
  cp -a "$f" "$bak"
  log "已备份：$f -> $bak"
}

write_file_if_changed() {
  local path="$1"
  local content="$2"

  if [[ -e "$path" ]]; then
    if diff -q <(printf '%s\n' "$content") "$path" >/dev/null 2>&1; then
      log "文件未变更：$path"
      return 0
    fi
    backup_file "$path"
  fi

  install -D -m 0644 /dev/null "$path"
  printf '%s\n' "$content" > "$path"
  log "已写入：$path"
}

apt_install() {
  local pkgs=("$@")
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "未找到 apt-get，跳过套件安装：${pkgs[*]}"
    return 0
  fi
  apt-get update -y
  apt-get install -y "${pkgs[@]}"
}

# ---------------- CPU governor ----------------
set_cpu_governor_runtime() {
  local any=0
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    any=1
    echo performance > "$f" || true
  done
  [[ "$any" -eq 0 ]] && warn "找不到 cpufreq scaling_governor（可能是 VM/未启用 cpufreq），跳过 runtime governor。"
}

set_cpu_governor_persistent() {
  apt_install cpufrequtils || true
  write_file_if_changed "/etc/default/cpufrequtils" 'GOVERNOR="performance"'
  systemctl enable --now cpufrequtils 2>/dev/null || true
  log "已设定 CPU governor(persistent) via cpufrequtils。"
}

# ---------------- irqbalance ----------------
enable_irqbalance() {
  apt_install irqbalance || true
  systemctl enable --now irqbalance
  log "已启用 irqbalance。"
}

# ---------------- sysctl ----------------
apply_sysctl() {
  write_file_if_changed "$SYSCTL_FILE" "$SYSCTL_CONTENT"
  sysctl --system
  log "已套用 sysctl（memory/network）。"
}

# ---------------- THP ----------------
disable_thp_runtime() {
  local base="/sys/kernel/mm/transparent_hugepage"
  if [[ -d "$base" ]]; then
    for f in "$base/enabled" "$base/defrag"; do
      [[ -e "$f" ]] || continue
      echo never > "$f" || true
    done
    log "已尝试停用 THP(runtime)。"
  else
    warn "找不到 THP 介面，跳过 runtime THP。"
  fi
}

grub_set_timeout() {
  [[ -f "$GRUB_FILE" ]] || { warn "找不到 $GRUB_FILE，跳过 GRUB 设定。"; return 0; }
  backup_file "$GRUB_FILE"

  if grep -qE '^\s*GRUB_TIMEOUT=' "$GRUB_FILE"; then
    sed -i "s/^\s*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT_VALUE}/" "$GRUB_FILE"
  else
    printf '\nGRUB_TIMEOUT=%s\n' "$GRUB_TIMEOUT_VALUE" >> "$GRUB_FILE"
  fi
  log "已设定 GRUB_TIMEOUT=${GRUB_TIMEOUT_VALUE}"
}

grub_add_cmdline_opts() {
  [[ -f "$GRUB_FILE" ]] || { warn "找不到 $GRUB_FILE，跳过 GRUB cmdline。"; return 0; }

  if ! grep -qE '^\s*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    printf '\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >> "$GRUB_FILE"
  fi

  local current updated
  current="$(grep -E '^\s*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | head -n1 | sed -E 's/^\s*GRUB_CMDLINE_LINUX_DEFAULT="(.*)".*/\1/')"
  updated="$current"

  for opt in "${GRUB_CMDLINE_ADD[@]}"; do
    if ! grep -qw -- "$opt" <<<"$updated"; then
      updated="$updated $opt"
    fi
  done
  updated="$(echo "$updated" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')"

  sed -i -E "s|^\s*GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${updated}\"|" "$GRUB_FILE"
  log "已更新 GRUB_CMDLINE_LINUX_DEFAULT：$updated"
}

update_grub() {
  if command -v update-grub >/dev/null 2>&1; then
    update-grub
    log "已 update-grub（需重开机才完整生效）。"
  else
    warn "找不到 update-grub，跳过。"
  fi
}

# ---------------- Block I/O ----------------
get_scheduler_candidates() {
  local rotational="$1"
  if [[ "$rotational" == "0" ]]; then
    echo "none noop mq-deadline deadline kyber bfq"
  else
    echo "mq-deadline deadline bfq kyber none noop"
  fi
}

set_block_scheduler_runtime() {
  local dev="$1"
  local sched_file="/sys/block/${dev}/queue/scheduler"
  local rot_file="/sys/block/${dev}/queue/rotational"
  [[ -e "$sched_file" ]] || return 0

  local rotational="1"
  [[ -e "$rot_file" ]] && rotational="$(cat "$rot_file" 2>/dev/null || echo 1)"
  local available chosen=""
  available="$(cat "$sched_file" 2>/dev/null || true)"

  local candidates
  candidates="$(get_scheduler_candidates "$rotational")"
  for c in $candidates; do
    if grep -Eq "(^|[[:space:]])\[$c\]([[:space:]]|$)|(^|[[:space:]])$c([[:space:]]|$)" <<<"$available"; then
      chosen="$c"
      break
    fi
  done

  if [[ -n "$chosen" ]]; then
    echo "$chosen" > "$sched_file" || true
    log "dev=$dev rotational=$rotational scheduler=$chosen (available: $available)"
  else
    warn "dev=$dev 找不到可用 scheduler（available: $available），跳过。"
  fi
}

set_block_queue_tunables() {
  local dev="$1"
  local nr="/sys/block/${dev}/queue/nr_requests"
  local ra="/sys/block/${dev}/queue/read_ahead_kb"
  [[ -e "$nr" ]] && echo "$NR_REQUESTS_DEFAULT" > "$nr" || true
  [[ -e "$ra" ]] && echo "$READ_AHEAD_KB_DEFAULT" > "$ra" || true
}

apply_block_io_runtime() {
  local any=0
  for d in /sys/block/*; do
    [[ -d "$d" ]] || continue
    local dev
    dev="$(basename "$d")"
    if [[ "$dev" =~ ^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)$ ]]; then
      any=1
      set_block_scheduler_runtime "$dev"
      set_block_queue_tunables "$dev"
    fi
  done
  [[ "$any" -eq 0 ]] && warn "未找到符合条件的 block device，跳过 I/O runtime。" || log "已套用 block I/O runtime（scheduler + queue tunables）。"
}

apply_udev_scheduler_rules() {
  write_file_if_changed "$UDEV_RULE_FILE" "$UDEV_RULE_CONTENT"
  udevadm control --reload-rules
  udevadm trigger
  log "已套用 udev 规则（下次开机/装置重连更完整生效）。"
}

# ---------------- TRIM timer ----------------
enable_fstrim_timer() {
  systemctl enable --now fstrim.timer 2>/dev/null || true
  log "已尝试启用 fstrim.timer。"
}

# ---------------- DNS (mandatory) ----------------
ensure_resolv_conf_points_to_resolved() {
  local stub="/run/systemd/resolve/stub-resolv.conf"
  local full="/run/systemd/resolve/resolv.conf"

  if [[ -e "$stub" ]]; then
    ln -sf "$stub" /etc/resolv.conf
    log "已将 /etc/resolv.conf 指向：$stub"
  elif [[ -e "$full" ]]; then
    ln -sf "$full" /etc/resolv.conf
    log "已将 /etc/resolv.conf 指向：$full"
  else
    warn "找不到 /run/systemd/resolve/* 输出；systemd-resolved 可能未启用。"
  fi
}

apply_dns_systemd_resolved() {
  local f="/etc/systemd/resolved.conf"
  if [[ ! -f "$f" ]]; then
    warn "找不到 $f（systemd-resolved 可能未使用），跳过 DNS 设定。"
    return 0
  fi

  backup_file "$f"

  if ! grep -qE '^\s*\[Resolve\]\s*$' "$f"; then
    printf '\n[Resolve]\n' >> "$f"
  fi

  sed -i -E "s|^\s*#?\s*DNS=.*|DNS=${DNS_PRIMARY}|" "$f" || true
  sed -i -E "s|^\s*#?\s*FallbackDNS=.*|FallbackDNS=${DNS_FALLBACK}|" "$f" || true

  if ! grep -qE "^\s*DNS=" "$f"; then
    awk -v dns="DNS=${DNS_PRIMARY}" '{print} /^\[Resolve\]/{print dns}' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi
  if ! grep -qE "^\s*FallbackDNS=" "$f"; then
    awk -v fdns="FallbackDNS=${DNS_FALLBACK}" '{print} /^\[Resolve\]/{print fdns}' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi

  systemctl enable --now systemd-resolved 2>/dev/null || true
  ensure_resolv_conf_points_to_resolved
  systemctl restart systemd-resolved

  log "DNS 优化已套用（systemd-resolved）。"
}

# ---------------- Disable services (fixed) ----------------
disable_fixed_services() {
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable --now "$s" 2>/dev/null || true
    log "已尝试停用服务：$s"
  done
  log "mysql 未停用（按需求保留）。"
}

# ---------------- Main ----------------
main() {
  need_root

  log "开始执行：持久化调优 + 固定停用服务（mysql除外） + DNS 必做"

  # Packages needed by features
  apt_install cpufrequtils irqbalance || true

  # CPU
  set_cpu_governor_runtime
  set_cpu_governor_persistent

  # IRQ balancing
  enable_irqbalance

  # sysctl persistent + apply now
  apply_sysctl

  # THP runtime + GRUB persistent
  disable_thp_runtime
  grub_set_timeout
  grub_add_cmdline_opts
  update_grub

  # Block IO runtime + udev persistent
  apply_block_io_runtime
  apply_udev_scheduler_rules

  # TRIM timer
  enable_fstrim_timer

  # DNS mandatory
  apply_dns_systemd_resolved

  # Disable services (fixed; mysql excluded)
  disable_fixed_services

  log "完成。建议：请安排重开机，让 GRUB/THP/udev 相关变更完整生效。"
}

main "$@"
