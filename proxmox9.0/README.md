## Proxmox8.0-9.0 VM 虛擬機自動化腳本

### Debian 13

此腳本用於在 Proxmox VE 8.0-9.0 上自動創建 Debian 13 虛擬機。

### 腳本流程

腳本提供兩種配置模式：

#### 默認模式
默認模式使用預定義的硬件配置創建虛擬機：
- 虛擬機ID：自動分配
- 機器類型：i440fx
- 磁盤大小：10G
- 磁盤緩存：None
- 主機名：debian
- CPU模型：KVM64
- CPU核心數：2
- 內存大小：2048 MiB
- 網絡橋接：vmbr0
- MAC地址：自動生成
- VLAN：Default
- MTU大小：Default
- 啟動選項：創建完成後自動啟動

在默認模式下，用戶仍可以選擇：
1. **Root密碼** - 設置root用戶密碼
2. **網絡配置** - 選擇使用DHCP或靜態IP配置
3. **Docker安裝** - 選擇是否安裝Docker和Docker Compose

#### 自定義模式
自定義模式允許用戶完全自定義所有配置參數。

```mermaid
flowchart TD
    A[開始腳本] --> B[檢查PVE環境和依賴項]
    B --> C[選擇設置模式]
    C --> D{選擇模式}
    D -->|默認設置| E[使用默認硬件配置]
    D -->|高級設置| F[自定義硬件配置]
    E --> G[設置默認參數]
    E --> H[獲取Root密碼]
    E --> I[獲取網絡配置選擇]
    F --> J[獲取VM ID]
    F --> K[獲取Root密碼]
    F --> L[獲取網絡配置選擇]
    F --> M[獲取機器類型]
    F --> N[獲取磁盤大小]
    F --> O[獲取磁盤緩存]
    F --> P[獲取主機名]
    F --> Q[獲取CPU模型]
    F --> R[獲取CPU核心數]
    F --> S[獲取內存大小]
    F --> T[獲取網絡橋接]
    F --> U[獲取MAC地址]
    F --> V[獲取VLAN標籤]
    F --> W[獲取MTU大小]
    I --> X{網絡配置}
    L --> X
    X -->|DHCP| Y[使用DHCP配置]
    X -->|靜態IP| Z[輸入靜態IP參數]
    Z --> AA[驗證IP地址有效性]
    AA --> AB[獲取網關和DNS]
    Y --> AC[詢問是否安裝Docker]
    AB --> AC
    M --> AC
    AC --> AD[選擇存儲池]
    AD --> AE[下載Debian 13鏡像]
    AE --> AF[創建虛擬機]
    AF --> AG[配置雲初始化]
    AG --> AH[設置用戶和密碼]
    AH --> AI[配置網絡]
    AI --> AJ{是否安裝Docker}
    AJ -->|是| AK[安裝Docker和Compose]
    AJ -->|否| AL[跳過Docker安裝]
    AK --> AM[擴展磁盤空間]
    AL --> AM
    AM --> AN{是否啟動VM}
    AN -->|是| AO[啟動虛擬機]
    AN -->|否| AP[完成創建]
    AO --> AP
    AP --> AQ[完成]
```

### 使用方法

1. 下載安裝腳本

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-vm.sh)"
```

2. 執行安裝 SSH

```bash
sudo apt update && sudo apt install -y openssh-client openssh-server
passwd root
sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
ssh-keygen -A
systemctl restart sshd
```

3. 把硬碟擴大

```bash
sudo apt update && sudo apt install -y cloud-guest-utils
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
```
