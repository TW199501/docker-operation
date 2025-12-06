#!/usr/bin/env bash

# LXC 容器密碼設置和 SSH 安裝腳本
# 功能：自動查找 LXC 容器，設置 root 密碼並安裝 SSH

function header_info {
  clear
  cat <<"EOF"
    __    ________  _________    _________   __  ____________
   / /   / ____/  |/  / ____/   / ____/   | / / / / ____/ __ \
  / /   / /   / /|_/ / /       / /   / /| |/ / / / __/ / /_/ /
 / /___/ /___/ /  / / /___    / /___/ ___ / /_/ / /___/ ____/
/_____/\____/_/  /_/\____/    \____/_/  |_/_____/_____/_/

    ____  __  _______  __________  ____  ____  __
   / __ \/ / / / ___/ /_  __/ __ \/ __ \/ __ \/ /
  / /_/ / /_/ /\__ \   / / / / / / /_/ / / / / /
 / ____/ __  /___/ /  / / / /_/ / _, _/ /_/ / /
/_/   /_/ /_//____/  /_/  \____/_/ |_|\____/_/

EOF
}

header_info
echo -e "\n Loading...\n"

# 檢查是否在 Proxmox 主機上運行
if ! command -v pct &>/dev/null; then
  echo "錯誤：此腳本必須在 Proxmox 主機上運行"
  echo "找不到 pct 命令"
  exit 1
fi

# 檢查是否以 root 身份運行
if [[ "$EUID" -ne 0 ]]; then
  echo "請以 root 身份運行此腳本"
  echo "使用 sudo 或切換到 root 用戶"
  exit 1
fi

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

# 查找 LXC 容器
function find_lxc_container() {
  msg_info "正在查找 LXC 容器..."

  # 顯示所有 LXC 容器
  echo "可用的 LXC 容器："
  pct list

  # 詢問用戶輸入容器名稱或 ID
  while true; do
    read -p "請輸入容器名稱或 ID: " CONTAINER_ID

    if [ -n "$CONTAINER_ID" ]; then
      # 檢查是否為數字（ID）
      if [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
        if pct status $CONTAINER_ID &>/dev/null; then
          echo "找到容器 ID: $CONTAINER_ID"
          break
        else
          msg_error "找不到 ID 為 $CONTAINER_ID 的容器"
        fi
      else
        # 按名稱查找
        FOUND_ID=$(pct list | grep -i "$CONTAINER_ID" | awk '{print $1}' | head -1)
        if [ -n "$FOUND_ID" ]; then
          CONTAINER_ID=$FOUND_ID
          echo "找到容器 '$CONTAINER_ID' 對應的 ID: $CONTAINER_ID"
          break
        else
          msg_error "找不到名稱包含 '$CONTAINER_ID' 的容器"
        fi
      fi
    else
      msg_error "容器 ID 或名稱不能為空"
    fi
  done

  # 檢查容器狀態，如果停止則啟動
  if ! pct status $CONTAINER_ID | grep -q "running"; then
    msg_info "容器未運行，正在啟動..."
    pct start $CONTAINER_ID
    sleep 3  # 等待容器啟動
  fi

  msg_ok "✓ 容器準備就緒"
}

# 設置 root 密碼
function set_root_password() {
  msg_info "正在設置容器 root 密碼..."

  while true; do
    # 輸入密碼
    read -s -p "請輸入 root 用戶的新密碼: " ROOT_PASSWORD
    echo

    # 確認密碼
    read -s -p "請再次輸入密碼以確認: " ROOT_PASSWORD_CONFIRM
    echo

    # 檢查密碼是否匹配
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
      if [ -n "$ROOT_PASSWORD" ]; then
        # 在容器中設置密碼
        echo "root:$ROOT_PASSWORD" | pct push $CONTAINER_ID - root:/tmp/passwd_input
        pct exec $CONTAINER_ID -- chpasswd < /tmp/passwd_input
        pct exec $CONTAINER_ID -- rm /tmp/passwd_input

        if [ $? -eq 0 ]; then
          msg_ok "✓ root 用戶密碼設置成功"
          break
        else
          msg_error "✗ 密碼設置失敗，請重試"
        fi
      else
        msg_error "✗ 密碼不能為空，請重試"
      fi
    else
      msg_error "✗ 兩次輸入的密碼不匹配，請重試"
    fi
  done
}

# 安裝和配置 SSH
function install_ssh() {
  msg_info "正在安裝和配置 SSH..."

  # 檢查容器類型並安裝 SSH
  pct exec $CONTAINER_ID -- which apt &>/dev/null
  if [ $? -eq 0 ]; then
    # Debian/Ubuntu 系統
    pct exec $CONTAINER_ID -- apt update
    pct exec $CONTAINER_ID -- apt install -y openssh-server openssh-client
  else
    pct exec $CONTAINER_ID -- which yum &>/dev/null
    if [ $? -eq 0 ]; then
      # CentOS/RHEL 系統
      pct exec $CONTAINER_ID -- yum install -y openssh-server openssh-client
    else
      pct exec $CONTAINER_ID -- which apk &>/dev/null
      if [ $? -eq 0 ]; then
        # Alpine 系統
        pct exec $CONTAINER_ID -- apk update
        pct exec $CONTAINER_ID -- apk add openssh
      else
        msg_error "✗ 無法識別容器系統類型，請手動安裝 SSH"
        return 1
      fi
    fi
  fi

  # 配置 SSH 允許 root 登錄
  pct exec $CONTAINER_ID -- sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config 2>/dev/null || \
  pct exec $CONTAINER_ID -- sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/g' /etc/ssh/sshd_config 2>/dev/null || \
  pct exec $CONTAINER_ID -- sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/g' /etc/ssh/sshd_config 2>/dev/null

  # 配置密碼認證
  pct exec $CONTAINER_ID -- sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config 2>/dev/null || \
  pct exec $CONTAINER_ID -- sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config 2>/dev/null

  # 生成 SSH 密鑰
  pct exec $CONTAINER_ID -- ssh-keygen -A 2>/dev/null || true

  # 啟動 SSH 服務
  pct exec $CONTAINER_ID -- systemctl restart ssh 2>/dev/null || \
  pct exec $CONTAINER_ID -- systemctl restart sshd 2>/dev/null || \
  pct exec $CONTAINER_ID -- service ssh restart 2>/dev/null || \
  pct exec $CONTAINER_ID -- /etc/init.d/sshd restart 2>/dev/null

  msg_ok "✓ SSH 安裝和配置完成"
}

# 創建普通用戶（可選）
function create_user() {
  read -p "是否要創建普通用戶? (y/N): " CREATE_USER

  if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    while true; do
      read -p "請輸入用戶名: " USERNAME
      if [ -n "$USERNAME" ]; then
        break
      else
        msg_error "用戶名不能為空"
      fi
    done

    # 創建用戶
    pct exec $CONTAINER_ID -- adduser $USERNAME

    # 添加到 sudo 群組（如果存在）
    pct exec $CONTAINER_ID -- usermod -aG sudo $USERNAME 2>/dev/null || \
    pct exec $CONTAINER_ID -- usermod -aG wheel $USERNAME 2>/dev/null

    msg_ok "✓ 用戶 '$USERNAME' 創建完成"
  else
    msg_info "跳過用戶創建"
  fi
}

# 驗證 IP 地址格式
function validate_ip() {
  local ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$ip"
    if [[ $ip1 -le 255 && $ip2 -le 255 && $ip3 -le 255 && $ip4 -le 255 ]]; then
      return 0  # 驗證通過
    fi
  fi
  return 1  # 驗證失敗
}

# 輸入並驗證 IP 地址
function input_ip_address() {
  local prompt=$1
  local var_name=$2
  while true; do
    read -p "$prompt" input_value
    if [ -n "$input_value" ]; then
      if validate_ip "$input_value"; then
        eval "$var_name=\"$input_value\""
        break
      else
        msg_error "✗ IP 地址格式無效，請重新輸入"
      fi
    else
      msg_error "✗ IP 地址不能為空"
    fi
  done
}

# 輸入網絡參數
function input_network_parameters() {
  # 輸入固定 IP 地址
  input_ip_address "請輸入固定 IP 地址 (例如: 192.168.1.100): " STATIC_IP

  # 根據模式決定是否手動輸入子網掩碼和網關
  if [ "$MODE" = "direct" ]; then
    # 輸入子網掩碼
    input_ip_address "請輸入子網掩碼 (例如: 255.255.255.0): " SUBNET_MASK

    # 輸入網關
    input_ip_address "請輸入網關地址 (例如: 192.168.1.1): " GATEWAY
  else
    # 自動計算網關地址（基於IP地址）
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$STATIC_IP"
    GATEWAY="$ip1.$ip2.$ip3.1"  # 默認網關為同網段的 .1
    SUBNET_MASK="255.255.255.0"   # 默認子網掩碼
  fi

  # 輸入 DNS 服務器
  read -p "請輸入 DNS 服務器 (默認: 8.8.8.8): " DNS_SERVER
  if [ -z "$DNS_SERVER" ]; then
    DNS_SERVER="8.8.8.8"  # 默認 DNS
  else
    # 驗證 DNS 服務器地址格式
    if ! validate_ip "$DNS_SERVER"; then
      msg_error "✗ DNS 服務器地址格式無效，使用默認 DNS"
      DNS_SERVER="8.8.8.8"
    fi
  fi
}

# 設置固定對外 IP 地址
function set_static_ip() {
  read -p "是否要設置固定對外 IP 地址? (y/N): " SET_STATIC_IP

  if [[ "$SET_STATIC_IP" =~ ^[Yy]$ ]]; then
    # 詢問網絡配置方式
    echo -e "\n請選擇網絡配置方式："
    echo "1) 容器內部固定 IP (默認網橋模式)"
    echo "2) 容器直接對外固定 IP (MAC VLAN/IP VLAN 模式)"
    read -p "請選擇 (1/2, 默認為 1): " NETWORK_MODE

    if [ "$NETWORK_MODE" = "2" ]; then
      # MAC VLAN/IP VLAN 模式
      msg_info "配置容器直接對外固定 IP..."
      MODE="direct"

      # 輸入網絡參數
      input_network_parameters

      # 配置 Proxmox 容器網絡為 MAC VLAN
      msg_info "正在配置 Proxmox 容器網絡..."
      # 這需要在 Proxmox 主機上執行
      echo "請在 Proxmox 主機上執行以下命令："
      echo "pct set $CONTAINER_ID -net0 macvlan=vmbr0,ip=$STATIC_IP/$SUBNET_MASK,gw=$GATEWAY"
      echo "或使用 IP VLAN (需要先配置 IP VLAN)："
      echo "pct set $CONTAINER_ID -net0 ipvlan=vmbr0,ip=$STATIC_IP/$SUBNET_MASK,gw=$GATEWAY"

      msg_info "請手動執行上述命令後按回車繼續..."
      read -p ""

      # 在容器內配置 DNS
      msg_info "正在配置 DNS..."
      pct exec $CONTAINER_ID -- sh -c "echo 'nameserver $DNS_SERVER' > /etc/resolv.conf"

      msg_ok "✓ 容器直接對外固定 IP 設置完成"
      msg_info "對外 IP 地址: $STATIC_IP"
      msg_info "子網掩碼: $SUBNET_MASK"
      msg_info "網關: $GATEWAY"
      msg_info "DNS: $DNS_SERVER"
    else
      # 默認網橋模式
      msg_info "配置容器內部固定 IP..."
      MODE="bridge"

      # 獲取當前網絡接口
      INTERFACE=$(pct exec $CONTAINER_ID -- ip route | grep default | awk '{print $5}' | head -1)
      if [ -z "$INTERFACE" ]; then
        INTERFACE="eth0"  # 默認接口名
      fi

      msg_info "檢測到網絡接口: $INTERFACE"

      # 顯示當前 IP 地址
      msg_info "當前 IP 配置："
      pct exec $CONTAINER_ID -- ip addr show $INTERFACE

      # 輸入網絡參數
      input_network_parameters

      # 備份原始網絡配置
      msg_info "正在備份原始網絡配置..."
      pct exec $CONTAINER_ID -- cp /etc/network/interfaces /etc/network/interfaces.backup 2>/dev/null || true

      # 配置固定 IP
      msg_info "正在配置固定 IP 地址..."
      NETWORK_CONFIG="# Loopback network interface
auto lo
iface lo inet loopback

# Primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $SUBNET_MASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVER"

      # 將配置寫入容器
      echo "$NETWORK_CONFIG" | pct push $CONTAINER_ID - /etc/network/interfaces

      # 重啟網絡服務
      msg_info "正在重啟網絡服務..."
      pct exec $CONTAINER_ID -- systemctl restart networking 2>/dev/null || \
      pct exec $CONTAINER_ID -- service networking restart 2>/dev/null || \
      pct exec $CONTAINER_ID -- ifdown $INTERFACE \; ifup $INTERFACE 2>/dev/null

      # 驗證新配置
      sleep 3
      msg_info "新的 IP 配置："
      pct exec $CONTAINER_ID -- ip addr show $INTERFACE

      msg_ok "✓ 容器內部固定 IP 設置完成"
      msg_info "IP 地址: $STATIC_IP"
      msg_info "子網掩碼: $SUBNET_MASK"
      msg_info "網關: $GATEWAY"
      msg_info "DNS: $DNS_SERVER"
    fi
  else
    msg_info "跳過固定 IP 設置"
  fi
}

# 診斷和修復網絡問題
function diagnose_network() {
  msg_info "正在診斷網絡連接..."

  # 檢查容器網絡接口
  msg_info "檢查網絡接口："
  NETWORK_INTERFACES=$(pct exec $CONTAINER_ID -- ip link show 2>/dev/null | grep -E '^[0-9]+:' | grep -v 'lo:' | awk -F: '{print $2}' | xargs)
  if [ -z "$NETWORK_INTERFACES" ]; then
    msg_error "✗ 未找到網絡接口"
    return 1
  fi
  echo "網絡接口: $NETWORK_INTERFACES"

  # 檢查 IP 地址
  msg_info "檢查 IP 地址："
  IP_ADDRESSES=$(pct exec $CONTAINER_ID -- ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
  if [ -z "$IP_ADDRESSES" ]; then
    msg_error "✗ 未分配 IP 地址"

    # 嘗試重新啟動網絡服務
    msg_info "嘗試重新啟動網絡服務..."
    pct exec $CONTAINER_ID -- systemctl restart networking 2>/dev/null || \
    pct exec $CONTAINER_ID -- service networking restart 2>/dev/null || \
    pct exec $CONTAINER_ID -- dhclient 2>/dev/null

    # 再次檢查 IP 地址
    sleep 3
    IP_ADDRESSES=$(pct exec $CONTAINER_ID -- ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
    if [ -z "$IP_ADDRESSES" ]; then
      msg_error "✗ 仍然無法獲取 IP 地址，請手動檢查網絡配置"
      return 1
    else
      msg_ok "✓ 成功獲取 IP 地址: $IP_ADDRESSES"
    fi
  else
    msg_ok "✓ IP 地址: $IP_ADDRESSES"
  fi

  # 檢查默認網關
  msg_info "檢查默認網關："
  DEFAULT_GATEWAY=$(pct exec $CONTAINER_ID -- ip route | grep default | awk '{print $3}' | head -1)
  if [ -n "$DEFAULT_GATEWAY" ]; then
    msg_ok "✓ 默認網關: $DEFAULT_GATEWAY"
  else
    msg_error "✗ 未設置默認網關"
  fi

  # 檢查 DNS 設置
  msg_info "檢查 DNS 設置："
  if pct exec $CONTAINER_ID -- cat /etc/resolv.conf &>/dev/null; then
    DNS_SERVERS=$(pct exec $CONTAINER_ID -- cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
    if [ -n "$DNS_SERVERS" ]; then
      msg_ok "✓ DNS 服務器: $DNS_SERVERS"
      # 驗證 DNS 服務器地址格式
      for dns in $DNS_SERVERS; do
        if ! validate_ip "$dns"; then
          msg_error "✗ DNS 服務器 $dns 格式無效"
        fi
      done
    else
      msg_error "✗ 未設置 DNS 服務器"
      # 添加默認 DNS
      pct exec $CONTAINER_ID -- echo "nameserver 8.8.8.8" >> /etc/resolv.conf 2>/dev/null || \
      msg_error "✗ 無法添加 DNS 服務器"
    fi
  else
    msg_error "✗ 無法讀取 /etc/resolv.conf"
  fi

  # 測試網絡連接
  msg_info "測試網絡連接："
  if pct exec $CONTAINER_ID -- ping -c 1 8.8.8.8 &>/dev/null; then
    msg_ok "✓ 能夠連接到外部網絡"
  else
    msg_error "✗ 無法連接到外部網絡"

    # 檢查防火牆設置
    msg_info "檢查防火牆設置..."
    if pct exec $CONTAINER_ID -- which iptables &>/dev/null; then
      FIREWALL_RULES=$(pct exec $CONTAINER_ID -- iptables -L | grep -i drop)
      if [ -n "$FIREWALL_RULES" ]; then
        msg_error "✗ 檢測到可能阻止連接的防火牆規則"
      fi
    fi
  fi

  msg_ok "✓ 網絡診斷完成"
}

# 主程序
function main() {
  msg_info "=== LXC 容器配置工具 ==="

  # 查找容器
  find_lxc_container

  # 設置 root 密碼
  echo -e "\n${YW}${BOLD}1. 設置 root 密碼${CL}"
  set_root_password

  # 安裝 SSH
  echo -e "\n${YW}${BOLD}2. 安裝 SSH${CL}"
  install_ssh

  # 創建普通用戶
  echo -e "\n${YW}${BOLD}3. 創建普通用戶${CL}"
  create_user

  # 設置固定 IP 地址
  echo -e "\n${YW}${BOLD}4. 設置固定 IP${CL}"
  set_static_ip

  # 網絡診斷和修復
  echo -e "\n${YW}${BOLD}5. 網絡診斷${CL}"
  read -p "是否要進行網絡診斷? (Y/n): " RUN_DIAGNOSTIC
  if [[ ! "$RUN_DIAGNOSTIC" =~ ^[Nn]$ ]]; then
    diagnose_network
  else
    msg_info "跳過網絡診斷"
    # 顯示容器 IP 地址
    msg_info "\n容器網絡信息："
    pct exec $CONTAINER_ID -- ip addr show | grep 'inet ' | grep -v '127.0.0.1'
  fi

  msg_ok "\n=== 所有操作完成 ==="
  msg_info "您可以使用以下命令連接到容器："
  msg_info "ssh root@<容器IP地址>"
  msg_info "或使用：pct enter $CONTAINER_ID"
}

# 執行主程序
main
