# Proxmox Kubernetes 架構設計

## 系統架構概述

### 架構圖
```
                    +------------------+
                    |   Load Balancer  |
                    |   (可選外部)     |
                    +------------------+
                             |
        +--------------------+--------------------+
        |                                         |
+-------v--------+                      +-------v--------+
|  Master Node   |                      |  Worker Node 1 |
|                |                      |                |
| - API Server   |                      | - Kubelet      |
| - etcd         |                      | - Container    |
| - Controller   |                      |   Runtime      |
| - Scheduler    |                      | - Pods         |
+----------------+                      +----------------+
        |                                         |
        +--------------------+--------------------+
                             |
                    +--------v--------+
                    |  Worker Node 2  |
                    |                 |
                    | - Kubelet       |
                    | - Container     |
                    |   Runtime       |
                    | - Pods          |
                    +-----------------+
```

## Proxmox 環境配置

### 節點規劃
| 節點類型 | 數量 | 配置建議 | 用途 |
|----------|------|----------|------|
| Master | 1 | 4CPU, 8GB RAM, 50GB SSD | 控制平面 |
| Worker | 2+ | 2CPU, 4GB RAM, 30GB SSD | 應用運行 |
| Storage | 1 | 4CPU, 8GB RAM, 100GB+ SSD | 存儲服務 |

### LXC 容器配置
```bash
# Master 節點
pct create 100 \
  -hostname k8s-master \
  -memory 8192 \
  -cores 4 \
  -rootfs local-lvm:50 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1

# Worker 節點
pct create 101 \
  -hostname k8s-worker1 \
  -memory 4096 \
  -cores 2 \
  -rootfs local-lvm:30 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1
```

## 網絡設計

### 網絡組件
1. **Pod 網絡**：Flannel (10.244.0.0/16)
2. **Service 網絡**：10.96.0.0/12
3. **Node 網絡**：Proxmox 主機網絡

### 網絡流量
```
外部訪問 -> Load Balancer -> NodePort/Ingress -> Service -> Pod
Pod 間通信 -> Flannel 網絡 -> Pod
```

## 存儲設計

### 存儲類型
1. **本地存儲**：LXC 容器本地存儲
2. **共享存儲**：NFS/Ceph (可選)
3. **持久化存儲**：PV/PVC 機制

### 存儲配置
```yaml
# 本地存儲類示例
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

## 安全設計

### 認證授權
1. **RBAC**：基於角色的訪問控制
2. **TLS**：節點間通信加密
3. **Network Policies**：網絡策略控制

### 安全最佳實踐
1. 使用最小權限原則
2. 定期更新組件
3. 網絡隔離
4. 日誌審計

## 高可用性設計

### 控制平面高可用
1. **多 Master 節點**（推薦 3 個）
2. **外部 etcd 集群**
3. **負載均衡器**

### 應用高可用
1. **多副本部署**
2. **健康檢查**
3. **自動恢復**

## 監控和日誌

### 監控組件
1. **Prometheus**：指標收集
2. **Grafana**：數據可視化
3. **Alertmanager**：告警管理

### 日誌組件
1. **EFK Stack**：
   - Elasticsearch：日誌存儲
   - Fluentd：日誌收集
   - Kibana：日誌可視化

## 備份和災難恢復

### 備份策略
1. **etcd 快照**
2. **應用配置備份**
3. **持久化數據備份**

### 恢復流程
1. **集群恢復**
2. **應用恢復**
3. **數據恢復**

## 升級策略

### Kubernetes 升級
1. **滾動升級**
2. **藍綠部署**
3. **金絲雀發布**

### 組件升級順序
1. **Master 節點**
2. **Worker 節點**
3. **應用組件**
