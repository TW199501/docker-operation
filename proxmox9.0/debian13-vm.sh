#!/usr/bin/env bash


explain_exit_code() {
  local code="$1"
  case "$code" in
  # --- Generic / Shell ---
  1) echo "General error / Operation not permitted" ;;
  2) echo "Misuse of shell builtins (e.g. syntax error)" ;;
  126) echo "Command invoked cannot execute (permission problem?)" ;;
  127) echo "Command not found" ;;
  128) echo "Invalid argument to exit" ;;
  130) echo "Terminated by Ctrl+C (SIGINT)" ;;
  137) echo "Killed (SIGKILL / Out of memory?)" ;;
  139) echo "Segmentation fault (core dumped)" ;;
  143) echo "Terminated (SIGTERM)" ;;
  # --- Package manager / APT / DPKG ---
  100) echo "APT: Package manager error (broken packages / dependency problems)" ;;
  101) echo "APT: Configuration error (bad sources.list, malformed config)" ;;
  255) echo "DPKG: Fatal internal error" ;;
  # --- Proxmox Custom Codes ---
  200) echo "Custom: Failed to create lock file" ;;
  203) echo "Custom: Missing CTID variable" ;;
  204) echo "Custom: Missing PCT_OSTYPE variable" ;;
  205) echo "Custom: Invalid CTID (<100)" ;;
  206) echo "Custom: CTID already in use (check 'pct list' and /etc/pve/lxc/)" ;;
  207) echo "Custom: Password contains unescaped special characters (-, /, \\, *, etc.)" ;;
  208) echo "Custom: Invalid configuration (DNS/MAC/Network format error)" ;;
  209) echo "Custom: Container creation failed (check logs for pct create output)" ;;
  210) echo "Custom: Cluster not quorate" ;;
  211) echo "Custom: Timeout waiting for template lock (concurrent download in progress)" ;;
  214) echo "Custom: Not enough storage space" ;;
  215) echo "Custom: Container created but not listed (ghost state - check /etc/pve/lxc/)" ;;
  216) echo "Custom: RootFS entry missing in config (incomplete creation)" ;;
  217) echo "Custom: Storage does not support rootdir (check storage capabilities)" ;;
  218) echo "Custom: Template file corrupted or incomplete download (size <1MB or invalid archive)" ;;
  220) echo "Custom: Unable to resolve template path" ;;
  221) echo "Custom: Template file exists but not readable (check file permissions)" ;;
  222) echo "Custom: Template download failed after 3 attempts (network/storage issue)" ;;
  223) echo "Custom: Template not available after download (storage sync issue)" ;;
  225) echo "Custom: No template available for OS/Version (check 'pveam available')" ;;
  231) echo "Custom: LXC stack upgrade/retry failed (outdated pve-container - check https://github.com/community-scripts/ProxmoxVE/discussions/8126)" ;;
  # --- Default ---
  *) echo "Unknown error" ;;
  esac
}

function header_info {
  clear
  cat <<"EOF"
    ______ _       ______          _____       _      _           ______      _ _
   |  ____| |     |  ____|        |  __ \     (_)    | |         |  ____|    | | |
   | |__  | |     | |__  __ _  ___| |  | | ___ _  ___| |_ _ __   | |__  __  _| | |
   |  __| | |     |  __|/ _` |/ __| |  | |/ _ | |/ __| __| '_ \  |  __| \ \/ / | |
   | |____| |____ | |__| (_| | (__| |__| |  __| | (__| |_| | | | | |____ >  <| | |
   |______|______||______\__,_|\___|_____/ \___|_|\___|\__|_| |_| |______/_/\_\_|_|

                              ELF Debian13 All-IN (open-source)
EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="debian13vm"
var_os="debian"
var_version="13"
LIBGUESTFS_RESOLV_CONF_PATH="${LIBGUESTFS_RESOLV_CONF:-}"
POST_INSTALL_MESSAGE="no"
POST_INSTALL_DETAILS=""

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
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if ACTION=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Debian 13 VM" --menu "This will create a new Debian 13 VM using cloud-init." 10 60 2 \
  "proceed" "Start creation" \
  "exit" "Cancel and quit" \
  3>&1 1>&2 2>&3); then
  if [ "$ACTION" = "exit" ]; then
    header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
  fi
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
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.1
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
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0 and 9.1
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 1)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.1"
      exit 1
    fi
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0 – 9.1"
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
      if SSH_DECISION=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "SSH DETECTED" --menu "It's suggested to use the Proxmox shell instead of SSH while gathering variables." 12 70 2 \
        "proceed" "Continue over SSH (not recommended)" \
        "exit" "Quit script" \
        3>&1 1>&2 2>&3); then
        if [ "$SSH_DECISION" = "exit" ]; then
          clear
          exit
        else
          echo "you've been warned"
        fi
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
  DISK_SIZE="30G"
  DISK_CACHE=""
  HN="debian13"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
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
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Using Cloud-init: ${BGN}Yes (Debian 13 genericcloud)${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using cloud-init with default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  if MACH=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "MACHINE TYPE" --cancel-button Exit-Script --menu "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" \
    "q35" "Machine q35" \
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

  if DISK_SIZE=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  if DISK_CACHE=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "DISK CACHE" --cancel-button Exit-Script --menu "Choose cache mode" 10 58 2 \
    "none" "None (Default)" \
    "writethrough" "Write Through" \
    3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "writethrough" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set Hostname" 8 58 debian13 --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="debian13"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "CPU MODEL" --cancel-button Exit-Script --menu "Choose CPU model" 10 58 2 \
    "kvm64" "KVM64 (Default)" \
    "host" "Host" \
    3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "host" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="2048"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    fi
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  if VLAN1=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  if MTU1=$(whiptail --backtitle "ELF Debian13 ALL IN" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  echo -e "${CLOUD}${BOLD}${DGN}Using Cloud-init: ${BGN}Yes (Debian 13 genericcloud)${CL}"

  if START_DECISION=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "START VIRTUAL MACHINE" --menu "Start VM when completed?" 10 58 2 \
    "yes" "Start automatically" \
    "no" "Do not start" \
    3>&1 1>&2 2>&3); then
    START_VM="$START_DECISION"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}$START_VM${CL}"
  else
    exit-script
  fi

  if FINAL_STEP=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "ADVANCED SETTINGS COMPLETE" --menu "Ready to create the VM?" 10 60 2 \
    "create" "Create Debian 13 VM" \
    "redo" "Do-Over settings" \
    3>&1 1>&2 2>&3); then
    if [ "$FINAL_STEP" = "create" ]; then
      echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using cloud-init with advanced settings${CL}"
    else
      header_info
      echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
      advanced_settings
    fi
  else
    exit-script
  fi
}

function start_script() {
  if MODE=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "SETTINGS" --menu "Select configuration mode" 10 60 2 \
    "default" "Use Default Settings" \
    "advanced" "Customize settings" \
    3>&1 1>&2 2>&3); then
    header_info
    if [ "$MODE" = "default" ]; then
      echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
      default_settings
    else
      echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
      advanced_settings
    fi
  else
    header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
  fi
}

function configure_cloudinit_network() {
  local ci_ip ci_gw ci_dns

  # VM IP (full IPv4, no CIDR)
  if ci_ip=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "VM IP" --inputbox "Set VM IPv4 address (e.g. 192.168.1.19)" 8 58 3>&1 1>&2 2>&3); then
    ci_ip=$(echo "$ci_ip" | tr -d ' ')
  else
    exit-script
  fi

  if ! echo "$ci_ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    whiptail --backtitle "ELF Debian13 ALL IN" --title "INVALID IP" --msgbox "IP must be a valid IPv4 address, e.g. 192.168.1.19" 8 70
    exit-script
  fi

  # Gateway (full IPv4, no CIDR)
  if ci_gw=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "GATEWAY" --inputbox "Set default gateway (e.g. 192.168.1.254)" 8 58 3>&1 1>&2 2>&3); then
    ci_gw=$(echo "$ci_gw" | tr -d ' ')
  else
    exit-script
  fi

  if ! echo "$ci_gw" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    whiptail --backtitle "ELF Debian13 ALL IN" --title "INVALID GATEWAY" --msgbox "Gateway must be a valid IPv4 address, e.g. 192.168.1.254" 8 70
    exit-script
  fi

  # DNS
  if ci_dns=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "DNS" --inputbox "Set DNS server (e.g. 8.8.8.8)" 8 58 8.8.8.8 3>&1 1>&2 2>&3); then
    ci_dns=$(echo "$ci_dns" | tr -d ' ')
  else
    exit-script
  fi

  CI_IPCFG="ip=${ci_ip}/24,gw=${ci_gw}"
  CI_DNS="$ci_dns"
}

check_root
arch_check
pve_check
ssh_check
start_script
configure_cloudinit_network

msg_info "Validating Storage"
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
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "ELF Debian13 ALL IN" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
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
  msg_info "Detected ZFS storage – applying raw disk import settings..."
  ;;
zfspool)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  msg_info "Detected ZFS Pool storage – applying pool volume settings..."
  ;;
lvm | lvm-thin)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  msg_error "Unsupported storage type: $STORAGE_TYPE"
  msg_error "Supported: nfs, dir, btrfs, zfs, zfspool, lvm, lvm-thin"
  exit 1
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  if [[ "$STORAGE_TYPE" == "zfspool" ]]; then
    eval DISK${i}=vm-${VMID}-disk-${i}
    eval DISK${i}_REF=${STORAGE}:${!disk}
  else
    eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
    eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
  fi
done

msg_info "Creating a Debian 13 VM with cloud-init support"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -scsi1 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

if [ -n "${CI_IPCFG:-}" ]; then
  qm set $VMID --ipconfig0 "$CI_IPCFG" >/dev/null
fi
if [ -n "${CI_DNS:-}" ]; then
  qm set $VMID --nameserver "$CI_DNS" >/dev/null
fi


qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

msg_ok "Created a Debian 13 VM with cloud-init support ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Debian 13 VM"
  qm start $VMID
  msg_ok "Started Debian 13 VM"
fi

msg_ok "Completed Successfully!\n"
echo "More Info at https://github.com/community-scripts/ProxmoxVE/discussions/836"
