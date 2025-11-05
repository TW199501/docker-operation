#!/usr/bin/env bash

# Debian 13 VM 工具腳本
# 功能：設置 root 密碼、配置網絡和擴展硬碟空間

# 設置大文件處理優化
ulimit -n 65536 2>/dev/null || true
ulimit -f unlimited 2>/dev/null || true

# 設置緩存優化
export LC_ALL=C
export LANG=C

function header_info {
  clear
  cat <<"EOF"
    ____       __    _               ________  __  _______  
   / __ \___  / /_  (_)___ _____    /_  __/ / / / /_  __/  
  / / / / _ \/ __ \/ / __ `/ __ \    / / / / / /   / /     
 / /_/ /  __/ /_/ / / /_/ / / / /   / / / /_/ /   / /      
/_____/\___/_.___/_/\__,_/_/ /_/   /_/  \____/   /_/       
                                                         
    ______            __  _
   /_  __/___  ____  / /_(_)___  ____
    / / / __ \/ __ \/ __/ / __ \/ __ \
   / / / /_/ / /_/ / /_/ / /_/ / / / /
  /_/  \____/\____/\__/_/\____/_/ /_/

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
  msg_info "正在設置 root 用戶密碼..."
  
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
        # 設置密碼
        echo "root:$ROOT_PASSWORD" | chpasswd
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
  if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ]; then
    msg_info "IPv6 已經被禁用"
    return 0
  fi
  
  # 臨時禁用 IPv6
  echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
  echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
  
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
  msg_info "正在配置固定IP地址..."
  
  # 詢問是否同時禁用 IPv6
  read -p "是否在配置固定IP時禁用 IPv6? (y/N): " DISABLE_IPV6
  if [[ "$DISABLE_IPV6" =~ ^[Yy]$ ]]; then
    disable_ipv6
  fi
  
  # 獲取當前網絡接口
  INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
  if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"  # 默認接口名
  fi
  
  # 顯示當前網絡配置
  msg_info "當前網絡接口: $INTERFACE"
  ip addr show $INTERFACE
  
  # 輸入固定IP地址
  while true; do
    read -p "請輸入固定IP地址 (例如: 192.168.1.100): " STATIC_IP
    if [ -n "$STATIC_IP" ]; then
      # 驗證IP地址格式
      if [[ $STATIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$STATIC_IP"
        if [[ $ip1 -le 255 && $ip2 -le 255 && $ip3 -le 255 && $ip4 -le 255 ]]; then
          break
        fi
      fi
      msg_error "✗ IP地址格式無效，請重新輸入"
    else
      msg_error "✗ IP地址不能為空"
    fi
  done
  
  # 自動計算子網掩碼和網關
  IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$STATIC_IP"
  SUBNET_MASK="255.255.255.0"  # 默認子網掩碼
  GATEWAY="$ip1.$ip2.$ip3.1"    # 默認網關
  DNS="8.8.8.8"                # 默認DNS
  
  # 備份原始網絡配置
  if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.backup
  fi
  
  # 配置網絡接口
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
  
  # 重啟網絡服務
  msg_info "正在重啟網絡服務..."
  systemctl restart networking
  
  # 顯示新配置
  msg_info "新的網絡配置:"
  ip addr show $INTERFACE
  
  msg_ok "✓ 固定IP地址配置完成"
  msg_info "IP地址: $STATIC_IP"
  msg_info "網關: $GATEWAY"
  msg_info "DNS: $DNS"
}

# 優化系統性能以處理大文件
function optimize_for_large_files() {
  msg_info "正在優化系統以處理大文件..."
  
  # 調整內核參數以更好地處理大文件
  echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf 2>/dev/null || true
  echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf 2>/dev/null || true
  echo 'vm.swappiness = 10' >> /etc/sysctl.conf 2>/dev/null || true
  
  # 應用內核參數
  sysctl -p >/dev/null 2>&1 || true
  
  msg_ok "✓ 系統優化完成"
}

# 擴展硬碟空間
function expand_disk() {
  msg_info "正在擴展硬碟空間..."
  
  # 優化系統以處理大文件操作
  optimize_for_large_files
  
  # 安裝必要的工具
  apt update && apt install -y cloud-guest-utils
  
  # 檢查分區
  msg_info "檢查磁碟分區..."
  lsblk
  
  # 嘗試擴展 sda3 分區
  if growpart /dev/sda 3 2>/dev/null; then
    msg_ok "✓ 分區擴展成功"
    resize2fs /dev/sda3
    msg_ok "✓ 文件系統調整完成"
  else
    # 如果 sda3 失敗，嘗試 sda1
    msg_info "嘗試擴展 sda1 分區..."
    if growpart /dev/sda 1 2>/dev/null; then
      msg_ok "✓ 分區擴展成功"
      resize2fs /dev/sda1
      msg_ok "✓ 文件系統調整完成"
    else
      msg_error "✗ 無法擴展分區，請手動檢查分區結構"
      return 1
    fi
  fi
  
  # 顯示最終磁碟使用情況
  df -h
  msg_ok "✓ 硬碟擴展完成"
}

# 主程序
function main() {
  msg_info "=== Debian 13 VM 工具 ==="
  
  # 詢問是否設置密碼
  echo -e "\n${YW}${BOLD}1. 設置 root 密碼${CL}"
  read -p "是否要設置 root 密碼? (y/N): " SET_PASSWORD
  
  if [[ "$SET_PASSWORD" =~ ^[Yy]$ ]]; then
    set_root_password
    configure_ssh
  else
    msg_info "跳過密碼設置"
  fi
  
  # 詢問是否配置固定IP
  echo -e "\n${YW}${BOLD}2. 配置固定IP地址${CL}"
  read -p "是否要配置固定IP地址? (y/N): " CONFIG_STATIC_IP
  
  if [[ "$CONFIG_STATIC_IP" =~ ^[Yy]$ ]]; then
    configure_static_ip
  else
    msg_info "跳過固定IP配置"
  fi
  
  # 詢問是否禁用 IPv6
  echo -e "\n${YW}${BOLD}3. 禁用 IPv6${CL}"
  read -p "是否要禁用 IPv6? (y/N): " DISABLE_IPV6
  
  if [[ "$DISABLE_IPV6" =~ ^[Yy]$ ]]; then
    disable_ipv6
  else
    msg_info "跳過 IPv6 禁用"
  fi
  
  # 詢問是否優化大文件處理
  echo -e "\n${YW}${BOLD}4. 優化大文件處理${CL}"
  read -p "是否要優化系統以更好地處理大文件? (y/N): " OPTIMIZE_LARGE_FILES
  
  if [[ "$OPTIMIZE_LARGE_FILES" =~ ^[Yy]$ ]]; then
    optimize_for_large_files
  else
    msg_info "跳過大文件處理優化"
  fi
  
  # 詢問是否擴展硬碟
  echo -e "\n${YW}${BOLD}5. 擴展硬碟空間${CL}"
  read -p "是否要擴展硬碟空間? (y/N): " EXPAND_DISK
  
  if [[ "$EXPAND_DISK" =~ ^[Yy]$ ]]; then
    expand_disk
  else
    msg_info "跳過硬碟擴展"
  fi
  
  msg_ok "\n=== 所有操作完成 ==="
  msg_info "您可以使用 SSH 連接到此虛擬機"
}

# 執行主程序
main
