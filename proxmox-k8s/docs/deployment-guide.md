# Proxmox Kubernetes 部署指南

## 部署前準備

### 系統要求

- Proxmox VE 8.0-9.0
- 至少 3 個節點（1 Master + 2 Workers）
- 每節點至少 2 CPU 核心和 4GB RAM
- 穩定的網絡連接
- 管理員訪問權限

### 網絡規劃

1. 確定節點 IP 地址範圍
2. 規劃 Pod 和 Service CIDR
3. 配置 DNS 解析
4. 設置防火牆規則

### 存儲規劃

1. 確定存儲類型（本地/共享）
2. 規劃存儲容量
3. 配置備份策略

### 腳本與配置

1. `proxmox-k8s/k8s-cluster/k8s-config.sh` 用於調整：
   - Kubernetes 版本 (`K8S_REPO_VERSION`)
   - Pod 網段 (`POD_NETWORK_CIDR`)
   - CNI 外掛類型 (`CNI_PLUGIN`，預設 flannel，可設為 calico)
2. 在執行 `create-cluster.sh` 前，如需客製化版本或網路配置，可先編輯此檔案。

## 部署步驟

### 第一階段：環境準備

#### 1. 創建 LXC 容器

```bash
# 在 Proxmox 主機上執行
# 創建 Master 節點
pct create 100 \
  -hostname k8s-master \
  -memory 8192 \
  -cores 4 \
  -rootfs local-lvm:50 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1

# 創建 Worker 節點 1
pct create 101 \
  -hostname k8s-worker1 \
  -memory 4096 \
  -cores 2 \
  -rootfs local-lvm:30 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1

# 創建 Worker 節點 2
pct create 102 \
  -hostname k8s-worker2 \
  -memory 4096 \
  -cores 2 \
  -rootfs local-lvm:30 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1
```

#### 2. 啟動容器並設置固定 IP

```bash
# 啟動所有容器
pct start 100
pct start 101
pct start 102

# 獲取容器 IP 並設置固定 IP（使用之前創建的 lxc.sh 腳本）
# 或手動設置固定 IP
```

### 第二階段：Master 節點配置

#### 1. 進入 Master 節點

```bash
pct enter 100
```

#### 2. 執行集群創建腳本

```bash
# 下載並執行創建腳本
cd /root
git clone https://github.com/your-repo/proxmox-k8s.git
chmod +x proxmox-k8s/k8s-cluster/create-cluster.sh
./proxmox-k8s/k8s-cluster/create-cluster.sh
```

#### 3. 保存 Join 命令

執行完畢後，保存輸出的 kubeadm join 命令，用於添加 Worker 節點。

### 第三階段：Worker 節點配置

#### 1. 配置 Worker 節點 1

```bash
# 進入 Worker 節點 1
pct enter 101

# 執行 Worker 加入腳本
chmod +x proxmox-k8s/k8s-cluster/join-worker.sh
./proxmox-k8s/k8s-cluster/join-worker.sh "[在此處粘貼從 Master 獲取的 join 命令]"
```

#### 2. 配置 Worker 節點 2

```bash
# 進入 Worker 節點 2
pct enter 102

# 執行 Worker 加入腳本
chmod +x proxmox-k8s/k8s-cluster/join-worker.sh
./proxmox-k8s/k8s-cluster/join-worker.sh "[在此處粘貼從 Master 獲取的 join 命令]"
```

### 第四階段：集群驗證

#### 1. 在 Master 節點驗證

```bash
# 檢查節點狀態
kubectl get nodes

# 檢查 Pod 狀態
kubectl get pods -A

# 檢查組件狀態
kubectl get componentstatuses
```

#### 2. 測試應用部署

```bash
# 部署測試應用
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# 檢查服務
kubectl get services
```

## 高級配置

### 網絡插件配置

默認使用 Flannel，也可配置其他網絡插件：

#### Calico 網絡插件

```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

#### Cilium 網絡插件

```bash
kubectl apply -f https://github.com/cilium/cilium/raw/master/install/kubernetes/quick-install.yaml
```

### 存儲配置

#### 本地存儲類

```bash
# 創建本地存儲類
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

#### NFS 存儲類

```bash
# 需要先設置 NFS 服務器
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: nfs-server-ip
    path: "/exported/path"
EOF
```

### 監控配置

#### 部署 Prometheus

```bash
# 使用 Helm 部署（需要先安裝 Helm）
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/prometheus
```

#### 部署 Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana
```

## 故障排除

### 常見問題

#### 1. 節點 NotReady 狀態

```bash
# 檢查節點詳細信息
kubectl describe node <node-name>

# 檢查 kubelet 狀態
systemctl status kubelet

# 檢查日誌
journalctl -u kubelet -f
```

#### 2. Pod 無法啟動

```bash
# 檢查 Pod 詳細信息
kubectl describe pod <pod-name>

# 檢查 Pod 日誌
kubectl logs <pod-name>
```

#### 3. 網絡問題

```bash
# 檢查 Flannel 狀態
kubectl get pods -n kube-system | grep flannel

# 檢查網絡接口
ip a show flannel.1
```

### 重置集群

如果需要重新開始，可以使用重置腳本：

```bash
./proxmox-k8s/k8s-cluster/reset-cluster.sh
```

## 性能優化

### 資源限制

```yaml
# 為應用設置資源請求和限制
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: nginx
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

### 自動擴縮容

```bash
# 設置 HPA
kubectl autoscale deployment nginx --cpu-percent=50 --min=1 --max=10
```
