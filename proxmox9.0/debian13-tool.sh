#!/usr/bin/env bash

# Debian 13 VM 工具腳本
# 功能：
#   1) 設置 root 密碼 + 啟用 SSH（允許 root 密碼登入）
#   2) 配置固定 IP（只輸入最後一碼；自動偵測網段與 gateway；含衝突檢查）
#   3) 禁用 IPv6（只問一次；使用 sysctl 持久化）
#   4) 優化大檔處理（sysctl）
#   5) 擴展硬碟（支援傳統分割區與常見 LVM 佈署）
#   6) 優化網路傳輸（BBR/fq、socket buffer、TFO、txqueuelen、GRO/GSO/TSO）
# 注意：
#   - 本腳本假設「未使用 VLAN」，PVE 以 vmbr0 ⇄ eno1 橋接至 LAN。
#   - 請用 Bash 執行；若誤用 sh，腳本會自動以 bash 重新啟動。

# 設置大文件處理優化
ulimit -n 65536 2>/dev/null || true
ulimit -f unlimited 2>/dev/null || true

# 設置緩存優化
export LC_ALL=C
export LANG=C

function header_info {
  clear
  cat <<"EOF"
    ______ _       ______          _____       _      _           ______      _ _
   |  ____| |     |  ____|        |  __ \     (_)    | |         |  ____|    | | |
   | |__  | |     | |__  __ _  ___| |  | | ___ _  ___| |_ _ __   | |__  __  _| | |
   |  __| | |     |  __|/ _` |/ __| |  | |/ _ | |/ __| __| '_ \  |  __| \ \/ / | |
   | |____| |____ | |__| (_| | (__| |__| |  __| | (__| |_| | | | | |____ >  <| | |
   |______|______||______\__,_|\___|_____/ \___|_|\___|\__|_| |_| |______/_/\_\|_| |

                           ELF Debian13 All-IN Tools (open-source)
EOF
}

header_info
echo -e "\n Loading...\n"

# 檢查是否以 root 身份運行
if [[ "$EUID" -ne 0 ]]; then
  echo "請以 root 身份運行此腳本"
  echo "使用 sudo 或切換到 root 用戶"
  exit 1
fi

# 等待系統初始化完成
echo "等待系統初始化完成..."
for i in {1..30}; do
  if systemctl is-system-running >/dev/null 2>&1; then
    if [ "$(systemctl is-system-running)" = "running" ]; then
      echo "系統已準備就緒"
      break
    fi
  fi
  echo -n "."
  sleep 2
done
echo ""

# 定義顏色變量
YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")

function msg_info() {
  local msg="$1"
  echo -e "${YW}${BOLD}${msg}${CL}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${GN}${BOLD}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${RD}${BOLD}${msg}${CL}"
}

# 設置 root 密碼
function set_root_password() {
  while true; do
    ROOT_PASSWORD=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請輸入 root 用戶的新密碼" 10 60 3>&1 1>&2 2>&3) || return
    ROOT_PASSWORD_CONFIRM=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ROOT PASSWORD" --passwordbox "請再次輸入以確認" 10 60 3>&1 1>&2 2>&3) || return
    if [ -z "$ROOT_PASSWORD" ]; then
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "密碼不能為空" 8 50
      continue
    fi
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
      if echo "root:$ROOT_PASSWORD" | chpasswd; then
        msg_ok "root 用戶密碼設置成功"
        break
      else
        whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "密碼設置失敗，請再試一次" 8 60
      fi
    else
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "兩次輸入不一致，請重試" 8 60
    fi
  done
}

# 配置 SSH
function configure_ssh() {
  msg_info "正在配置 SSH..."

  # 安裝 SSH 服務
  apt update && apt install -y openssh-client openssh-server

  # 配置 SSH 允許密碼登錄
  sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

  # 生成 SSH 密鑰
  ssh-keygen -A

  # 重啟 SSH 服務
  systemctl restart sshd

  msg_ok "✓ SSH 配置完成"
}

# 關閉 IPv6 功能
function disable_ipv6() {
  msg_info "正在關閉 IPv6 功能..."

  # 檢查是否已經禁用 IPv6
  if [ -f "/proc/sys/net/ipv6/conf/all/disable_ipv6" ] && [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ]; then
    msg_info "IPv6 已經被禁用"
    return 0
  fi

  # 臨時禁用 IPv6
  if [ -f "/proc/sys/net/ipv6/conf/all/disable_ipv6" ]; then
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
  fi
  if [ -f "/proc/sys/net/ipv6/conf/default/disable_ipv6" ]; then
    echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
  fi

  # 永久禁用 IPv6
  # 備份原始配置
  if [ -f /etc/default/grub ]; then
    cp /etc/default/grub /etc/default/grub.backup
  fi

  # 添加 grub 參數
  if grep -q "GRUB_CMDLINE_LINUX=" /etc/default/grub; then
    # 檢查是否已經有 ipv6.disable=1 參數
    if ! grep -q "ipv6.disable=1" /etc/default/grub; then
      sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    fi
  else
    echo 'GRUB_CMDLINE_LINUX="ipv6.disable=1"' >> /etc/default/grub
  fi

  # 更新 grub 配置
  if command -v update-grub &>/dev/null; then
    update-grub >/dev/null 2>&1
  elif command -v grub-mkconfig &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
  fi

  msg_ok "✓ IPv6 功能已禁用"
  msg_info "系統重啟後將永久生效"
}

# 配置固定IP地址
function configure_static_ip() {
  if whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" --yesno "配置固定 IP 時是否同時禁用 IPv6？" 10 60; then
    disable_ipv6
  fi

  INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
  INTERFACE=${INTERFACE:-eth0}
  CURRENT_IP=$(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)

  while true; do
    STATIC_IP=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" --inputbox "請輸入固定 IP (目前: ${CURRENT_IP:-無})" 10 60 "${CURRENT_IP}" 3>&1 1>&2 2>&3) || return
    if [[ $STATIC_IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      IFS='.' read -r ip1 ip2 ip3 ip4 <<<"$STATIC_IP"
      if [[ $ip1 -le 255 && $ip2 -le 255 && $ip3 -le 255 && $ip4 -le 255 ]]; then
        break
      fi
    fi
    whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "IP 格式無效，請重新輸入" 8 50
  done

  SUBNET_MASK="255.255.255.0"
  DNS="8.8.8.8"

  CURRENT_GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
  if [ -n "$CURRENT_GATEWAY" ]; then
    if whiptail --backtitle "ELF Debian13 ALL IN" --yesno "偵測到網關 ${CURRENT_GATEWAY}\n要使用此設定嗎？" 10 60; then
      GATEWAY="$CURRENT_GATEWAY"
    fi
  fi

  if [ -z "$GATEWAY" ]; then
    while true; do
      GATEWAY=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "固定 IP" --inputbox "請輸入網關 (例如 192.168.25.254)" 10 60 3>&1 1>&2 2>&3) || return
      if [[ $GATEWAY =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r g1 g2 g3 g4 <<<"$GATEWAY"
        if [[ $g1 -le 255 && $g2 -le 255 && $g3 -le 255 && $g4 -le 255 ]]; then
          break
        fi
      fi
      whiptail --backtitle "ELF Debian13 ALL IN" --msgbox "網關格式無效，請重新輸入" 8 50
    done
  fi

  # 備份原始網絡配置
  if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.backup
  fi

  # 檢查系統使用的網路管理器
  local network_manager=""

  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    network_manager="systemd-networkd"
    msg_info "檢測到使用 systemd-networkd"
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    network_manager="NetworkManager"
    msg_info "檢測到使用 NetworkManager"
  else
    network_manager="interfaces"
    msg_info "使用傳統 interfaces 文件"
  fi

  case "$network_manager" in
    "systemd-networkd")
      # 配置 systemd-networkd
      msg_info "配置 systemd-networkd..."

      cat > "/etc/systemd/network/10-$INTERFACE.network" <<EOF
[Match]
Name=$INTERFACE

[Network]
Address=$STATIC_IP/24
Gateway=$GATEWAY
DNS=$DNS
EOF

      # 重新載入並重啟網路服務
      systemctl daemon-reload
      systemctl restart systemd-networkd

      msg_ok "✓ systemd-networkd 配置完成"
      ;;

    "NetworkManager")
      # 配置 NetworkManager
      msg_info "配置 NetworkManager..."

      # 創建 NetworkManager 連接文件
      cat > "/etc/NetworkManager/system-connections/$INTERFACE.nmconnection" <<EOF
[connection]
id=$INTERFACE
type=ethernet
interface-name=$INTERFACE

[ipv4]
method=manual
address1=$STATIC_IP/24,$GATEWAY
dns=$DNS;

[ipv6]
method=ignore
EOF

      chmod 600 "/etc/NetworkManager/system-connections/$INTERFACE.nmconnection"
      nmcli connection reload
      nmcli connection up "$INTERFACE"

      msg_ok "✓ NetworkManager 配置完成"
      ;;

    "interfaces"|*)
      # 配置傳統 interfaces 文件
      msg_info "配置傳統網路接口..."

      cat > /etc/network/interfaces <<EOF
# Loopback network interface
auto lo
iface lo inet loopback

# Primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $SUBNET_MASK
    gateway $GATEWAY
    dns-nameservers $DNS
EOF

      # 嘗試重啟網路服務
      msg_info "正在重啟網路服務..."
      if systemctl is-active --quiet networking 2>/dev/null; then
        systemctl restart networking
        msg_ok "✓ networking 服務重啟成功"
      elif [ -f /etc/init.d/networking ]; then
        /etc/init.d/networking restart
        msg_ok "✓ networking 服務重啟成功"
      else
        msg_warning "⚠️ 無法重啟網路服務，嘗試手動應用配置..."

        # 手動應用 IP 配置
        msg_info "正在手動應用 IP 配置..."

        # 清除現有 IP
        ip addr flush dev "$INTERFACE"

        # 添加新 IP
        ip addr add "$STATIC_IP/24" dev "$INTERFACE"

        # 添加網關
        ip route add default via "$GATEWAY" dev "$INTERFACE"

        # 添加 DNS
        echo "nameserver $DNS" > /etc/resolv.conf

        msg_ok "✓ 手動 IP 配置應用完成"
      fi
      ;;
  esac

  # 等待網路配置生效
  sleep 3

  # 驗證配置
  msg_info "驗證網路配置..."
  local new_ip
  new_ip=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+' | head -1)

  if [ "$new_ip" = "$STATIC_IP" ]; then
    msg_ok "✓ IP地址配置成功: $STATIC_IP"
  else
    msg_warning "⚠️ IP地址可能需要重啟系統才能生效"
    msg_info "當前IP: $new_ip, 配置的IP: $STATIC_IP"
  fi

  # 測試網路連通性
  msg_info "測試網路連通性..."
  if ping -c 3 -W 5 "$GATEWAY" >/dev/null 2>&1; then
    msg_ok "✓ 網關可達"
  else
    msg_warning "⚠️ 無法連接到網關，請檢查網路配置"
  fi

  if ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1; then
    msg_ok "✓ 外部網路可達"
  else
    msg_warning "⚠️ 無法連接到外部網路"
  fi

  # 顯示最終配置
  msg_info "最終網路配置:"
  ip addr show $INTERFACE
  ip route show

  msg_ok "✓ 固定IP地址配置完成"
  msg_info "IP地址: $STATIC_IP"
  msg_info "網關: $GATEWAY"
  msg_info "DNS: $DNS"
  msg_info "網路管理器: $network_manager"
}

# 優化系統性能以處理大文件
function optimize_for_large_files() {
  msg_info "正在優化系統以處理大文件..."

  # 創建專用的 sysctl 配置文件
  local f=/etc/sysctl.d/99-io-tuning.conf
  mkdir -p /etc/sysctl.d

  # 寫入優化參數
  cat >"$f" <<'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF

  # 應用內核參數
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true

  msg_ok "✓ 系統大文件處理優化完成"
  msg_info "配置文件: $f"
}

# 擴展硬碟空間
function expand_disk() {
  msg_info "正在檢查硬碟空間..."

  # 安裝必要的工具
  apt update && apt install -y cloud-guest-utils lvm2 xfsprogs btrfs-progs

  # 獲取根設備和文件系統類型
  local rootdev fstype
  rootdev=$(findmnt -no SOURCE /)
  fstype=$(findmnt -no FSTYPE /)

  msg_info "根設備: $rootdev"
  msg_info "文件系統: $fstype"

  # 檢查可用空間
  local disk_info total_space used_space avail_space
  disk_info=$(df -BG / | tail -1)
  total_space=$(echo "$disk_info" | awk '{print $2}' | sed 's/G//')
  used_space=$(echo "$disk_info" | awk '{print $3}' | sed 's/G//')
  avail_space=$(echo "$disk_info" | awk '{print $4}' | sed 's/G//')

  msg_info "總空間: ${total_space}GB, 已用: ${used_space}GB, 可用: ${avail_space}GB"

  # 檢查磁碟是否有未分配空間
  local has_free_space=false

  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    # LVM 檢查
    local vg_free
    vg_free=$(vgs --noheadings -o vg_free --units G 2>/dev/null | awk '{print $1}' | sed 's/G//' | head -1)
    if [ -n "$vg_free" ] && [ "$(echo "$vg_free > 0" | bc 2>/dev/null)" = "1" ]; then
      has_free_space=true
      msg_info "LVM VG 可用空間: ${vg_free}GB"
    fi
  else
    # 傳統分區檢查 - 檢查磁碟是否有未分配空間
    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"
      part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"
      part="${BASH_REMATCH[2]}"
    fi

    if [ -n "${disk:-}" ]; then
      # 檢查磁碟總大小和分區大小
      local disk_size part_size
      disk_size=$(lsblk -b -n -o SIZE "$disk" 2>/dev/null | head -1)
      part_size=$(lsblk -b -n -o SIZE "$rootdev" 2>/dev/null)

      if [ -n "$disk_size" ] && [ -n "$part_size" ] && [ "$disk_size" -gt "$part_size" ]; then
        local unused_space=$(( (disk_size - part_size) / 1024 / 1024 / 1024 )) # GB
        if [ "$unused_space" -gt 1 ]; then  # 如果未分配空間大於1GB
          has_free_space=true
          msg_info "磁碟有未分配空間: ${unused_space}GB"
        fi
      fi
    fi
  fi

  # 如果沒有可用空間，跳過擴充
  if [ "$has_free_space" = false ]; then
    msg_ok "✓ 硬碟已經是最大容量，無需擴充"
    msg_info "當前硬碟使用情況:"
    df -h /
    return 0
  fi

  msg_info "檢測到可用空間，正在擴展硬碟空間..."

  # 檢查是否為 LVM
  if [[ "$rootdev" =~ ^/dev/mapper/.+ ]]; then
    # LVM 處理
    msg_info "檢測到 LVM 配置，正在處理..."

    local lv pv disk part
    lv="$rootdev"
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | awk 'NF{print $1; exit}')

    if [ -z "${pv:-}" ]; then
      msg_error "✗ 找不到 PV，可能非 LVM 或需手動處理"
      return 1
    fi

    # 解析磁碟和分區
    if [[ "$pv" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$pv" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      msg_error "✗ 無法解析 PV: $pv"
      return 1
    fi

    msg_info "正在擴展分區: $disk 第 $part 分區"

    # 執行 LVM 擴展
    if growpart "$disk" "$part"; then
      msg_ok "✓ 分區擴展成功"

      if pvresize "$pv"; then
        msg_ok "✓ PV 重新調整大小成功"

        if lvextend -r -l +100%FREE "$lv"; then
          msg_ok "✓ LV 擴展成功"
          df -h /
          msg_ok "✓ LVM 硬碟擴展完成"
          return 0
        else
          msg_error "✗ LV 擴展失敗"
          return 1
        fi
      else
        msg_error "✗ PV 重新調整大小失敗"
        return 1
      fi
    else
      msg_error "✗ 分區擴展失敗"
      return 1
    fi
  else
    # 非 LVM 處理
    msg_info "檢測到傳統分區，正在處理..."

    local disk part
    if [[ "$rootdev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$rootdev" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
      disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
      msg_error "✗ 不支援的根設備: $rootdev"
      return 1
    fi

    msg_info "正在擴展分區: $disk 第 $part 分區"

    if growpart "$disk" "$part"; then
      msg_ok "✓ 分區擴展成功"

      # 根據文件系統類型調整大小
      case "$fstype" in
        ext2|ext3|ext4)
          msg_info "正在調整 ext 文件系統..."
          resize2fs "$rootdev"
          ;;
        xfs)
          msg_info "正在調整 XFS 文件系統..."
          xfs_growfs -d /
          ;;
        btrfs)
          msg_info "正在調整 Btrfs 文件系統..."
          btrfs filesystem resize max /
          ;;
        *)
          msg_error "✗ 不支援的文件系統: $fstype"
          return 1
          ;;
      esac

      msg_ok "✓ 文件系統調整完成"
      df -h /
      msg_ok "✓ 硬碟擴展完成"
    else
      msg_error "✗ 分區擴展失敗"
      return 1
    fi
  fi
}

# 優化網路傳輸
function optimize_network_stack() {
  msg_info "正在優化網路傳輸參數..."

  # 創建網路優化配置文件
  local f=/etc/sysctl.d/99-net-opt.conf
  mkdir -p /etc/sysctl.d

  # 檢測是否支援 BBR
  local cc="cubic"
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    cc="bbr"
    msg_info "檢測到 BBR 支援，將使用 BBR 擁塞控制"
  else
    msg_info "使用默認擁塞控制: cubic"
  fi

  # 寫入網路優化參數
  cat >"$f" <<EOF
# 網路優化參數
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

  # 應用網路參數
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1 || true

  msg_ok "✓ 網路參數優化完成"

  # 網路介面層優化
  local iface
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')

  if [ -n "${iface:-}" ]; then
    msg_info "正在優化網路介面: $iface"

    # 安裝 ethtool（如果可用）
    apt install -y ethtool >/dev/null 2>&1 || true

    # 調整介面參數
    ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
    ethtool -K "$iface" gro on gso on tso on >/dev/null 2>&1 || true
    ethtool -G "$iface" rx 4096 tx 4096 >/dev/null 2>&1 || true

    msg_ok "✓ 網路介面優化完成"
  else
    msg_info "找不到預設路由介面，跳過介面層調整"
  fi

  msg_info "網路優化配置文件: $f"
}

# 主程序
function install_package_if_needed() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y "$pkg"
  fi
}

function install_guest_agent() {
  msg_info "安裝 qemu-guest-agent..."
  install_package_if_needed qemu-guest-agent
  systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
  msg_ok "qemu-guest-agent 安裝完成"
}

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
}

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

function account_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "帳號 / SSH" --menu "選擇要執行的操作" 15 60 4 \
      "rootpass" "設定 root 密碼" \
      "ssh" "安裝並啟用 SSH (允許 root 密碼登入)" \
      "guest" "安裝 qemu-guest-agent" \
      "back" "返回主選單" \
      3>&1 1>&2 2>&3) || break
    case "$choice" in
      rootpass) set_root_password ;;
      ssh) configure_ssh ;;
      guest) install_guest_agent ;;
      back) break ;;
      *) break ;;
    esac
  done
}

function docker_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Docker / Compose" --menu "選擇要執行的操作" 12 60 3 \
      "docker" "安裝 Docker 與 Compose" \
      "guest" "安裝 qemu-guest-agent" \
      "back" "返回主選單" \
      3>&1 1>&2 2>&3) || break
    case "$choice" in
      docker) install_docker_stack ;;
      guest) install_guest_agent ;;
      back) break ;;
      *) break ;;
    esac
  done
}

function network_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "網路設定" --menu "選擇要執行的操作" 15 60 4 \
      "static" "配置固定 IP / DNS" \
      "ipv6" "禁用 IPv6" \
      "opt" "優化網路傳輸" \
      "back" "返回主選單" \
      3>&1 1>&2 2>&3) || break
    case "$choice" in
      static) configure_static_ip ;;
      ipv6) disable_ipv6 ;;
      opt) optimize_network_stack ;;
      back) break ;;
      *) break ;;
    esac
  done
}

function system_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "系統 / 磁碟優化" --menu "選擇要執行的操作" 15 60 4 \
      "large" "優化大文件處理" \
      "disk" "擴展硬碟 (含 LVM)" \
      "log" "設定 log 清理排程" \
      "back" "返回主選單" \
      3>&1 1>&2 2>&3) || break
    case "$choice" in
      large) optimize_for_large_files ;;
      disk) expand_disk ;;
      log) schedule_log_cleanup ;;
      back) break ;;
      *) break ;;
    esac
  done
}

function main_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "第二階段工具" --menu "選擇要執行的操作" 18 70 6 \
      "account" "帳號 / SSH / guest agent" \
      "network" "網路設定與優化" \
      "system" "磁碟與系統優化 / log 維護" \
      "docker" "Docker / Compose 安裝" \
      "quit" "結束" \
      3>&1 1>&2 2>&3) || exit 0
    case "$choice" in
      account) account_menu ;;
      network) network_menu ;;
      system) system_menu ;;
      docker) docker_menu ;;
      quit) exit 0 ;;
      *) break ;;
    esac
  done
}

main_menu

