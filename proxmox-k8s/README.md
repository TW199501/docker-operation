# Proxmox 8.0-9.0 Kubernetes 專案

## 專案概述

本專案旨在在 Proxmox VE 8.0-9.0 環境中部署和管理 Kubernetes 集群，提供完整的容器化應用解決方案。專案包含自動化腳本和詳細文檔，幫助用戶快速搭建和管理 Kubernetes 環境。

## 目錄結構

```
proxmox-k8s/
├── README.md
├── Makefile
├── k8s-cluster/
│   ├── create-cluster.sh      # Master 節點集群創建腳本
│   ├── join-worker.sh         # Worker 節點加入腳本
│   ├── reset-cluster.sh       # 集群重置腳本
│   └── config/
│       ├── master-config.yaml
│       └── worker-config.yaml
├── k8s-apps/
│   ├── deploy-app.sh          # 應用部署腳本
│   └── manifests/
├── monitoring/
│   ├── prometheus/
│   └── grafana/
├── ingress/
│   └── nginx-ingress/
├── storage/
│   └── persistent-volumes/
└── docs/
    ├── architecture.md         # 架構設計文檔
    ├── deployment-guide.md     # 部署指南
    └── troubleshooting.md      # 故障排除指南
```

## 功能特性

- **自動化部署**：一鍵部署 Kubernetes 集群
- **Proxmox LXC 支持**：專為 Proxmox 環境優化
- **高可用性**：支持多節點集群配置
- **監控集成**：內置監控和日誌解決方案
- **網絡管理**：Flannel 網絡插件支持
- **存儲管理**：持久化存儲配置
- **應用部署**：簡化的應用部署工具

## 系統要求

- **Proxmox VE 版本**：8.0-9.0
- **節點配置**：
  - Master 節點：4 CPU 核心，8GB RAM，50GB 存儲
  - Worker 節點：2+ CPU 核心，4GB RAM，30GB 存儲
- **網絡要求**：穩定的網絡連接，節點間可互訪
- **權限要求**：Proxmox 管理員權限

## 快速開始

### 1. 項目初始化

```bash
# 克隆項目
cd /opt
git clone <repository-url> proxmox-k8s
cd proxmox-k8s

# 初始化項目
make init
```

### 2. Proxmox 環境準備

```bash
# 創建 Master 節點 LXC 容器
pct create 100 \
  -hostname k8s-master \
  -memory 8192 \
  -cores 4 \
  -rootfs local-lvm:50 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1

# 創建 Worker 節點 LXC 容器
pct create 101 \
  -hostname k8s-worker1 \
  -memory 4096 \
  -cores 2 \
  -rootfs local-lvm:30 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -features nesting=1 \
  -onboot 1
```

### 3. 部署 Kubernetes 集群

```bash
# 在 Master 節點執行
pct enter 100
/opt/proxmox-k8s/k8s-cluster/create-cluster.sh

# 在 Worker 節點執行
pct enter 101
/opt/proxmox-k8s/k8s-cluster/join-worker.sh "[從 Master 獲取的 join 命令]"
```

### 4. 驗證集群

```bash
# 在 Master 節點執行
kubectl get nodes
kubectl get pods -A
```

## 腳本使用

### Master 節點腳本

- `create-cluster.sh`：初始化 Kubernetes 集群
- `reset-cluster.sh`：重置集群配置

### Worker 節點腳本

- `join-worker.sh`：加入現有 Kubernetes 集群

### 應用部署腳本

- `deploy-app.sh`：部署常見應用（Nginx、MySQL、WordPress）

## 文檔資源

使用 `make docs` 查看詳細文檔：

1. **架構設計**：`docs/architecture.md`
2. **部署指南**：`docs/deployment-guide.md`
3. **故障排除**：`docs/troubleshooting.md`

## 項目管理

```bash
make help     # 顯示幫助信息
make init     # 初始化項目
make master   # 準備 Master 節點
make worker   # 準備 Worker 節點
make reset    # 準備重置腳本
make app      # 準備應用部署
make docs     # 顯示文檔列表
make clean    # 清理臨時文件
```

## Windows 環境支持

### 安裝 make 工具

Windows 用戶可以通過以下方式安裝 make 工具：

#### 方法 1：安裝 Chocolatey（推薦）

```powershell
# 以管理員身份運行 PowerShell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 安裝 make
choco install make
```

#### 方法 2：安裝 Git for Windows

1. 下載並安裝 [Git for Windows](https://git-scm.com/download/win)
2. 安裝完成後，使用 Git Bash 運行 make 命令

#### 方法 3：安裝 MinGW-w64

1. 下載 [MinGW-w64](https://www.mingw-w64.org/downloads/)
2. 安裝並將 bin 目錄添加到 PATH 環境變量

#### 方法 4：使用 WSL（Windows Subsystem for Linux）

```bash
# 啟用 WSL
wsl --install

# 在 WSL 中安裝 make
sudo apt update
sudo apt install make
```

### Windows 環境下直接運行腳本

如果不方便安裝 make 工具，可以直接運行腳本：

```powershell
# 初始化項目（設置腳本權限）
chmod +x k8s-cluster/*.sh
chmod +x k8s-apps/*.sh

# 執行特定腳本
./k8s-cluster/create-cluster.sh
./k8s-cluster/join-worker.sh
./k8s-cluster/reset-cluster.sh
./k8s-apps/deploy-app.sh
```

## 注意事項

1. **資源規劃**：確保 Proxmox 主機有足夠資源
2. **網絡配置**：節點間需要穩定網絡連接
3. **安全考慮**：生產環境需要配置適當的安全策略
4. **備份策略**：定期備份 etcd 和重要數據

## 貢獻和反饋

歡迎提交 Issue 和 Pull Request 來改進這個專案！
