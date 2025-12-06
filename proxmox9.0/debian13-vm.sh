#!/usr/bin/env bash

header_info() {
  cat <<"EOF"
    ____             __                _    ____  ___
   / __ \____  _____/ /_____  _____   | |  / /  |/  /
  / /_/ / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
  / / / / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
 / /_/ / /_/ / /__/ ,< /  __/ /       | |/ / /  / /
/_____/\____/\___/_/|_|\___/_/        |___/_/  /_/
EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="docker-vm"
var_os="debian"
var_version="13"
DISK_SIZE="30G"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  #post_update_to_api "failed" "${command}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  #post_update_to_api "done" "none"
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "ELF Debian13 VM install" --title "Debian 13 VM" --yesno "This will create a New Debian 13 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0+ (including 9.1.1)
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 1
    fi
    echo -e "${GN}Proxmox VE $PVE_VER is supported${CL}"
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0 and higher (including 9.1.1)
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    # Support all 9.x versions including 9.1.1
    echo -e "${GN}Proxmox VE $PVE_VER is supported${CL}"
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.9 and 9.0+ (including 9.1.1)"
  exit 1
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "ELF Debian13 VM install" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  DISK_SIZE="10G"
  HN="docker"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}OS Version: ${BGN}Debian 13${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using the above default settings${CL}"

  if (whiptail --backtitle "ELF Debian13 VM install" --title "INSTALL DOCKER" --yesno "Install Docker and Docker Compose?" 10 58); then
    echo -e "${CLOUD}${BOLD}${DGN}Install Docker: ${BGN}yes${CL}"
    INSTALL_DOCKER="yes"
  else
    echo -e "${CLOUD}${BOLD}${DGN}Install Docker: ${BGN}no${CL}"
    INSTALL_DOCKER="no"
  fi

  if (whiptail --backtitle "ELF Debian13 VM install" --title "INSTALL NODE EXPORTER" --yesno "Install Prometheus Node Exporter for monitoring?" 10 58); then
    echo -e "${CLOUD}${BOLD}${DGN}Install Node Exporter: ${BGN}yes${CL}"
    INSTALL_NODE_EXPORTER="yes"
  else
    echo -e "${CLOUD}${BOLD}${DGN}Install Node Exporter: ${BGN}no${CL}"
    INSTALL_NODE_EXPORTER="no"
  fi

  # Set Cloud-Init defaults
  CI_USER="debian"
  CI_PASSWORD="debian"
  CI_IP_CONFIG="ip=dhcp"
  CI_NAMESERVER="8.8.8.8 1.1.1.1"
  CI_SSHKEY=""
  CONFIGURE_CLOUDINIT="yes"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init User: ${BGN}debian${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init Password: ${BGN}debian${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init Network: ${BGN}DHCP${CL}"
  msg_info "⚠️  Default password is 'debian' - Please change after first login!"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "ELF Debian13 VM install" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "ELF Debian13 VM install" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="docker"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  echo -e "${HOSTNAME}${BOLD}${DGN}OS Version: ${BGN}Debian 13${CL}"

  if CPU_TYPE1=$(whiptail --backtitle "ELF Debian13 VM install" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="2048"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    fi
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
    else
      MAC="$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if (whiptail --backtitle "ELF Debian13 VM install" --title "INSTALL DOCKER" --yesno "Install Docker and Docker Compose?" 10 58); then
    echo -e "${CLOUD}${BOLD}${DGN}Install Docker: ${BGN}yes${CL}"
    INSTALL_DOCKER="yes"
  else
    echo -e "${CLOUD}${BOLD}${DGN}Install Docker: ${BGN}no${CL}"
    INSTALL_DOCKER="no"
  fi

  if (whiptail --backtitle "ELF Debian13 VM install" --title "INSTALL NODE EXPORTER" --yesno "Install Prometheus Node Exporter for monitoring?" 10 58); then
    echo -e "${CLOUD}${BOLD}${DGN}Install Node Exporter: ${BGN}yes${CL}"
    INSTALL_NODE_EXPORTER="yes"
  else
    echo -e "${CLOUD}${BOLD}${DGN}Install Node Exporter: ${BGN}no${CL}"
    INSTALL_NODE_EXPORTER="no"
  fi

  if (whiptail --backtitle "ELF Debian13 VM install" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  # Cloud-Init Configuration
  if (whiptail --backtitle "ELF Debian13 VM install" --title "CLOUD-INIT CONFIGURATION" --yesno "Configure Cloud-Init (user, password, network)?" 10 58); then
    # Username
    if CI_USER=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set Cloud-Init username" 8 58 debian --title "CLOUD-INIT USER" --cancel-button Skip 3>&1 1>&2 2>&3); then
      if [ -z "$CI_USER" ]; then
        CI_USER="debian"
      fi
      echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init User: ${BGN}$CI_USER${CL}"
    else
      CI_USER="debian"
      echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init User: ${BGN}$CI_USER (default)${CL}"
    fi

    # Password
    if CI_PASSWORD=$(whiptail --backtitle "ELF Debian13 VM install" --passwordbox "Set Cloud-Init password" 8 58 --title "CLOUD-INIT PASSWORD" --cancel-button Skip 3>&1 1>&2 2>&3); then
      if [ -z "$CI_PASSWORD" ]; then
        CI_PASSWORD="debian"
      fi
      echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init Password: ${BGN}***${CL}"
    else
      CI_PASSWORD="debian"
      echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init Password: ${BGN}*** (default)${CL}"
    fi

    # Network Configuration
    if (whiptail --backtitle "ELF Debian13 VM install" --title "NETWORK CONFIG" --yesno "Use DHCP for network configuration?" --defaultno 10 58); then
      CI_IP_CONFIG="ip=dhcp"
      echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}DHCP${CL}"
    else
      # Static IP
      if CI_IP=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set static IP address (e.g., 192.168.1.100/24)" 8 58 --title "STATIC IP" --cancel-button Skip 3>&1 1>&2 2>&3); then
        if [ -n "$CI_IP" ]; then
          # Ensure subnet mask is included
          if [[ "$CI_IP" != */* ]]; then
            CI_IP="${CI_IP}/24"
          fi
          # Gateway
          if CI_GW=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set gateway address" 8 58 --title "GATEWAY" --cancel-button Skip 3>&1 1>&2 2>&3); then
            if [ -n "$CI_GW" ]; then
              CI_IP_CONFIG="ip=${CI_IP},gw=${CI_GW}"
              echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}Static IP: $CI_IP, Gateway: $CI_GW${CL}"
            else
              CI_IP_CONFIG="ip=${CI_IP}"
              echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}Static IP: $CI_IP${CL}"
            fi
          else
            CI_IP_CONFIG="ip=${CI_IP}"
            echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}Static IP: $CI_IP${CL}"
          fi
        else
          CI_IP_CONFIG="ip=dhcp"
          echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}DHCP (fallback)${CL}"
        fi
      else
        CI_IP_CONFIG="ip=dhcp"
        echo -e "${CLOUD}${BOLD}${DGN}Network Config: ${BGN}DHCP (fallback)${CL}"
      fi
    fi

    # DNS Configuration
    if CI_DNS=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Set DNS nameservers (space-separated, e.g., 8.8.8.8 1.1.1.1)" 8 58 "8.8.8.8 1.1.1.1" --title "DNS SERVERS" --cancel-button Skip 3>&1 1>&2 2>&3); then
      if [ -n "$CI_DNS" ]; then
        CI_NAMESERVER="$CI_DNS"
        echo -e "${CLOUD}${BOLD}${DGN}DNS Servers: ${BGN}$CI_DNS${CL}"
      else
        CI_NAMESERVER="8.8.8.8 1.1.1.1"
        echo -e "${CLOUD}${BOLD}${DGN}DNS Servers: ${BGN}8.8.8.8 1.1.1.1 (default)${CL}"
      fi
    else
      CI_NAMESERVER="8.8.8.8 1.1.1.1"
      echo -e "${CLOUD}${BOLD}${DGN}DNS Servers: ${BGN}8.8.8.8 1.1.1.1 (default)${CL}"
    fi

    # SSH Public Key (optional)
    if CI_SSHKEY=$(whiptail --backtitle "ELF Debian13 VM install" --inputbox "Paste SSH public key (optional, leave blank to skip)" 10 58 --title "SSH PUBLIC KEY" --cancel-button Skip 3>&1 1>&2 2>&3); then
      if [ -n "$CI_SSHKEY" ]; then
        echo -e "${CLOUD}${BOLD}${DGN}SSH Key: ${BGN}Configured${CL}"
      else
        CI_SSHKEY=""
        echo -e "${CLOUD}${BOLD}${DGN}SSH Key: ${BGN}Not configured${CL}"
      fi
    else
      CI_SSHKEY=""
      echo -e "${CLOUD}${BOLD}${DGN}SSH Key: ${BGN}Not configured${CL}"
    fi

    CONFIGURE_CLOUDINIT="yes"
  else
    # Use defaults
    CI_USER="debian"
    CI_PASSWORD="debian"
    CI_IP_CONFIG="ip=dhcp"
    CI_NAMESERVER="8.8.8.8 1.1.1.1"
    CI_SSHKEY=""
    CONFIGURE_CLOUDINIT="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}Using defaults (debian/debian, DHCP)${CL}"
  fi

  if (whiptail --backtitle "ELF Debian13 VM install" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Debian 13 VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "ELF Debian13 VM install" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}
check_root
arch_check
pve_check
ssh_check
start_script
#post_to_api_vm

msg_info "Validating Storage"
# Suppress errors from unavailable storage backends (e.g., offline PBS)
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images 2>/dev/null | awk 'NR>1')
VALID=$(pvesm status -content images 2>/dev/null | awk 'NR>1')

# Check if any storage backends failed to connect
if pvesm status -content images 2>&1 | grep -qi "error\|can't connect\|connection refused"; then
  echo -e "${YW}ℹ️  Note: Some storage backends are currently unavailable (this won't affect VM creation)${CL}"
fi

# Validate that we have at least one available storage
if [ ${#STORAGE_MENU[@]} -eq 0 ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "ELF Debian13 VM install" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
# 檢查本地是否已有映像檔，並檢查版本
LOCAL_IMAGE_DIR="/var/lib/vz/template/iso"
LOCAL_IMAGE="$LOCAL_IMAGE_DIR/debian-13-nocloud-$(dpkg --print-architecture).qcow2"
REMOTE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-$(dpkg --print-architecture).qcow2"

# 添加強制更新選項
FORCE_UPDATE=false
if [ "$1" == "--force-update" ]; then
  FORCE_UPDATE=true
  msg_info "強制更新模式：將下載最新映像檔"
fi

# 檢查本地映像檔是否存在且不是強制更新模式
if [ -f "$LOCAL_IMAGE" ] && [ -s "$LOCAL_IMAGE" ] && [ "$FORCE_UPDATE" = false ]; then
  # 檢查本地映像檔的修改時間
  LOCAL_MOD_TIME=$(stat -c %Y "$LOCAL_IMAGE")
  CURRENT_TIME=$(date +%s)
  DIFF_DAYS=$(( (CURRENT_TIME - LOCAL_MOD_TIME) / 86400 ))

  # 如果映像檔超過30天未更新，提示用戶
  if [ $DIFF_DAYS -gt 30 ]; then
    msg_info "本地映像檔已有 $DIFF_DAYS 天未更新"
    if (whiptail --backtitle "ELF Debian13 VM install" --title "映像檔更新" --yesno "本地映像檔已有 $DIFF_DAYS 天未更新，是否下載最新版本？" 10 60); then
      msg_info "用戶選擇更新映像檔"
      URL="$REMOTE_URL"
      USE_LOCAL_IMAGE=false
    else
      msg_info "用戶選擇使用現有映像檔"
      URL="$LOCAL_IMAGE"
      USE_LOCAL_IMAGE=true
    fi
  else
    msg_info "找到本地 Debian 13 映像檔 (修改於 $DIFF_DAYS 天前)"
    URL="$LOCAL_IMAGE"
    USE_LOCAL_IMAGE=true
  fi
else
  msg_info "未找到本地映像檔或強制更新模式，將從網路下載"
  URL="$REMOTE_URL"
  USE_LOCAL_IMAGE=false
fi

sleep 2
msg_ok "${CL}${BL}$URL${CL}"

# 處理映像檔
if [ "$USE_LOCAL_IMAGE" = true ]; then
  # 使用本地映像檔
  FILE=$(basename "$URL")
  cp "$URL" "$(pwd)/$FILE"
  msg_ok "使用本地映像檔: $FILE"
else
  # 下載映像檔
  FILE=$(basename "$URL")
  msg_info "Downloading to: $(pwd)/$FILE"

  # 添加重試機制，最多嘗試3次
  MAX_RETRIES=3
  RETRY_COUNT=0
  DOWNLOAD_SUCCESS=false

  while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$DOWNLOAD_SUCCESS" = "false" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ $RETRY_COUNT -gt 1 ]; then
      msg_info "重試下載 (嘗試 $RETRY_COUNT/$MAX_RETRIES)..."
      sleep 3
    fi

    # 嘗試使用不同的下載方式
    if [ $RETRY_COUNT -eq 1 ]; then
      # 第一次嘗試：使用 curl
      if curl -f#SL --connect-timeout 30 -o "$FILE" "$URL"; then
        DOWNLOAD_SUCCESS=true
      fi
    elif [ $RETRY_COUNT -eq 2 ]; then
      # 第二次嘗試：使用 wget
      if command -v wget >/dev/null 2>&1; then
        if wget --timeout=30 --tries=3 -O "$FILE" "$URL"; then
          DOWNLOAD_SUCCESS=true
        fi
      else
        # 如果沒有 wget，使用 curl 但換不同參數
        if curl -f#SL --connect-timeout 60 --retry 3 --retry-delay 5 -o "$FILE" "$URL"; then
          DOWNLOAD_SUCCESS=true
        fi
      fi
    else
      # 第三次嘗試：使用 curl 但增加超時時間
      if curl -f#SL --connect-timeout 120 --retry 5 --retry-delay 10 -o "$FILE" "$URL"; then
        DOWNLOAD_SUCCESS=true
      fi
    fi
  done

  if [ "$DOWNLOAD_SUCCESS" = "true" ]; then
    echo -en "\e[1A\e[0K"

    # Verify the downloaded file
    if [ -f "$FILE" ] && [ -s "$FILE" ]; then
      FILE_SIZE=$(du -h "$FILE" | cut -f1)
      msg_ok "Downloaded ${CL}${BL}${FILE}${CL} (${FILE_SIZE})"

      # 保存下載的映像檔以供將來使用
      if [ ! -d "$LOCAL_IMAGE_DIR" ]; then
        mkdir -p "$LOCAL_IMAGE_DIR"
      fi

      if [ ! -f "$LOCAL_IMAGE" ]; then
        msg_info "保存映像檔到本地目錄供將來使用"
        cp "$(pwd)/$FILE" "$LOCAL_IMAGE"
        msg_ok "映像檔已保存到: $LOCAL_IMAGE"
      fi
    else
      msg_error "Download completed but file is missing or empty"
      msg_error "Expected file: $(pwd)/$FILE"
      ls -lh "$(pwd)" 2>/dev/null || true
      exit 1
    fi
  else
    msg_error "Failed to download Debian 13 image"
    msg_error "URL: ${URL}"
    msg_error "Please check your internet connection and try again"
    exit 1
  fi
fi

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
zfs)
  DISK_EXT=".img"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  msg_info "检测到 ZFS 存储类型，应用 ZFS 优化设置..."
  ;;
zfspool)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  msg_info "检测到 ZFS Pool 存储类型，应用 ZFSPool 优化设置..."
  # ZFSPool handles volume names differently
  ;;
lvm | lvm-thin)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
rbd)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  msg_info "檢測到 Ceph RBD 儲存類型，應用 RBD 優化設置..."
  ;;
*)
  msg_error "不支持的儲存類型: $STORAGE_TYPE"
  msg_error "支持: nfs, dir, btrfs, zfs, zfspool, lvm, lvm-thin, rbd"
  exit 1
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  if [[ "$STORAGE_TYPE" == "zfspool" ]] || [[ "$STORAGE_TYPE" == "rbd" ]]; then
    # ZFSPool uses different naming convention
    eval DISK${i}=vm-${VMID}-disk-${i}
    eval DISK${i}_REF=${STORAGE}:${!disk}
  else
    eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
    eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
  fi
done

# 確保 PVE 主機上安裝了必要的工具
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing Pre-Requisite libguestfs-tools onto Host"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools lsb-release qemu-guest-agent -y >/dev/null
  # Workaround for Proxmox VE 9.0 libguestfs issue
  apt-get -qq install dhcpcd-base -y >/dev/null 2>&1 || true
  msg_ok "Installed libguestfs-tools and qemu-guest-agent successfully"
else
  # 確保 qemu-guest-agent 已安裝
  if ! dpkg -l | grep -q qemu-guest-agent; then
    msg_info "Installing QEMU Guest Agent on host"
    apt-get -qq update >/dev/null
    apt-get -qq install qemu-guest-agent -y >/dev/null
    msg_ok "Installed qemu-guest-agent successfully"
  fi
fi

# 確保 qemu-guest-agent 服務已啟用並運行
systemctl enable qemu-guest-agent >/dev/null 2>&1 || true
systemctl restart qemu-guest-agent >/dev/null 2>&1 || true

# Fix network issues for virt-customize
msg_info "Setting up network for virt-customize..."
export http_proxy="${http_proxy:-}"
export https_proxy="${https_proxy:-}"

if [ "$INSTALL_DOCKER" == "yes" ]; then
  msg_info "Adding Docker engine and Compose to Debian 13 Qcow2 Disk Image"

  # 設置更長的超時時間和重試機制
  export LIBGUESTFS_BACKEND_SETTINGS=timeout=600

  # 先安裝基本套件
  if virt-customize -q -a "${FILE}" --copy-in /etc/resolv.conf:/etc --install qemu-guest-agent,cloud-init,openssh-server,apt-transport-https,ca-certificates,curl,gnupg,lsb-release >/dev/null; then
    # 嘗試添加 Docker 存儲庫和安裝 Docker
    DOCKER_INSTALL_SUCCESS=false

    # 嘗試最多3次
    for i in {1..3}; do
      if [ $i -gt 1 ]; then
        msg_info "重試安裝 Docker (嘗試 $i/3)..."
        sleep 3
      fi

      if virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/apt/keyrings && curl -fsSL --connect-timeout 30 --retry 3 https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg" >/dev/null &&
         virt-customize -q -a "${FILE}" --run-command "echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable' > /etc/apt/sources.list.d/docker.list" >/dev/null &&
         virt-customize -q -a "${FILE}" --run-command "apt-get update -qq && apt-get purge -y docker-compose-plugin --allow-change-held-packages && apt-get install -y docker-ce docker-ce-cli containerd.io" >/dev/null &&
         virt-customize -q -a "${FILE}" --run-command "curl -L --connect-timeout 30 --retry 3 https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-\$(uname -s)-\$(uname -m) -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose" >/dev/null; then
        DOCKER_INSTALL_SUCCESS=true
        break
      fi
    done

    if [ "$DOCKER_INSTALL_SUCCESS" = "true" ]; then
      virt-customize -q -a "${FILE}" --run-command "systemctl enable docker" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/ssh/sshd_config.d" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "printf 'PasswordAuthentication yes\\nUseDNS no\\n' > /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "chmod 644 /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-networkd" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-resolved" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -f /etc/network/interfaces" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/network/interfaces.d/*" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/systemd/network/*" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/netplan/*" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/cloud/cloud.cfg.d" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'datasource_list: [ NoCloud, ConfigDrive ]' > /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'system_info: {network: {renderers: [networkd]}}' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'ssh_pwauth: true' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "cloud-init clean" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -rf /var/lib/cloud/*" >/dev/null &&
      virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo -n > /etc/machine-id" >/dev/null
      msg_ok "Added Docker engine and Compose to Debian 13 Qcow2 Disk Image successfully"
    else
      msg_error "Failed to install Docker due to network issues. Continuing with basic setup..."
      # Fallback to basic setup without Docker
      virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/ssh/sshd_config.d" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "printf 'PasswordAuthentication yes\\nUseDNS no\\n' > /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "chmod 644 /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-networkd" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-resolved" >/dev/null &&
      # 不刪除網路配置，只確保 cloud-init 能夠正確配置網路
      virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/cloud/cloud.cfg.d" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'datasource_list: [ NoCloud, ConfigDrive ]' > /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'system_info: {network: {renderers: [networkd]}}' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo 'ssh_pwauth: true' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "cloud-init clean" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "rm -rf /var/lib/cloud/*" >/dev/null &&
      virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "echo -n > /etc/machine-id" >/dev/null
      msg_ok "VM image customized (without Docker)"
    fi
  else
    msg_error "Failed to install packages due to network issues. Continuing..."
    # Skip installation but continue with other customizations
    virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null 2>&1 &&
    virt-customize -q -a "${FILE}" --run-command "echo -n > /etc/machine-id" >/dev/null 2>&1
    msg_ok "VM image customized (without additional packages)"
  fi
else
  msg_info "Adding QEMU Guest Agent and Cloud-Init to Debian 13 Qcow2 Disk Image"
  # Try to install qemu-guest-agent and cloud-init with retry logic for network issues
  # Mirror is already deb.debian.org in the image, no need to change
  if virt-customize -q -a "${FILE}" --copy-in /etc/resolv.conf:/etc --install qemu-guest-agent,cloud-init,openssh-server >/dev/null 2>&1; then
    virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/ssh/sshd_config.d" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "printf 'PasswordAuthentication yes\\nUseDNS no\\n' > /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "chmod 644 /etc/ssh/sshd_config.d/99-custom.conf" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-networkd" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "systemctl enable systemd-resolved" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "rm -f /etc/network/interfaces" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/network/interfaces.d/*" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/systemd/network/*" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "rm -rf /etc/netplan/*" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "mkdir -p /etc/cloud/cloud.cfg.d" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "echo 'datasource_list: [ NoCloud, ConfigDrive ]' > /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "echo 'system_info: {network: {renderers: [networkd]}}' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "echo 'ssh_pwauth: true' >> /etc/cloud/cloud.cfg.d/99_pve.cfg" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "cloud-init clean" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "rm -rf /var/lib/cloud/*" >/dev/null &&
    virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "echo -n > /etc/machine-id" >/dev/null
    msg_ok "Added QEMU Guest Agent and Cloud-Init to Debian 13 Qcow2 Disk Image successfully"
  else
    msg_error "Failed to install packages due to network issues. Continuing..."
    # Skip installation but continue with other customizations
    virt-customize -q -a "${FILE}" --hostname "${HN}" >/dev/null 2>&1 &&
    virt-customize -q -a "${FILE}" --run-command "echo -n > /etc/machine-id" >/dev/null 2>&1
    msg_ok "VM image customized (without additional packages)"
  fi
fi

# Install Node Exporter if requested
if [ "$INSTALL_NODE_EXPORTER" == "yes" ]; then
  msg_info "Adding Prometheus Node Exporter to Debian 13 Qcow2 Disk Image"

  # Download and install Node Exporter
  virt-customize -q -a "${FILE}" --run-command "useradd --no-create-home --shell /bin/false node_exporter" >/dev/null &&
    if virt-customize -q -a "${FILE}" --run-command "curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz -o /tmp/node_exporter.tar.gz" >/dev/null; then
      virt-customize -q -a "${FILE}" --run-command "tar -xzf /tmp/node_exporter.tar.gz -C /tmp && mv /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/ && rm -rf /tmp/node_exporter*" >/dev/null &&
      virt-customize -q -a "${FILE}" --run-command "chown node_exporter:node_exporter /usr/local/bin/node_exporter" >/dev/null
    else
      msg_error "Failed to download Node Exporter from GitHub. Skipping installation."
    fi

  # Create systemd service file - 修復語法錯誤
  virt-customize -q -a "${FILE}" --run-command "cat > /etc/systemd/system/node_exporter.service << 'EOFMARKER'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOFMARKER" >/dev/null &&
    virt-customize -q -a "${FILE}" --run-command "systemctl enable node_exporter" >/dev/null

  msg_ok "Added Prometheus Node Exporter to Debian 13 Qcow2 Disk Image successfully"
  msg_info "Node Exporter will be available on port 9100"
fi

# msg_info "Expanding root partition to use full disk space"
# qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
# # 使用更可靠的分區檢測方法
# PARTITIONS=$(virt-filesystems -a ${FILE} --partitions --human-readable 2>/dev/null | grep '/dev/sda' | sort -k3 -h | tail -1 | awk '{print $1}')
# if [ -n "$PARTITIONS" ]; then
#   # 嘗試擴展檢測到的最大分區
#   virt-resize --expand $PARTITIONS ${FILE} expanded.qcow2 >/dev/null 2>&1 || \
#     # 如果擴展失敗，嘗試不指定分區的擴展
#     virt-resize ${FILE} expanded.qcow2 >/dev/null 2>&1
# else
#   # 如果沒有檢測到分區，直接擴展整個磁碟
#   virt-resize ${FILE} expanded.qcow2 >/dev/null 2>&1
# fi
# mv expanded.qcow2 ${FILE} >/dev/null 2>&1
# msg_ok "Expanded image to full size"

# 臨時跳過磁碟擴展，虛擬機仍可正常啟動
# 稍後會通過獨立腳本進行磁碟擴展

msg_info "Creating a Debian 13 VM"
if [ "$INSTALL_DOCKER" == "yes" ]; then
  VM_TAG="debian13-docker"
else
  VM_TAG="debian13"
fi

# Add node-exporter tag if installed
if [ "$INSTALL_NODE_EXPORTER" == "yes" ]; then
  VM_TAG="${VM_TAG};node-exporter"
fi
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags $VM_TAG -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
qm resize $VMID scsi0 "$DISK_SIZE" >/dev/null
qm set $VMID --agent enabled=1 >/dev/null
# 讓 PVE 的 Cloud-Init 設定生效
qm set $VMID --ide2 $STORAGE:cloudinit

# Configure Cloud-Init with user settings
msg_info "Configuring Cloud-Init..."
qm set $VMID --ciuser "${CI_USER:-debian}" >/dev/null
qm set $VMID --cipassword "${CI_PASSWORD:-debian}" >/dev/null
qm set $VMID --ipconfig0 "${CI_IP_CONFIG:-ip=dhcp}" >/dev/null

# Set DNS nameservers if configured
if [ -n "${CI_NAMESERVER:-}" ]; then
  qm set $VMID --nameserver "${CI_NAMESERVER}" >/dev/null
fi

# Set SSH public key if provided
if [ -n "${CI_SSHKEY:-}" ]; then
  # URL encode the SSH key for Proxmox
  ENCODED_KEY=$(echo -n "${CI_SSHKEY}" | jq -sRr @uri 2>/dev/null || echo -n "${CI_SSHKEY}")
  qm set $VMID --sshkeys "$ENCODED_KEY" >/dev/null
  # Ensure password authentication is still enabled
  qm set $VMID --cipassword "${CI_PASSWORD:-debian}" >/dev/null
  msg_ok "Cloud-Init configured (User: ${CI_USER:-debian}, Network: ${CI_IP_CONFIG:-DHCP}, SSH Key: Yes, Password: Enabled)"
else
  msg_ok "Cloud-Init configured (User: ${CI_USER:-debian}, Network: ${CI_IP_CONFIG:-DHCP})"
fi

if [ "${CI_PASSWORD:-debian}" == "debian" ]; then
  msg_info "⚠️  Using default password 'debian' - Please change after first login!"
fi

DESCRIPTION=$(cat <<EOF
<div align='center'>

</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a Debian 13 VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Debian 13 VM"
  qm start $VMID
  msg_ok "Started Debian 13 VM"
  echo ""
  msg_info "⏳ Please wait 2-3 minutes for Cloud-Init to complete initialization"
  msg_info "📋 Login credentials:"
  msg_info "   User: ${CI_USER:-debian}"
  msg_info "   Password: ${CI_PASSWORD:-debian}"
  msg_info "   Network: ${CI_IP_CONFIG:-DHCP}"
  echo ""
  msg_info "💡 To check Cloud-Init status, use Proxmox Console and run:"
  msg_info "   cloud-init status --wait"
fi
## post_update_to_api "done" "none"
msg_ok "Completed Successfully!"
