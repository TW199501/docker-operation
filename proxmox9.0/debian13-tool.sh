#!/usr/bin/env bash

# Debian 13 VM 工具腳本
# 功能：設置 root 密碼和擴展硬碟空間

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

# 擴展硬碟空間
function expand_disk() {
  msg_info "正在擴展硬碟空間..."
  
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
  
  # 詢問是否擴展硬碟
  echo -e "\n${YW}${BOLD}2. 擴展硬碟空間${CL}"
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
