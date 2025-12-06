#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/k8s-config.sh" ]; then
  . "$SCRIPT_DIR/k8s-config.sh"
else
  K8S_REPO_VERSION="${K8S_REPO_VERSION:-v1.28}"
  K8S_REPO_BASE_URL="${K8S_REPO_BASE_URL:-https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb}"
fi

# Kubernetes Worker 節點加入腳本
# 支持 Proxmox 8.0-9.0 環境

# 設置顏色變量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日誌函數
echo_red() { echo -e "${RED}$1${NC}"; }
echo_green() { echo -e "${GREEN}$1${NC}"; }
echo_yellow() { echo -e "${YELLOW}$1${NC}"; }

# 檢查是否以 root 身份運行
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo_red "此腳本必須以 root 身份運行"
    exit 1
  fi
}

# 更新系統
update_system() {
  echo_yellow "正在更新系統..."
  apt update && apt upgrade -y
  echo_green "系統更新完成"
}

# 安裝必要組件
install_prerequisites() {
  echo_yellow "正在安裝必要組件..."

  # 安裝必要工具
  apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common

  echo_green "必要組件安裝完成"
}

# 安裝 Docker
install_docker() {
  echo_yellow "正在安裝 Docker..."

  # 添加 Docker 官方 GPG 密鑰
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  # 添加 Docker 官方倉庫
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  # 安裝 Docker Engine
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # 啟動並設置 Docker 開機自啟
  systemctl start docker
  systemctl enable docker

  echo_green "Docker 安裝完成"
}

# 配置 Docker daemon
configure_docker() {
  echo_yellow "正在配置 Docker daemon..."

  # 創建 daemon.json 配置文件
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

  # 重啟 Docker 服務
  systemctl daemon-reload
  systemctl restart docker

  echo_green "Docker 配置完成"
}

# 安裝 Kubernetes 組件
install_kubernetes() {
  echo_yellow "正在安裝 Kubernetes 組件..."

  # 添加 Kubernetes 官方 GPG 密鑰
  curl -fsSL "${K8S_REPO_BASE_URL}/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  # 添加 Kubernetes 官方倉庫
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_REPO_BASE_URL} /" | tee /etc/apt/sources.list.d/kubernetes.list

  # 安裝 Kubernetes 組件
  apt update
  apt install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  echo_green "Kubernetes 組件安裝完成"
}

# 配置系統參數
configure_system() {
  echo_yellow "正在配置系統參數..."

  # 禁用 swap
  swapoff -a
  sed -i '/ swap / s/^/#/' /etc/fstab

  # 加載必要的內核模塊
cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

  modprobe br_netfilter

  # 設置網絡參數
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

  sysctl --system

  echo_green "系統參數配置完成"
}

# 加入 Kubernetes 集群
join_cluster() {
  echo_yellow "正在加入 Kubernetes 集群..."

  local join_cmd="${1:-}"

  # 檢查是否提供了 join 命令
  if [ -z "$join_cmd" ]; then
    echo_red "錯誤：請提供從 Master 節點獲取的 join 命令"
    echo_yellow "使用方法：./join-worker.sh \"kubeadm join ...\""
    read -r -p "> " join_cmd
  fi

  if [ -z "$join_cmd" ]; then
    echo_red "錯誤：未提供有效的 join 命令"
    exit 1
  fi

  # 執行 join 命令
  eval "$join_cmd"

  echo_green "Worker 節點已成功加入集群"
}

# 主函數
main() {
  echo_green "==========================================="
  echo_green "Kubernetes Worker 節點加入腳本"
  echo_green "適用於 Proxmox 8.0-9.0"
  echo_green "==========================================="

  check_root
  update_system
  install_prerequisites
  install_docker
  configure_docker
  install_kubernetes
  configure_system

  local join_cmd="${1:-}"
  join_cluster "$join_cmd"

  echo_green "==========================================="
  echo_green "Worker 節點配置完成！"
  echo_green "==========================================="
  echo_yellow "請在 Master 節點驗證節點狀態: kubectl get nodes"
}

# 執行主函數
# 如果提供了參數，則使用參數作為 join 命令
if [ $# -gt 0 ]; then
  main "$*"
else
  main ""
fi
