Proxmox VE 虛擬機自動化腳本
📌 功能概述
一鍵創建 Debian 13 虛擬機（VM）。
支持自動配置磁盤大小、CPU 核心數、記憶體等資源。
可選安裝 Docker 及 Docker Compose。
禁用數據收集功能（無外部 API 調用）。
✅ 核心功能
預設磁盤大小：8GB（可通過腳本修改）。
Cloud-init 支持：使用 genericcloud 映像檔。
交互式配置：通過終端輸入自定義參數。
安全性：無需連接外部服務。
⚠️ 依賴環境
Proxmox VE 版本：8.x 或 9.0。
必要工具： curl 、 whiptail 。
🚀 快速開始
1. 下載腳本
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-vm.sh)"
```
2. 運行腳本
```bash
./debian13-vm.sh
```
3. 參數配置
默認值：直接按 Enter 使用預設配置。
自定義：輸入 CPU 核心數、記憶體大小等。
⚙️ 自定義選項
修改默認磁盤大小
編輯腳本中的 DISK_SIZE 變量：

bash
DISK_SIZE="20G"  # 默認 8G，修改為 20G
禁用 Cloud-init
將腳本中的 CLOUD_INIT 設為 no ：

bash
CLOUD_INIT="no"
強制跳過確認
添加 -y 參數（需腳本支持）：

bash
./debian13-vm.sh -y
❓ 常見問題
Q1: 如何解決權限不足？
確保以 root 運行：

bash
sudo -i
./debian13-vm.sh
Q2: 如何徹底移除數據收集代碼？
刪除 api.func 文件並移除主腳本中的引用：

bash
rm api.func
Q3: 支持 ARM64 架構嗎？
僅支持 AMD64，ARM 需使用 PiMox 專用腳本。

📜 許可證
MIT License | 詳情

🤝 貢獻指南
Fork 本倉庫。
提交 Pull Request。
確保代碼通過基礎測試。