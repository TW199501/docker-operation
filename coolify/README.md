## 自託管安裝

如果您喜歡掌控一切並自行管理，那麼自行託管 Coolify 是您的理想選擇。

除了伺服器費用外，它是完全免費的，並且讓您可以完全控制您的設定。

⚡️快速安裝（建議）：

```
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

在終端機中執行此腳本，Coolify 將自動安裝。更多詳情，包括防火牆配置和先決條件，請查看以下指南。

致Ubuntu用戶：

自動安裝腳本僅適用於 Ubuntu LTS 版本（20.04、22.04、24.04）。如果您使用的是非 LTS 版本（例如 24.10），請使用下方的[手動安裝](https://coolify.io/docs/get-started/installation#manual-installation)方法。

## 開始之前

安裝 Coolify 之前，請確保您的伺服器符合必要的要求。

### 1. 伺服器要求

您需要一台具有 SSH 存取權限的伺服器。例如：

* VPS（虛擬專用伺服器）
* 專用伺服器
* 虛擬機器（VM）
* 樹莓派（請參閱我們的[樹莓派作業系統設定指南](https://coolify.io/docs/knowledge-base/how-to/raspberry-pi-os#prerequisites)）
* 或任何其他具有 SSH 存取權限的伺服器

筆記：

為了避免與現有應用程式發生衝突，最好使用全新的伺服器來執行 Coolify。

提示：

如果您還沒有選定伺服器供應商，不妨考慮使用[Hetzner](https://coolify.io/hetzner)。您也可以使用我們的[推薦連結](https://coolify.io/hetzner)來支持該專案。

### 2. 支援的作業系統

Coolify支援多種Linux發行版：

* 基於 Debian 的系統（例如 Debian、Ubuntu - 所有版本均支持，但非 LTS 版 Ubuntu 需要手動安裝）
* 基於 Redhat（例如 CentOS、Fedora、Redhat、AlmaLinux、Rocky、Asahi）
* 基於 SUSE 的系統（例如，SLES、SUSE、openSUSE）
* Arch Linux（註：並非所有 Arch 衍生版本都支援）
* Alpine Linux
* 樹莓派作業系統 64 位元（Raspbian）

筆記

對於某些發行版（例如 AlmaLinux），Docker 必須預先安裝。如果安裝腳本失敗，請手動安裝 Docker 並重新執行腳本。

其他 Linux 發行版可能與 Coolify 相容，但尚未經過官方測試。

### 3. 支援的架構

Coolify 可在 64 位元系統上運作：

* AMD64
* ARM64

⚠️ 樹莓派用戶請注意：

請務必使用 64 位元版本的 Raspberry Pi OS（Raspbian）。詳情請參閱我們的[Raspberry Pi OS 設定指南](https://coolify.io/docs/knowledge-base/how-to/raspberry-pi-os#prerequisites)。

### 4. 最低硬體需求

您的伺服器至少應具備：

* **CPU**：2 核
* **記憶體（RAM）**：2 GB
* **儲存空間**：30 GB 可用空間

Coolify 可能在配置低於上述配置的伺服器上也能正常運行，但我們建議使用稍高的最低配置要求。

這樣可以確保用戶擁有足夠的資源來部署多個應用程式而不會出現效能問題。

小心！

如果你在同一台伺服器上執行建置程式和 Coolify，請監控資源使用情況。資源使用率過高可能會導致伺服器無回應。

如有需要，請考慮啟用交換空間或升級伺服器。

### 5. 專案所需的伺服器資源

您需要的資源取決於您的專案。例如，如果您要託管多個服務或大型應用程序，請選擇具有更高 CPU、記憶體和儲存空間的伺服器。

⚙️ 範例設定：

Andras 的生產應用程式運行在一台伺服器上，該伺服器配置如下：

* **記憶體**：8GB（平均使用量：3.5GB）
* **CPU**：4 核心（平均使用率：20-30%）
* **儲存空間**：150GB（平均使用量：40GB）

這種配置可以輕鬆支援：

* 3 個 NodeJS 應用
* 4. 靜態網站
* 合理的分析
* Fider（回饋工具）
* UptimeKuma（正常運作時間監控）
* Ghost（新聞簡報）
* 3. Redis 資料庫
* 2 個 PostgreSQL 資料庫

## 安裝方法

Coolify有兩種安裝方式：

* [快速安裝](https://coolify.io/docs/get-started/installation#quick-installation-recommended)（建議）
* [手動安裝](https://coolify.io/docs/get-started/installation#manual-installation)

我們強烈建議**快速安裝**方法，因為它能自動完成安裝過程，並降低出錯的幾率。

---

### 快速安裝（建議）

這是啟動並運行 Coolify 的最簡單、最快捷的方法。

#### 1. 準備伺服器

* 以 root 使用者身分登入（目前還不完全支援非 root 使用者）。
* 依照[SSH 設定指南](https://coolify.io/docs/knowledge-base/server/openssh#ssh-settings-configuration)設定 SSH 。
* 借助[防火牆指南](https://coolify.io/docs/knowledge-base/server/firewall)設定防火牆。
* 請確保已安裝[curl](https://curl.se/)（通常已預先安裝）。

#### 2. 運行安裝腳本

伺服器準備就緒後，運行：

```
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

查看[腳本原始碼](https://github.com/coollabsio/coolify/blob/main/scripts/install.sh)

提示：

如果您未以 root 使用者身分登入，請使用 sudo 執行腳本：

```
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

您也可以在安裝過程中直接設定第一個管理員帳戶。詳情請參閱：[使用環境變數建立 Root 用戶](https://coolify.io/docs/knowledge-base/create-root-user-with-env)

您可以設定多個環境變數來自訂 Coolify 安裝。

例如，您可以設定預設的 root 使用者或定義預設的 docker 網路池。

有關更多詳細信息，請參閱“[使用 ENV 定義自訂 Docker 網路”](https://coolify.io/docs/knowledge-base/define-custom-docker-network-with-env)或“[使用 ENV 建立 Root 使用者”](https://coolify.io/docs/knowledge-base/create-root-user-with-env)。

#### 3. 造訪 Coolify

安裝完成後，腳本將顯示您的 Coolify URL（例如 `http://203.0.113.1:8000`：）。造訪此 URL，您將被重新導向到註冊頁面以建立您的第一個管理員帳戶。

⚠️ 注意：

**安裝完成後請立即建立管理員帳戶。如果其他人比您先訪問註冊頁面，他們可能會獲得您伺服器的完全控制權。**

筆記：

如果您在家庭網路中的 Raspberry Pi 上安裝了 Coolify，請使用您的私人 IP 位址存取它，因為公用 IP 可能無法正常運作。

#### 安裝程式的功能：

* 安裝必要的工具（curl、wget、git、jq、openssl）
* 安裝 Docker Engine（版本 24+）
* 配置 Docker 設定（日誌記錄、守護程式）
* 在以下位置設定目錄 `/data/coolify`
* 設定伺服器管理的 SSH 金鑰
* 安裝並啟動 Coolify

⚠️ 注意：

不支援透過 snap 安裝的 Docker！

**快速安裝指南到此結束。如果您已依照上述步驟操作，現在即可開始使用 Coolify。以下指南適用於希望手動安裝和設定 Coolify 的使用者。**

---

### 手動安裝

如果您希望擁有更多控制權，可以手動安裝 Coolify。這一種方法需要一些額外的步驟。

筆記

以下情況需採用手動安裝方法：

* 非 LTS 版 Ubuntu（例如 24.10）
* 自動腳本遇到問題的系統

#### 先決條件

* **SSH**：確保已啟用 SSH 並已正確設定（請參閱[SSH 設定指南](https://coolify.io/docs/knowledge-base/server/openssh)）。
* **curl**：確認[curl](https://curl.se/)已安裝。
* **Docker Engine**：依照官方[Docker Engine 安裝指南](https://docs.docker.com/engine/install/#server)（版本 24+）安裝 Docker。

⚠️ 注意：

不支援透過 snap 安裝的 Docker！

---

手動設定步驟如下：

#### 1. 建立目錄

在以下目錄下建立 Coolify 的基礎目錄 `/data/coolify`：

```
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic
```

#### 2. 產生並新增 SSH 金鑰

為 Coolify 產生 SSH 金鑰以管理您的伺服器：

```
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify
```

然後，將公鑰添加到您的 `~/.ssh/authorized_keys`：

```
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

提示！

如果您已經擁有 SSH 金鑰，則可以跳過產生新金鑰的步驟，但請記住在安裝後將其新增至您的 Coolify 實例中。

#### 3. 設定設定檔

從 Coolify 的 CDN 下載必要檔案到 `/data/coolify/source`：

```
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /data/coolify/source/.env
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh
```

#### 4. 設定權限

為 Coolify 檔案和目錄設定正確的權限：

```
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify
```

#### 5. 生成值

`.env`使用安全性的隨機值更新檔案：

```
sed -i "s|APP_ID=.*|APP_ID=$(openssl rand -hex 16)|g" /data/coolify/source/.env
sed -i "s|APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|g" /data/coolify/source/.env
```

⚠️ 重要提示：

這些命令僅在首次安裝 Coolify 時執行。之後更改這些值可能會導致安裝失敗。請妥善保管！

#### 6. 建立 Docker 網絡

確保已建立 Docker 網路：

```
docker network create --attachable coolify
```

#### 7. 啟動 Coolify

使用 Docker Compose 啟動 Coolify：

```
docker compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml up -d --pull always --remove-orphans --force-recreate
```

⚠️ 重要提示：

`docker login`如果您遇到上述任何問題，此時可能需要採取相應措施。

#### 8. 造訪 Coolify

現在您可以透過造訪 `http://203.0.113.1:8000`（將替換 `203.0.113.1`為您的伺服器的 IP 位址）來存取 Coolify。

如果您在任何步驟遇到困難，歡迎加入我們的[Discord 社區](https://coolify.io/discord)，並在支援論壇頻道中發文求助。
