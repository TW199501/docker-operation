
```
# Docker 中運行 macOS 的筆記

## 1. 功能介紹 ✨
- **KVM 加速**: 提供硬體級的虛擬化加速，提升性能。
- **Web-based Viewer**: 可通過瀏覽器遠端查看和控制容器內的 macOS 系統。
- **Automatic Download**: 自動下載指定版本的 macOS 安裝檔案。

## 2. 使用方法 🐳
### (1) Docker Compose
在 `docker-compose.yml` 中定義服務：
```yaml
services:
  macos:
    image: dockurr/macos
    container_name: macos
    environment:
      VERSION: "13"          # 選擇 macOS 版本（默認為 Ventura）
    devices:
      - /dev/kvm            # KVM 硬體加速
      - /dev/net/tun        # 網路_TUN 設備
    cap_add:
      - NET_ADMIN           # 授予網路管理權限
    ports:
      - 8006:8006           # Web 檢視器埠
      - 5900:5900/tcp       # VNC 通訊埠（TCP）
      - 5900:5900/udp       # VNC 通訊埠（UDP）
    volumes:
      - ./macos:/storage    # 指定儲存位置
    restart: always          # 自動重啟容器
    stop_grace_period: 2m    # 容器停止前等待時間
```

### (2) Docker CLI
直接執行命令：
```bash
docker run -it --rm --name macos \
-p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --cap-add NET_ADMIN \
-v "${PWD:-.}/macos:/storage" --stop-timeout 120 dockurr/macos
```

### (3) Kubernetes
```bash
kubectl apply -f https://raw.githubusercontent.com/dockur/macos/refs/heads/master/kubernetes.yml
```

## 3. 安裝步驟 💬
1. 啟動容器後，開啟瀏覽器連線至 `http://127.0.0.1:8006`。
2. 選「磁碟工具實用程式」，然後選擇最大的「Apple Inc. VirtIO Block Media」磁碟。
3. 點擊「抹掉」按鈕將其格式化為 APFS，並命名。
4. 關閉當前窗口，點擊「重新安裝 macOS」開始安裝。
5. 選擇之前創建的磁碟作為安裝位置。
6. 設定地區、語言和帳戶信息。

## 4. 常見問題解答
### (1) 如何選擇 macOS 版本？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  VERSION: "13"          # 選擇版本（默認為 Ventura）
```
可用版本如下：

| **值** | **版本名稱**    | **代號** |
|---|---|---|
| `15` | macOS 15        | Sequoia  |
| `14` | macOS 14        | Sonoma   |
| `13` | macOS 13        | Ventura  |
| `12` | macOS 12        | Monterey |
| `11` | macOS 11        | Big Sur  |

### (2) 如何更改儲存位置？
在 `docker-compose.yml` 中加入：
```yaml
volumes:
  - ./macos:/storage       # 將 "./macos" 指定為儲存目錄
```

### (3) 如何調整硬碟大小？
加入環境變量：
```yaml
environment:
  DISK_SIZE: "256G"          # 選擇所需容量（默認為 64 GB）
```

### (4) 如何與主機共用檔案？
1. 在 macOS 中開啟「Finder」，進入「前往此位置」。
2. 輸入 `volumes://host.lan/Data` 以連接共享夾。
3. 通過 Docker 綁定掛載：
```yaml
volumes:
  - ./example:/shared          # 將 "./example" 指定為共用夾路徑
```

### (5) 如何調整 CPU 或記憶體？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  RAM_SIZE: "8G"             # 設定記憶體大小（默認為 4 GB）
  CPU_CORES: "4"             # 設定核心數（默認為 2 核心）
```

### (6) 如何設定帳號密碼？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  USERNAME: "bill"           # 自訂用戶名
  PASSWORD: "gates"          # 自訂密碼
```
默認帳戶為 `Docker`，密碼為 `admin`。

### (7) 如何安裝自訂版本？
若要安裝未支援的版本，可在 `docker-compose.yml` 中指定 ISO URL 或本地檔案：
```yaml
environment:
  VERSION: "https://example.com/win.iso"  # 使用網路上的 ISO
```
或
```yaml
volumes:
  - ./example.iso:/boot.iso               # 使用本地 ISO
```

### (8) 如何使用 RDP 連線？
1. 在 macOS 中開啟「遠端桌面連線」（按 `Win + R`，輸入 `mstsc`）。
2. 輸入容器 IP（默認為 `localhost`），帳戶名稱為 `Docker`，密碼為 `admin`。

### (9) 如何配置dhcp？
若要讓 macOS 取得路由器分配的 IP：
在 `docker-compose.yml` 中加入：
```yaml
environment:
  DHCP: "Y"                          # 啟用dhcp
devices:
  - /dev/vhost-net                   # 添加網路設備
device_cgroup_rules:
  - 'c *:* rwm'                     # 設定設備權限
```

### (10) 如何擴展硬碟？
若要新增多顆硬碟，可以添加：
```yaml
devices:
    - /dev/sdb:/disk1
    - /dev/sdc1:/disk2
```
使用 `/disk1` 作為主要磁碟， `/disk2` 等用作 secondary drives。

### (11) 如何傳遞 USB 裝置？
首先查找設備的廠商和產品編號，然後添加到.compose 文件：
```yaml
environment:
    ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"
devices:
    - /dev/bus/usb
```

### (12) 如何檢查系統是否支援 KVM？
執行以下命令：
```bash
sudo apt install cpu-checker
sudo kvm-ok
```
如果收到錯誤提示，請檢查 BIOS 中的虛擬化選項，並確保未在雲伺服器上運行。

### (13) 合法性問題
- 该项目使用開源代碼，不涉及版權侵權。
- 安裝 macOS 需遵守 Apple 的最終用戶許可協議，只能在官方硬體上運行。

## 5. 注意事項
- **macOS 15 (Sequoia)** 目前還不成熟，無法登錄 Apple 帳號，可能影響某些功能的使用。
- 使用 macvlan 網路可以讓容器有獨立 IP，並從路由器獲得 DHCP 位址，但需注意與宿主機的通信限制。

```

# 完整環境變量與參數的 docker-compose.yml 文件示例

```yaml
version: '3.8'

services:
  macos:
    # 使用dockurr/macos鏡像，默認為macOS Ventura (13)
    image: dockurr/macos:13
    
    # 容器名稱
    container_name: my-macos
    
    # 環境變量設定
    environment:
      # 指定macOS版本（可選值：15, 14, 13, 12, 11）
      VERSION: "13"
      
      # 設定硬碟大小，默認為64GB
      DISK_SIZE: "256G"
      
      # 設定記憶體大小，默認為4GB
      RAM_SIZE: "8G"
      
      # 設定CPU核心數，默認為2核
      CPU_CORES: "4"
      
      # 啟用dhcp以讓macOS從路由器取得IP地址
      DHCP: "Y"
    
    # 設備掛載
    devices:
      # 激活KVM硬體加速
      - /dev/kvm:/dev/kvm
      
      # 附加USB總線，用於傳輸USB裝置
      - /dev/bus/usb:/dev/bus/usb
      
      # 網路設備，用於macvlan配置
      - /dev/vhost-net:/dev/vhost-net
    
    # 設定cgroup規則以允許網路設備操作
    device_cgroup_rules:
      - 'c *:* rwm'
    
    # 掛載存儲卷，指定宿主機的目錄到容器內的路徑
    volumes:
      # 將宿主機的/mnt/macos目錄掛載到容器的/storage
      - /mnt/macos:/storage
      
      # 分享一個測試用的檔案夾
      - ./shared:/Users/docker/shared
    
    # 通訊埠映射
    ports:
      # Web基於瀏覽器的檢視器埠
      - "8006:8006"
      
      # VNC遠端桌面埠（TCP）
      - "5900:5900/tcp"
      
      # VNC遠端桌面埠（UDP）
      - "5900:5900/udp"
    
    # 設定容器啟動後保持tty連接
    tty: true
    
    # 自動重啟容器
    restart: always

networks:
  # 定義一個macvlan網路，用於讓macOS取得獨立IP地址
  macvlan_net:
    driver: macvlan
    options:
      parent: eth0
```

# 說明與註解

1. **版本聲明**：
   - `version: '3.8'`：指定使用Docker Compose文件的版本，確保兼容性。

2. **服務定義**：
   - `services.macos.image`：指定使用的鏡像名稱和tag。默認為macOS Ventura（版本13）。
   
   - `container_name`：為容器指定一個易於識別的名字。

3. **環境變量**：
   - `VERSION`：用來選擇安裝的macOS版本，可選值包括15（Sequoia）、14（Sonoma）、13（Ventura）、12（Monterey）、11（Big Sur）。
   
   - `DISK_SIZE`：指定容器內虛擬硬碟的大小，默認為64GB。根據需求可以調整為更大的容量。
   
   - `RAM_SIZE`：設置分配給macOS的記憶體大小，默認為4GB，可根據宿主機資源情況進行調節。
   
   - `CPU_CORES`：指定容器內虛擬的CPU核心數，默認為2核，可以根據需求增加或減少。
   
   - `DHCP`：啟用dhcp模式，讓macOS能夠通過路由器自動取得IP地址，默認為"N"（禁用）。設置為"Y"即可啟用。

4. **設備掛載**：
   - `/dev/kvm`：掛載KVM硬體加速設備，確保容器內的虛擬機器性能 optimal。
   
   - `/dev/bus/usb`：將USB總線掛載到容器中，允許傳輸USB裝置如外接硬碟、鍵盤等。
   
   - `/dev/vhost-net`：用於macvlan網路配置，實現容器有獨立的MAC地址和IP地址。

5. **cgroup規則**：
   - `device_cgroup_rules`：設置設備控制組規則，允許網路設備的操作，確保dhcp和網路功能正常運行。

6. **存儲卷掛載**：
   - `/mnt/macos:/storage`：將宿主機的/mnt/macos目錄掛載到容器的/storage路徑，用於存儲macOS安裝和相關數據。
   
   - `./shared:/Users/docker/shared`：共享一個測試用的檔案夾，便於在宿主機和容器之間傳輸文件。

7. **通訊埠映射**：
   - `8006:8006`：將宿主機的8006埠映射到容器的Web檢視器埠，用於遠端控制macOS界面。
   
   - `5900:5900/tcp 和 5900:5900/udp`：將VNC（Virtual Network Computing）的埠映射出來，實現對macOS桌面的遠端連接。

8. **tty和restart設置**：
   - `tty: true`：確保容器啟動後保持TTY連接，方便直接輸入命令操作。
   
   - `restart: always`：設定容器在退出或崩潰時自動重啟，提高可靠性。

9. **網路配置**：
   - `networks.macvlan_net`：定義一個macvlan類型的網路，使用宿主機的eth0接口作為父接口。這樣可以讓容器獲得與宿主機相同的MAC地址，並能直接接入現有的網路環境，從路由器取得DHCP分配的IP地址。

**注意事項**：
- 在運行此docker-compose文件之前，請確保宿主機已安裝並啟用Docker服務，並且具備KVM硬體加速的支持。
- 若要使用macvlan網路，需檢查宿主機的操作系統是否支持該網路驅動，某些 distributions 可能需要額外的配置或安裝特定的KERNEL模組。
- 請遵守Apple的最終用戶許可協議，確保此容器只運行在官方授權的硬體上，避免任何版權法律問題。

這個docker-compose文件整合了多個環境變量和設備參數，並通過註解的形式詳細解釋了每個配置的作用，方便管理和維護。您可以根據具體需求調整相關設置，以實現最佳的使用體驗。