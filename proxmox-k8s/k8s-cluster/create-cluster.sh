#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/k8s-config.sh" ]; then
  . "$SCRIPT_DIR/k8s-config.sh"
else
  K8S_REPO_VERSION="${K8S_REPO_VERSION:-v1.28}"
  K8S_REPO_BASE_URL="${K8S_REPO_BASE_URL:-https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb}"
  POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
  CNI_PLUGIN="${CNI_PLUGIN:-flannel}"
  FLANNEL_MANIFEST_URL="${FLANNEL_MANIFEST_URL:-https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml}"
  CALICO_MANIFEST_URL="${CALICO_MANIFEST_URL:-https://docs.projectcalico.org/manifests/calico.yaml}"
fi

# Kubernetes 集群創建腳本
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

  # 禁用防火牆（可選，根據安全策略調整）
  # systemctl stop ufw || true
  # systemctl disable ufw || true

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

# 初始化 Kubernetes Master 節點
init_master() {
  echo_yellow "正在初始化 Kubernetes Master 節點..."

  # 初始化集群
  kubeadm init --pod-network-cidr="${POD_NETWORK_CIDR}"

  # 配置 kubectl
cat <<EOF | tee /root/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF

  source /root/.bashrc

  # 創建 .kube 目錄
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"

  echo_green "Kubernetes Master 節點初始化完成"
  echo_yellow "請保存以下命令用於添加 Worker 節點："
  kubeadm token create --print-join-command
}

# 安裝 Pod 網絡插件
install_network_plugin() {
  echo_yellow "正在安裝 Pod 網絡插件..."

  # 安裝 Flannel 網絡插件
  if [ "${CNI_PLUGIN}" = "calico" ]; then
    kubectl apply -f "${CALICO_MANIFEST_URL}"
  else
    kubectl apply -f "${FLANNEL_MANIFEST_URL}"
  fi

  echo_green "Pod 網絡插件安裝完成"
}

# 主函數
main() {
  echo_green "==========================================="
  echo_green "Kubernetes 集群創建腳本"
  echo_green "適用於 Proxmox 8.0-9.0"
  echo_green "==========================================="

  check_root
  update_system
  install_prerequisites
  install_docker
  configure_docker
  install_kubernetes
  configure_system
  init_master
  install_network_plugin

  echo_green "==========================================="
  echo_green "Kubernetes 集群創建完成！"
  echo_green "==========================================="
  echo_yellow "下一步操作："
  echo_yellow "1. 在 Worker 節點運行 join-worker.sh 腳本"
  echo_yellow "2. 驗證集群狀態: kubectl get nodes"
  echo_yellow "3. 部署應用到集群"
}

# 執行主函數
main
