## Proxmox8.0-9.0 VM 虛擬機自動化腳本

### Debian 13

此腳本用於在 Proxmox VE 8.0-9.0 上自動創建 Debian 13 虛擬機。

### 腳本流程

```mermaid
flowchart TD
    A[開始腳本] --> B[檢查依賴項和權限]
    B --> C[選擇設置模式]
    C --> D{選擇模式}
    D -->|默認設置| E[使用默認配置]
    D -->|高級設置| F[自定義配置]
    E --> G[詢問是否安裝Docker]
    F --> G
    G --> H{是否安裝Docker}
    H -->|是| I[設置INSTALL_DOCKER=yes]
    H -->|否| J[設置INSTALL_DOCKER=no]
    I --> K[選擇存儲池]
    J --> K
    K --> L[下載Debian 13鏡像]
    L --> M[創建虛擬機]
    M --> N[配置雲初始化]
    N --> O[設置用戶和密碼]
    O --> P[配置網絡]
    P --> Q{是否安裝Docker}
    Q -->|是| R[安裝Docker和Compose]
    Q -->|否| S[跳過Docker安裝]
    R --> T[擴展磁盤空間]
    S --> T
    T --> U{是否啟動VM}
    U -->|是| V[啟動虛擬機]
    U -->|否| W[完成創建]
    V --> W
    W --> X[完成]
```

### 使用方法

1. 下載安裝腳本

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-docker-vm.sh)"
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
