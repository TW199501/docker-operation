#!/usr/bin/env bash

# 注意：此腳本必須在 Proxmox VE 服務器上以 root 身份運行

function header_info {
  clear
  cat <<"EOF"
    ____       __    _                ________
   / __ \___  / /_  (_)___ _____     <  /__  /
  / / / / _ \/ __ \/ / __ `/ __ \    / / /_ <
 / /_/ /  __/ /_/ / / /_/ / / / /   / /___/ /
/_____/\___/_.___/_/\__,_/_/ /_/   /_//____/
                                              (Trixie)
    ____             __                _    ____  ___
   / __ \____  _____/ /_____  _____   | |  / /  |/  /
  / / / / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
 / /_/ / /_/ / /__/ ,< /  __/ /       | |/ / /  / /
/_____/\____/\___/_/|_|\___/_/        |___/_/  /_/

EOF
}

header_info

echo -e "\n Loading..."

# 檢查是否以 root 身份運行
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

# 檢查必要的依賴項
if ! command -v whiptail >/dev/null 2>&1 || \
   ! command -v qm >/dev/null 2>&1 || \
   ! command -v pvesm >/dev/null 2>&1 || \
   ! command -v genisoimage >/dev/null 2>&1; then
  echo "Missing required dependencies. Please install: whiptail, qm, pvesm, genisoimage"
  exit 1
fi

# 詢問用戶是否要創建 VM
if whiptail --title "Debian 13 VM Setup" --yesno "Do you want to create a new Debian 13 VM?" 10 58; then
  echo "Starting VM creation process..."
  
  # 在這裡調用原來的完整腳本
  if [ -f "./debian13-vm.sh" ]; then
    bash ./debian13-vm.sh
  else
    echo "Error: Main script (debian13-vm.sh) not found!"
    exit 1
  fi
  
  echo "VM creation completed successfully!"
else
  header_info
  echo -e "\n${TAB}❌${TAB}User chose not to create a VM${CL}\n"
  exit 0
fi
