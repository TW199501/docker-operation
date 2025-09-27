
# Windows 簡明使用手冊

## 總覽
這個專案允許你在 Docker 容器中運行 Windows 作業系統，並提供自動安裝功能。以下是主要特色與使用方法。

---

## 功能 ✨
- **ISO 下載器**: 自動下載指定版本的 Windows ISO。
- **KVM 加速**: 支援硬體虛擬化加速（需 BIOS 開啟 VT-x 或 SVM）。
- **Web 基础檢視器**: 通過瀏覽器遠端連線查看安裝進度。

---

## 使用方法 🐳

### 1. 使用 Docker Compose
將以下內容加入 `docker-compose.yml`：
```yaml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"          # 選擇 Windows 版本（預設為 Windows 11 Pro）
    devices:
      - /dev/kvm            # KVM 硬體加速
      - /dev/net/tun        # 網路_TUN 设備
    cap_add:
      - NET_ADMIN           # 授予網路管理權限
    ports:
      - 8006:8006           # Web 檢視器埠
      - 3389:3389/tcp       # RDP 通訊埠（TCP）
      - 3389:3389/udp       # RDP 通訊埠（UDP）
    volumes:
      - ./windows:/storage  # 指定儲存位置
    restart: always          # 自動重啟容器
    stop_grace_period: 2m    # 容器停止前等待時間
```

### 2. 使用 Docker CLI
直接執行命令：
```bash
docker run -it --rm --name windows \
-p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --cap-add NET_ADMIN \
-v "${PWD:-.}/windows:/storage" --stop-timeout 120 dockurr/windows
```

### 3. 使用 Kubernetes
```bash
kubectl apply -f https://raw.githubusercontent.com/dockur/windows/refs/heads/master/kubernetes.yml
```

---

## 常見問題解答 💬

### 如何使用？
1. 啟動容器後，開啟瀏覽器連線至 `http://127.0.0.1:8006`。
2. 安裝程序會自動執行，安裝完成後即可看到桌面。

### 如何選擇 Windows 版本？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  VERSION: "11"          # 選擇版本（如 "10" 表示 Windows 10 Pro）
```
可用版本如下：

| **值** | **版本名稱**            | **大小** |
|---|---|---|
| `11`   | Windows 11 Pro           | 5.4 GB   |
| `11l`  | Windows 11 LTSC          | 4.7 GB   |
| `11e`  | Windows 11 Enterprise    | 5.3 GB   |
| `10`   | Windows 10 Pro           | 5.7 GB   |
| `10l`  | Windows 10 LTSC          | 4.6 GB   |
| `10e`  | Windows 10 Enterprise    | 5.2 GB   |
| `8e`   | Windows 8.1 Enterprise   | 3.7 GB   |
| `7u`   | Windows 7 Ultimate       | 3.1 GB   |
| `vu`   | Windows Vista Ultimate   | 3.0 GB   |
| `xp`   | Windows XP Professional  | 0.6 GB   |
| `2k`   | Windows 2000 Professional | 0.4 GB   |

---

### 如何更改儲存位置？
在 `docker-compose.yml` 中加入：
```yaml
volumes:
  - ./windows:/storage       # 將 "./windows" 指定為儲存目錄
```

### 如何調整硬碟大小？
加入環境變量：
```yaml
environment:
  DISK_SIZE: "256G"          # 選擇所需容量（預設為 64 GB）
```
注意：若要擴展現有硬碟，需手動調整磁區。

---

### 如何與主機共用檔案？
1. 在 Windows 中開啟「此電腦」，進入「網路」。
2. 找到名為 `host.lan` 的電腦，並連接其 `Data` 共用夾。
3. 通過 Docker 綁定掛載：
```yaml
volumes:
  - ./example:/data          # 將 "./example" 指定為共用夾路徑
```
此路徑將在 Windows 中顯示為 `\\host.lan\Data`。

---

### 如何調整 CPU 或記憶體？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  RAM_SIZE: "8G"             # 設定記憶體大小（預設 4 GB）
  CPU_CORES: "4"             # 設定核心數（預設 2 核心）
```

---

### 如何設定帳號密碼？
在 `docker-compose.yml` 中加入：
```yaml
environment:
  USERNAME: "bill"           # 自訂用戶名
  PASSWORD: "gates"          # 自訂密碼
```
預設帳戶為 `Docker`，密碼為 `admin`。

---

### 如何安裝自訂版本？
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

---

### 如何執行自訂腳本？
將腳本放在 `install.bat` 中，並掛載至容器：
```yaml
volumes:
  - ./example:/oem                       # 將 "./example" 挂載到 C:\OEM
```
安裝完成后，`install.bat` 會自動執行。

---

### 如何使用 RDP 連線？
1. 在 Windows 中開啟「遠端桌面連線」（按 `Win + R`，輸入 `mstsc`）。
2. 輸入容器 IP（預設為 `localhost`），帳戶名稱為 `Docker`，密碼為 `admin`。

---

### 如何設定dhcp？
若要讓 Windows 取得路由器分配的 IP：
在 `docker-compose.yml` 中加入：
```yaml
environment:
  DHCP: "Y"                          # 啟用dhcp
devices:
  - /dev/vhost-net                   # 添加網路設備
device_cgroup_rules:
  - 'c *:* rwm'                     # 設定設備權限
```

---

### 如何擴展硬碟？
若要新增多顆硬碟，可在 `docker-compose.yml` 中加入：
```yaml
environment:
  DISK2_SIZE: "32G"                 # 新增第二顆硬碟（32 GB）
```

---

### 如何直接使用_usb 裝置？
在 `docker-compose.yml` 中加入：
```yaml
devices:
  - /dev/bus/usb                     # 添加_usb 總線路徑
environment:
  ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"  # 設定_usb裝置參數（根據lsusb結果）
```

---

### 如何檢查系統是否支援 kvm？
執行以下命令：
```bash
sudo apt install cpu-checker          # 安裝cpu-checker
sudo kvm-ok                          # 檢查 kvm 支援狀況
```
若出現錯誤，請確認 BIOS 中已開啟.virtualization 技術（如 Intel VT-x 或 AMD SVM）。

---

希望這份手冊能幫助你順利使用 Windows in Docker！如果有其他問題，歡迎前往 [GitHub](https://github.com/dockur/windows) 查詢。