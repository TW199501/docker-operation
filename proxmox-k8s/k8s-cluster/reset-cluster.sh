#!/bin/bash

# Kubernetes 集群重置腳本
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

# 重置 Kubernetes 節點
reset_kubernetes() {
  echo_yellow "正在重置 Kubernetes 節點..."

  # 重置 kubeadm
  kubeadm reset -f

  # 清理 iptables 規則
  iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

  # 清理 IPVS 規則（如果存在）
  ipvsadm -C 2>/dev/null || true

  # 刪除網絡接口
  ip link delete cni0 2>/dev/null || true
  ip link delete flannel.1 2>/dev/null || true
  ip link delete kube-ipvs0 2>/dev/null || true
  ip link delete dummy0 2>/dev/null || true

  echo_green "Kubernetes 節點重置完成"
}

# 清理配置文件
cleanup_configs() {
  echo_yellow "正在清理配置文件..."

  # 刪除 Kubernetes 配置
  rm -rf /etc/kubernetes/
  rm -rf ~/.kube/
  rm -rf /var/lib/etcd/
  rm -rf /var/lib/kubelet/

  # 刪除 CNI 配置
  rm -rf /etc/cni/
  rm -rf /opt/cni/

  # 刪除 Docker 容器和鏡像（可選）
  # docker system prune -af

  echo_green "配置文件清理完成"
}

# 重新啟用 swap（如果需要）
reenable_swap() {
  echo_yellow "正在重新啟用 swap..."

  # 重新啟用 swap（取消註釋 /etc/fstab 中的 swap 行）
  sed -i 's/^#\(.*swap.*\)/\1/' /etc/fstab 2>/dev/null || true

  # 啟用所有 swap
  swapon -a 2>/dev/null || true

  echo_green "Swap 重新啟用完成"
}

# 重啟服務
restart_services() {
  echo_yellow "正在重啟相關服務..."

  # 重啟 Docker 服務
  systemctl restart docker

  # 重啟網絡服務
  systemctl restart networking 2>/dev/null || true

  echo_green "相關服務重啟完成"
}

# 主函數
main() {
  echo_red "==========================================="
  echo_red "警告：此操作將完全重置 Kubernetes 節點"
  echo_red "所有集群數據將被刪除！"
  echo_red "==========================================="

  # 確認操作
  read -p "是否繼續執行重置操作？(y/N): " confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo_green "操作已取消"
    exit 0
  fi

  check_root
  reset_kubernetes
  cleanup_configs
  reenable_swap
  restart_services

  echo_green "==========================================="
  echo_green "Kubernetes 節點重置完成！"
  echo_green "==========================================="
  echo_yellow "現在可以重新初始化集群或加入現有集群"
}

# 執行主函數
main
