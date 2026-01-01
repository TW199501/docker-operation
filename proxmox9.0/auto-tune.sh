#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ELF Linux Tuning Script
# - CPU governor
# - irqbalance
# - sysctl (memory/network)
# - THP disable
# - block IO scheduler + queue tunables
# - fstrim timer
# - (optional) DNS via systemd-resolved
# - (optional) disable services
# - (optional) initramfs policy
# ============================================================

DRY_RUN=0
ENABLE_DNS=0
DISABLE_SERVICES=0
ENABLE_INITRAMFS=0

# DNS servers (systemd-resolved)
DNS_PRIMARY="1.1.1.1 8.8.8.8"
DNS_FALLBACK="1.0.0.1 8.8.4.4"

# Sysctl tuning (edit as needed)
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

# Udev rules for scheduler (best-effort; depends on kernel availability)
UDEV_RULE_FILE="/etc/udev/rules.d/60-elf-schedulers.rules"
UDEV_RULE_CONTENT=$(cat <<'EOF'
# Set scheduler based on rotational flag (best-effort)
# rotational=0: SSD/NVMe -> prefer 'none' (or noop on older kernels)
# rotational=1: HDD      -> prefer 'mq-deadline' (or deadline on older kernels)
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|xvd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|xvd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
)

# Block queue tunables (best-effort defaults)
NR_REQUESTS_DEFAULT=128
READ_AHEAD_KB_DEFAULT=256

# GRUB tuning
GRUB_FILE="/etc/default/grub"
GRUB_TIMEOUT_VALUE="2"
# Additions to GRUB_CMDLINE_LINUX_DEFAULT (do not remove existing options)
GRUB_CMDLINE_ADD=("transparent_hugepage=never")

# Services that are "commonly optional" (disable only with --disable-services)
SERVICES_TO_DISABLE=(bluetooth cups apache2 mysql)

# Initramfs tuning (optional)
INITRAMFS_DRIVER_POLICY="/etc/initramfs-tools/conf.d/driver-policy"
INITRAMFS_COMPRESS="/etc/initramfs-tools/conf.d/compress"
INITRAMFS_DRIVER_POLICY_CONTENT='MODULES=dep'
INITRAMFS_COMPRESS_CONTENT='COMPRESS=lz4'

# ------------------------------------------------------------

log()  { printf '%s\n' "[INFO] $*"; }
warn() { printf '%s\n' "[WARN] $*" >&2; }
die()  { printf '%s\n' "[ERROR] $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "[DRY] $*"
  else
    eval "$@"
  fi
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "請用 root 執行：sudo $0 [options]"
  fi
}

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local bak="${f}.bak.${ts}"
  run "cp -a \"$f\" \"$bak\""
  log "已備份：$f -> $bak"
}

write_file_if_changed() {
  local path="$1"
  local content="$2"

  if [[ -e "$path" ]]; then
    # Compare content
    if diff -q <(printf '%s\n' "$content") "$path" >/dev/null 2>&1; then
      log "檔案未變更：$path"
      return 0
    fi
    backup_file "$path"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "將寫入：$path"
    printf '%s\n' "----- BEGIN $path -----"
    printf '%s\n' "$content"
    printf '%s\n' "----- END $path -----"
  else
    install -D -m 0644 /dev/null "$path"
    printf '%s\n' "$content" > "$path"
    log "已寫入：$path"
  fi
}

apt_install() {
  local pkgs=("$@")
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "未找到 apt-get，跳過套件安裝：${pkgs[*]}"
    return 0
  fi
  run "apt-get update -y"
  run "apt-get install -y ${pkgs[*]}"
}

# ------------------------------------------------------------
# CPU governor
# ------------------------------------------------------------
set_cpu_governor_runtime() {
  local gov="performance"
  local any=0

  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -e "$f" ]] || continue
    any=1
    run "echo \"$gov\" > \"$f\" || true"
  done

  if [[ "$any" -eq 0 ]]; then
    warn "找不到 cpufreq scaling_governor（可能是虛擬機/未啟用 cpufreq），跳過 runtime 設定。"
  else
    log "已嘗試設定 CPU governor(runtime) 為：$gov"
  fi
}

set_cpu_governor_persistent() {
  # cpufrequtils on Debian/Ubuntu uses /etc/default/cpufrequtils
  apt_install cpufrequtils || true
  local f="/etc/default/cpufrequtils"
  local c='GOVERNOR="performance"'
  write_file_if_changed "$f" "$c"

  # Try enable service if exists
  run "systemctl enable --now cpufrequtils 2>/dev/null || true"
  log "已設定 CPU governor(persistent) via $f（若系統無此服務則僅保留設定檔）。"
}

# ------------------------------------------------------------
# irqbalance
# ------------------------------------------------------------
enable_irqbalance() {
  apt_install irqbalance || true
  run "systemctl enable --now irqbalance"
  log "已啟用 irqbalance。"
}

# ------------------------------------------------------------
# Sysctl
# ------------------------------------------------------------
apply_sysctl() {
  write_file_if_changed "$SYSCTL_FILE" "$SYSCTL_CONTENT"
  run "sysctl --system"
  log "已套用 sysctl（含 memory/network）。"
}

# ------------------------------------------------------------
# THP disable
# ------------------------------------------------------------
disable_thp_runtime() {
  local base="/sys/kernel/mm/transparent_hugepage"
  if [[ -d "$base" ]]; then
    for f in "$base/enabled" "$base/defrag"; do
      [[ -e "$f" ]] || continue
      run "echo never > \"$f\" || true"
    done
    log "已嘗試停用 THP(runtime)。"
  else
    warn "找不到 THP 介面（$base），跳過 runtime 設定。"
  fi
}

# ------------------------------------------------------------
# GRUB helpers
# ------------------------------------------------------------
grub_set_timeout() {
  [[ -f "$GRUB_FILE" ]] || { warn "找不到 $GRUB_FILE，跳過 GRUB 設定。"; return 0; }
  backup_file "$GRUB_FILE"

  # Set GRUB_TIMEOUT=2 (replace if exists else append)
  if grep -qE '^\s*GRUB_TIMEOUT=' "$GRUB_FILE"; then
    run "sed -i 's/^\s*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT_VALUE}/' \"$GRUB_FILE\""
  else
    run "printf '\nGRUB_TIMEOUT=%s\n' \"$GRUB_TIMEOUT_VALUE\" >> \"$GRUB_FILE\""
  fi
  log "已設定 GRUB_TIMEOUT=${GRUB_TIMEOUT_VALUE}"
}

grub_add_cmdline_opts() {
  [[ -f "$GRUB_FILE" ]] || { warn "找不到 $GRUB_FILE，跳過 GRUB cmdline 設定。"; return 0; }

  # Ensure GRUB_CMDLINE_LINUX_DEFAULT exists
  if ! grep -qE '^\s*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    run "printf '\nGRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"\n' >> \"$GRUB_FILE\""
  fi

  # Read current value
  local current
  current="$(grep -E '^\s*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | head -n1 | sed -E 's/^\s*GRUB_CMDLINE_LINUX_DEFAULT="(.*)".*/\1/')"

  local updated="$current"
  for opt in "${GRUB_CMDLINE_ADD[@]}"; do
    if ! grep -qw -- "$opt" <<<"$updated"; then
      updated="$updated $opt"
    fi
  done
  updated="$(echo "$updated" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')"

  # Replace line
  run "sed -i -E 's|^\s*GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${updated}\"|' \"$GRUB_FILE\""
  log "已更新 GRUB_CMDLINE_LINUX_DEFAULT：$updated"
}

update_grub() {
  if command -v update-grub >/dev/null 2>&1; then
    run "update-grub"
    log "已 update-grub（需要重開機才完整生效）。"
  else
    warn "找不到 update-grub，跳過。"
  fi
}

# ------------------------------------------------------------
# Block I/O scheduler + queue tunables
# ------------------------------------------------------------
get_scheduler_candidates() {
  # Return a list (space separated) of candidates in preferred order
  local rotational="$1"
  if [[ "$rotational" == "0" ]]; then
    # SSD/NVMe
    echo "none noop mq-deadline deadline kyber bfq"
  else
    # HDD
    echo "mq-deadline deadline bfq kyber none noop"
  fi
}

set_block_scheduler_runtime() {
  local dev="$1"
  local sched_file="/sys/block/${dev}/queue/scheduler"
  local rot_file="/sys/block/${dev}/queue/rotational"

  [[ -e "$sched_file" ]] || return 0

  local rotational="0"
  [[ -e "$rot_file" ]] && rotational="$(cat "$rot_file" 2>/dev/null || echo 0)"

  local available
  available="$(cat "$sched_file" 2>/dev/null || true)"

  local chosen=""
  local candidates
  candidates="$(get_scheduler_candidates "$rotational")"

  for c in $candidates; do
    if grep -Eq "(^|[[:space:]])\[$c\]([[:space:]]|$)|(^|[[:space:]])$c([[:space:]]|$)" <<<"$available"; then
      chosen="$c"
      break
    fi
  done

  if [[ -n "$chosen" ]]; then
    run "echo \"$chosen\" > \"$sched_file\" || true"
    log "dev=$dev rotational=$rotational scheduler=$chosen (available: $available)"
  else
    warn "dev=$dev 找不到可用 scheduler（available: $available），跳過。"
  fi
}

set_block_queue_tunables() {
  local dev="$1"
  local nr="/sys/block/${dev}/queue/nr_requests"
  local ra="/sys/block/${dev}/queue/read_ahead_kb"

  [[ -e "$nr" ]] && run "echo \"$NR_REQUESTS_DEFAULT\" > \"$nr\" || true"
  [[ -e "$ra" ]] && run "echo \"$READ_AHEAD_KB_DEFAULT\" > \"$ra\" || true"
}

apply_block_io_runtime() {
  local any=0
  for d in /sys/block/*; do
    [[ -d "$d" ]] || continue
    local dev
    dev="$(basename "$d")"
    # Limit to typical disk devices; adjust if needed
    if [[ "$dev" =~ ^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)$ ]]; then
      any=1
      set_block_scheduler_runtime "$dev"
      set_block_queue_tunables "$dev"
    fi
  done

  if [[ "$any" -eq 0 ]]; then
    warn "未找到符合條件的 block device（sd*/vd*/xvd*/nvme*n*），跳過 I/O runtime 設定。"
  else
    log "已套用 block I/O runtime 設定（scheduler + queue tunables）。"
  fi
}

apply_udev_scheduler_rules() {
  write_file_if_changed "$UDEV_RULE_FILE" "$UDEV_RULE_CONTENT"
  run "udevadm control --reload-rules"
  run "udevadm trigger"
  log "已套用 udev 規則（下次裝置重新加入/開機更完整生效）。"
}

# ------------------------------------------------------------
# TRIM
# ------------------------------------------------------------
enable_fstrim() {
  run "systemctl enable --now fstrim.timer 2>/dev/null || true"
  log "已嘗試啟用 fstrim.timer。"
}

# ------------------------------------------------------------
# DNS (systemd-resolved)
# ------------------------------------------------------------
apply_dns_systemd_resolved() {
  local f="/etc/systemd/resolved.conf"
  [[ -f "$f" ]] || { warn "找不到 $f，跳過 DNS 設定。"; return 0; }
  backup_file "$f"

  # Ensure [Resolve] section exists
  if ! grep -qE '^\s*\[Resolve\]\s*$' "$f"; then
    run "printf '\n[Resolve]\n' >> \"$f\""
  fi

  # Set/replace DNS= and FallbackDNS=
  # If commented or existing, replace; else append under [Resolve]
  run "sed -i -E 's|^\s*#?\s*DNS=.*|DNS=${DNS_PRIMARY}|' \"$f\""
  run "sed -i -E 's|^\s*#?\s*FallbackDNS=.*|FallbackDNS=${DNS_FALLBACK}|' \"$f\""

  if ! grep -qE "^\s*DNS=" "$f"; then
    run "awk -v dns=\"DNS=${DNS_PRIMARY}\" 'BEGIN{added=0} {print} /^\[Resolve\]/{print dns; added=1} END{}' \"$f\" > \"${f}.tmp\" && mv \"${f}.tmp\" \"$f\""
  fi
  if ! grep -qE "^\s*FallbackDNS=" "$f"; then
    run "awk -v fdns=\"FallbackDNS=${DNS_FALLBACK}\" 'BEGIN{added=0} {print} /^\[Resolve\]/{print fdns; added=1} END{}' \"$f\" > \"${f}.tmp\" && mv \"${f}.tmp\" \"$f\""
  fi

  run "systemctl restart systemd-resolved"
  log "已更新 systemd-resolved DNS 並重啟服務。"
}

# ------------------------------------------------------------
# Services disable (optional)
# ------------------------------------------------------------
disable_unneeded_services() {
  for s in "${SERVICES_TO_DISABLE[@]}"; do
    run "systemctl disable --now \"$s\" 2>/dev/null || true"
    log "已嘗試停用服務：$s"
  done
}

# ------------------------------------------------------------
# Initramfs (optional)
# ------------------------------------------------------------
apply_initramfs_tuning() {
  apt_install lz4 || true
  write_file_if_changed "$INITRAMFS_DRIVER_POLICY" "$INITRAMFS_DRIVER_POLICY_CONTENT"
  write_file_if_changed "$INITRAMFS_COMPRESS" "$INITRAMFS_COMPRESS_CONTENT"
  if command -v update-initramfs >/dev/null 2>&1; then
    run "update-initramfs -u"
    log "已更新 initramfs（可能需要重開機）。"
  else
    warn "找不到 update-initramfs，跳過。"
  fi
}

# ------------------------------------------------------------
# One-off actions (not persistent) - exposed as functions
# ------------------------------------------------------------
oneoff_drop_caches() {
  run "sync"
  run "echo 3 > /proc/sys/vm/drop_caches"
  log "已執行 drop_caches=3（一次性）。"
}

oneoff_compact_memory() {
  run "echo 1 > /proc/sys/vm/compact_memory"
  log "已觸發 compact_memory=1（一次性）。"
}

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------
usage() {
  cat <<EOF
Usage: sudo $0 [options]

Options:
  --dry-run                 不實際修改，只輸出將執行的動作
  --enable-dns              設定 systemd-resolved DNS（預設不動 DNS）
  --dns-primary "A B"       設定 DNS=（預設: ${DNS_PRIMARY})
  --dns-fallback "A B"      設定 FallbackDNS=（預設: ${DNS_FALLBACK})

  --disable-services        停用常見非必要服務（bluetooth/cups/apache2/mysql）
  --enable-initramfs        套用 initramfs 設定（MODULES=dep, COMPRESS=lz4）並重建

  --oneoff-drop-caches      一次性清 cache（drop_caches=3）
  --oneoff-compact-memory   一次性觸發記憶體壓縮（compact_memory=1）

  -h, --help                顯示說明

預設行為（不加選項）會套用：
  - CPU governor runtime + persistent（cpufrequtils）
  - irqbalance
  - sysctl（memory/network）
  - THP runtime disable + GRUB cmdline 追加 transparent_hugepage=never + update-grub
  - block I/O runtime（scheduler/queue）+ udev rules（best-effort）
  - fstrim.timer

EOF
}

main() {
  local oneoff_drop=0
  local oneoff_compact=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --enable-dns) ENABLE_DNS=1; shift ;;
      --dns-primary) DNS_PRIMARY="$2"; shift 2 ;;
      --dns-fallback) DNS_FALLBACK="$2"; shift 2 ;;
      --disable-services) DISABLE_SERVICES=1; shift ;;
      --enable-initramfs) ENABLE_INITRAMFS=1; shift ;;
      --oneoff-drop-caches) oneoff_drop=1; shift ;;
      --oneoff-compact-memory) oneoff_compact=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知參數：$1（用 -h 看用法）" ;;
    esac
  done

  need_root

  log "開始套用調優（DRY_RUN=$DRY_RUN）"

  # Packages + core tuning
  set_cpu_governor_runtime
  set_cpu_governor_persistent

  enable_irqbalance
  apply_sysctl

  disable_thp_runtime
  grub_set_timeout
  grub_add_cmdline_opts
  update_grub

  apply_block_io_runtime
  apply_udev_scheduler_rules

  enable_fstrim

  if [[ "$ENABLE_DNS" -eq 1 ]]; then
    apply_dns_systemd_resolved
  else
    log "DNS 設定未啟用（可用 --enable-dns）"
  fi

  if [[ "$DISABLE_SERVICES" -eq 1 ]]; then
    disable_unneeded_services
  else
    log "未停用服務（可用 --disable-services）"
  fi

  if [[ "$ENABLE_INITRAMFS" -eq 1 ]]; then
    apply_initramfs_tuning
  else
    log "未套用 initramfs 調整（可用 --enable-initramfs）"
  fi

  if [[ "$oneoff_drop" -eq 1 ]]; then
    oneoff_drop_caches
  fi
  if [[ "$oneoff_compact" -eq 1 ]]; then
    oneoff_compact_memory
  fi

  log "完成。建議：如包含 GRUB/udev/THP/initramfs 變更，請安排重開機以完整生效。"
}

main "$@"
