# Proxmox Kubernetes 故障排除指南

## 節點問題

### 節點狀態異常

#### 節點 NotReady

**問題描述**：節點顯示為 NotReady 狀態

**診斷步驟**：

1. 檢查節點詳細信息

```bash
kubectl describe node <node-name>
```

2. 檢查 kubelet 服務

```bash
systemctl status kubelet
journalctl -u kubelet -f
```

3. 檢查容器運行時

```bash
systemctl status docker
docker info
```

**解決方案**：

- 重啟 kubelet 服務：`systemctl restart kubelet`
- 檢查系統資源（內存、磁碟空間）
- 檢查網絡連接

#### 節點資源不足

**問題描述**：Pod 無法調度到節點

**診斷步驟**：

1. 檢查節點資源使用

```bash
kubectl describe node <node-name>
```

2. 檢查系統資源

```bash
free -h
df -h
```

**解決方案**：

- 增加節點資源（內存、CPU）
- 清理不必要的 Pod 和鏡像
- 調整 Pod 資源請求

### 網絡問題

#### Pod 無法通信

**問題描述**：Pod 間無法通信

**診斷步驟**：

1. 檢查網絡插件狀態

```bash
kubectl get pods -n kube-system | grep flannel
kubectl logs -n kube-system <flannel-pod-name>
```

2. 檢查網絡接口

```bash
ip a show flannel.1
ping <other-pod-ip>
```

**解決方案**：

- 重啟網絡插件 Pod
- 檢查防火牆設置
- 驗證網絡 CIDR 配置

#### Service 無法訪問

**問題描述**：無法通過 Service 訪問應用

**診斷步驟**：

1. 檢查 Service 配置

```bash
kubectl describe service <service-name>
```

2. 檢查 Endpoint

```bash
kubectl get endpoints <service-name>
```

3. 檢查 kube-proxy

```bash
kubectl get pods -n kube-system | grep kube-proxy
```

**解決方案**：

- 檢查 Label 選擇器匹配
- 重啟 kube-proxy
- 檢查 iptables 規則

## Pod 問題

### Pod 無法啟動

#### ImagePullBackOff

**問題描述**：Pod 卡在 ImagePullBackOff 狀態

**診斷步驟**：

1. 檢查 Pod 詳細信息

```bash
kubectl describe pod <pod-name>
```

2. 檢查鏡像名稱和標籤
3. 檢查鏡像倉庫訪問權限

**解決方案**：

- 驗證鏡像名稱和標籤
- 檢查網絡連接到鏡像倉庫
- 配置鏡像拉取 Secret

#### CrashLoopBackOff

**問題描述**：Pod 不斷重啟

**診斷步驟**：

1. 檢查 Pod 日誌

```bash
kubectl logs <pod-name> --previous
```

2. 檢查應用配置
3. 檢查資源限制

**解決方案**：

- 修復應用錯誤
- 調整資源限制
- 檢查依賴服務

### 存儲問題

#### PersistentVolume 無法掛載

**問題描述**：Pod 無法掛載持久化存儲

**診斷步驟**：

1. 檢查 PV 和 PVC 狀態

```bash
kubectl get pv
kubectl get pvc
```

2. 檢查存儲類配置

```bash
kubectl describe storageclass <storageclass-name>
```

**解決方案**：

- 檢查存儲後端可用性
- 驗證存儲類配置
- 檢查權限設置

## Proxmox 特定問題

### LXC 容器限制

#### 嵌套虛擬化問題

**問題描述**：無法在 LXC 容器中運行 Docker

**診斷步驟**：

1. 檢查 LXC 配置

```bash
pct config <container-id>
```

2. 檢查嵌套虛擬化設置

**解決方案**：

- 啟用嵌套虛擬化：`pct set <container-id> -features nesting=1`
- 重啟容器

#### 資源限制問題

**問題描述**：容器資源不足

**診斷步驟**：

1. 檢查 Proxmox 資源使用

```bash
pct status <container-id>
```

2. 檢查容器資源限制

**解決方案**：

- 調整容器資源分配

```bash
pct set <container-id> -memory 4096 -cores 2
```

### 網絡配置問題

#### 容器網絡不通

**問題描述**：LXC 容器無法訪問外部網絡

**診斷步驟**：

1. 檢查容器網絡配置

```bash
pct exec <container-id> -- ip a
pct exec <container-id> -- ip route
```

2. 檢查 Proxmox 網橋設置

**解決方案**：

- 檢查網橋配置
- 驗證防火牆規則
- 檢查 IP 配置

## 性能問題

### 集群響應緩慢

#### API Server 性能問題

**問題描述**：kubectl 命令響應緩慢

**診斷步驟**：

1. 檢查 API Server 狀態

```bash
kubectl get componentstatuses
```

2. 檢查 etcd 性能

```bash
kubectl get pods -n kube-system | grep etcd
```

**解決方案**：

- 優化 etcd 配置
- 增加 Master 節點資源
- 檢查網絡延遲

#### 調度器性能問題

**問題描述**：Pod 調度緩慢

**診斷步驟**：

1. 檢查調度器日誌

```bash
kubectl logs -n kube-system <scheduler-pod-name>
```

2. 檢查資源碎片化

**解決方案**：

- 調整調度器參數
- 優化資源請求
- 清理未使用的資源

## 安全問題

### 認證授權問題

#### RBAC 權限不足

**問題描述**：用戶無法執行特定操作

**診斷步驟**：

1. 檢查用戶權限

```bash
kubectl auth can-i <verb> <resource> --as=<user>
```

2. 檢查 Role 和 RoleBinding

```bash
kubectl get roles,rolebindings
```

**解決方案**：

- 創建適當的 Role 和 RoleBinding
- 調整用戶權限

### 網絡安全問題

#### 網絡策略阻止訪問

**問題描述**：Pod 無法訪問特定服務

**診斷步驟**：

1. 檢查 NetworkPolicy

```bash
kubectl get networkpolicies
kubectl describe networkpolicy <policy-name>
```

2. 測試網絡連接

**解決方案**：

- 調整 NetworkPolicy 規則
- 添加允許規則

## 備份和恢復

### 備份失敗

#### etcd 快照失敗

**問題描述**：etcd 備份失敗

**診斷步驟**：

1. 檢查 etcd 狀態

```bash
kubectl exec -n kube-system <etcd-pod-name> -- etcdctl endpoint health
```

2. 檢查存儲空間

**解決方案**：

- 清理存儲空間
- 檢查 etcd 配置
- 驗證備份路徑權限

### 恢復失敗

#### 恢復過程中出現錯誤

**問題描述**：從備份恢復時出現錯誤

**診斷步驟**：

1. 檢查備份文件完整性
2. 檢查集群狀態
3. 檢查版本兼容性

**解決方案**：

- 驗證備份文件
- 檢查 Kubernetes 版本
- 按步驟恢復

## 監控和日誌

### 監控數據缺失

#### Prometheus 無法收集指標

**問題描述**：Prometheus 無法收集某些組件的指標

**診斷步驟**：

1. 檢查目標狀態

```bash
kubectl get pods -n monitoring
```

2. 檢查服務發現

**解決方案**：

- 檢查 ServiceMonitor 配置
- 驗證指標端點
- 檢查網絡策略

### 日誌收集問題

#### Fluentd 無法收集日誌

**問題描述**：部分 Pod 日誌未被收集

**診斷步驟**：

1. 檢查 Fluentd 配置
2. 檢查日誌路徑
3. 檢查權限設置

**解決方案**：

- 調整 Fluentd 配置
- 檢查日誌驅動
- 驗證路徑權限
