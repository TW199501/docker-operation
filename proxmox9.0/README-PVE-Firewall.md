# PVE VM 防火牆管理工具使用說明

## ⚠️ 重要前置設定

> [!CAUTION]
> **在使用此腳本之前，必須先啟用 Proxmox VE 的防火牆功能！**

### 必須先啟用的防火牆設定

#### 1. **啟用資料中心防火牆**
在 Proxmox VE Web 介面操作：
```
Datacenter (資料中心)
  → Firewall (防火牆)
    → Options (選項)
      → Firewall: ✅ 勾選啟用
```

#### 2. **啟用節點防火牆**
針對每個節點操作：
```
Datacenter (資料中心)
  → [節點名稱，例如: pve1]
    → Firewall (防火牆)
      → Options (選項)
        → Firewall: ✅ 勾選啟用
```

**操作截圖說明：**
- 左側選單找到 `Datacenter`（資料中心）
- 展開後點選 `Firewall`（防火牆）
- 點擊 `Options`（選項）標籤頁
- 雙擊 `Firewall` 項目，勾選啟用並確認

> [!IMPORTANT]
> 如果資料中心或節點的防火牆沒有啟用，即使設定了 VM 防火牆規則也**不會生效**！

---

## 📋 腳本功能概述

`pve-fw.sh` 是一個互動式的 Proxmox VE 虛擬機防火牆管理工具，可以：
- 快速啟用/關閉 VM 防火牆
- 套用預設安全 Profile（Web Server、IP 白名單）
- 自訂防火牆規則
- 自動檢查並修正網卡的 `firewall=1` 設定

---

## 🔧 前置需求

### 必要套件
在 PVE 節點上安裝 `jq`（JSON 處理工具）：
```bash
apt update
apt install -y jq
```

### 快速使用（推薦）
**直接從 GitHub 下載並執行：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/pve-fw.sh)"
```

> [!TIP]
> 這個指令會自動下載最新版本的腳本並執行，無需手動下載或設定權限

### 手動下載使用
如果需要離線使用或修改腳本：
```bash
# 下載腳本
wget https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/pve-fw.sh

# 或使用 curl
curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/pve-fw.sh -o pve-fw.sh

# 設定執行權限
chmod +x pve-fw.sh

# 執行腳本
./pve-fw.sh
```

---

## 🎯 主要功能說明

### 1️⃣ **VM 選擇**
腳本啟動後會列出叢集中所有 VM：
```
目前叢集 VM 清單：
VMID    NODE    NAME
--------------------------------
100     pve1    web-server
101     pve2    database
請輸入要操作的 VMID: _
```

### 2️⃣ **網卡防火牆檢查**
自動檢查 VM 網卡是否啟用 `firewall=1` 參數：
- ✅ 如果已啟用，顯示確認訊息
- ⚠️ 如果未啟用，詢問是否自動修正

> [!NOTE]
> VM 網卡必須有 `firewall=1` 參數，防火牆規則才會對該網卡生效

### 3️⃣ **互動式管理選單**
```
==== PVE VM 防火牆管理 ====
操作 VM: 100 (節點: pve1)
1) 啟用防火牆
2) 關閉防火牆
3) 套用 Web Server Profile (22+80+443，其餘 DROP)
4) 套用 IP 白名單 Profile (只允許某 IP/網段，其餘 DROP)
5) 自訂新增一條規則
6) 顯示目前規則
7) 清空所有規則
0) 離開
請選擇: _
```

---

## 📦 預設 Profile 說明

### Web Server Profile (選項 3)
適用於對外提供網頁服務的 VM：

| 規則 | 說明 |
|------|------|
| SSH (22) | 允許來自內網 `192.168.0.0/16` 的 SSH 連線 |
| HTTP (80) | 允許所有來源的 HTTP 連線 |
| HTTPS (443) | 允許所有來源的 HTTPS 連線 |
| 其他 | 全部 DROP（丟棄） |

**使用場景：**
- 公開網站伺服器
- Web 應用服務
- API 服務

---

### IP 白名單 Profile (選項 4)
只允許特定 IP 或網段訪問：

```bash
請輸入允許的來源 IP 或網段 (例如 192.168.25.0/24 或 1.2.3.4): 192.168.25.0/24
```

| 規則 | 說明 |
|------|------|
| 指定 IP/網段 | 允許該來源的所有流量 |
| 其他 | 全部 DROP（丟棄） |

**使用場景：**
- 內部管理伺服器
- 限定辦公室 IP 訪問的服務
- 需要高安全性的系統

---

## 🛠️ 自訂規則功能

### 規則參數說明

#### **方向 (Direction)**
- `in`：進入 VM 的流量（預設，最常用）
- `out`：離開 VM 的流量

#### **動作 (Action)**
- `ACCEPT`：允許該流量
- `DROP`：直接丟棄，不回應（推薦，更安全）
- `REJECT`：拒絕並回應對方

#### **其他參數**
- **通訊協定 (proto)**：tcp / udp / icmp
- **目的 Port (dport)**：單一 port（如 `22`）或範圍（如 `80:443`）
- **來源 IP (source)**：可指定 IP 或網段（如 `192.168.25.0/24`）

### 自訂規則範例

#### 範例 1：允許特定 IP 的 SSH 連線
```
方向: 1 (in)
動作: 1 (ACCEPT)
通訊協定: tcp
目的 Port: 22
來源 IP: 192.168.1.100
```

#### 範例 2：允許所有 ICMP (Ping)
```
方向: 1 (in)
動作: 1 (ACCEPT)
通訊協定: icmp
目的 Port: (留空)
來源 IP: (留空)
```

#### 範例 3：拒絕所有出站 SMTP
```
方向: 2 (out)
動作: 2 (DROP)
通訊協定: tcp
目的 Port: 25
來源 IP: (留空)
```

---

## 📊 查看現有規則

選擇選項 6 會顯示目前所有規則：
```
VM 100 目前規則：
0    in    ACCEPT    tcp    port=22        src=192.168.0.0/16
1    in    ACCEPT    tcp    port=80        src=-
2    in    ACCEPT    tcp    port=443       src=-
3    in    DROP      -      port=-         src=-
```

**欄位說明：**
- **pos**：規則位置（優先順序，0 最優先）
- **type**：方向（in/out）
- **action**：動作（ACCEPT/DROP/REJECT）
- **proto**：協定
- **port**：目的 Port
- **src**：來源 IP

---

## 🔄 使用流程建議

### 標準工作流程

```bash
# 1. 確認前置設定
# - 資料中心防火牆：已啟用 ✅
# - 節點防火牆：已啟用 ✅

# 2. 執行腳本
./pve-fw.sh

# 3. 選擇要設定的 VM
請輸入要操作的 VMID: 100

# 4. 確認網卡設定
# 腳本會自動檢查，如需要會詢問是否修正

# 5. 選擇適合的 Profile 或自訂規則
# - Web Server → 選項 3
# - 只允許特定 IP → 選項 4
# - 完全自訂 → 選項 5

# 6. 驗證規則
# 選項 6 查看設定是否正確

# 7. 測試連線
# 從外部測試防火牆是否正常運作
```

---

## ⚙️ 命令列直接操作

### 手動啟用 VM 防火牆
```bash
pvesh set /nodes/pve1/qemu/100/firewall/options -enable 1
```

### 手動新增規則
```bash
# 允許 SSH
pvesh create /nodes/pve1/qemu/100/firewall/rules \
  -type in -action ACCEPT -enable 1 -proto tcp -dport 22 -source 192.168.0.0/16

# 允許 HTTP
pvesh create /nodes/pve1/qemu/100/firewall/rules \
  -type in -action ACCEPT -enable 1 -proto tcp -dport 80
```

### 手動設定網卡 firewall=1
```bash
# 查看目前設定
qm config 100 | grep net0

# 修改網卡加上 firewall=1
# 假設原本是: net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0
qm set 100 -net0 virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,firewall=1
```

---

## 🔍 故障排除

### 問題 1：規則設定了但不生效
**檢查清單：**
- [ ] 資料中心防火牆已啟用
- [ ] 節點防火牆已啟用
- [ ] VM 防火牆已啟用（選項 1）
- [ ] 網卡有 `firewall=1` 參數
- [ ] 規則順序正確（DROP 規則應在最後）

### 問題 2：腳本執行錯誤
```bash
# 確認 jq 已安裝
which jq

# 確認 pvesh 可執行
pvesh --version

# 確認在 PVE 節點上執行
hostname
```

### 問題 3：無法連線到 VM
**安全建議：**
> [!WARNING]
> 在修改防火牆前，建議先透過 PVE Console 連線，避免 SSH 被鎖定無法遠端管理

---

## 🎓 最佳實踐

### 1. **防火牆規則原則**
- ✅ 最小權限原則：只開放必要的 Port
- ✅ 白名單優先：使用 IP 限制而非全開放
- ✅ 明確 DROP：最後加上 DROP 規則拒絕其他流量

### 2. **安全建議**
```bash
# ❌ 不推薦：SSH 對所有 IP 開放
-source 0.0.0.0/0 -dport 22

# ✅ 推薦：SSH 只允許內網或特定 IP
-source 192.168.0.0/16 -dport 22
```

### 3. **測試流程**
```bash
# 1. 先設定防火牆
# 2. 從允許的 IP 測試連線
ssh user@vm-ip

# 3. 從不允許的 IP 測試（應連線失敗）
# 4. 確認日誌
pvesh get /nodes/pve1/qemu/100/firewall/log
```

---

## 📚 相關資源

- [Proxmox VE 防火牆官方文件](https://pve.proxmox.com/wiki/Firewall)
- [pvesh API 參考](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- 其他腳本：`README-LXC.md`（LXC 容器資源配置）

---

## 📝 注意事項

> [!TIP]
> 定期檢查防火牆規則，移除不必要的開放 Port 以維持安全性

> [!CAUTION]
> 修改防火牆規則可能導致服務中斷，建議在維護時段進行

---

**版本資訊：** 適用於 Proxmox VE 9.0+  
**最後更新：** 2025-12-10
