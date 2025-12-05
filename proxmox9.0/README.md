# Proxmox VE 9.0 輔助腳本集合

> 📚 **Proxmox VE 9.0 Helper Scripts Collection**

這個目錄包含一系列用於 Proxmox Virtual Environment (PVE) 9.0 的輔助腳本，主要用於自動化常見的虛擬化任務。

## 🚀 主要腳本

### 1. `debian13-vm.sh` - Debian 13 VM 創建腳本

自動創建 Debian 13 虛擬機的完整解決方案，支援以下功能：

- **自動化安裝**: 從官方 Debian Cloud 映像下載並配置
- **Docker 支援**: 可選安裝 Docker Engine 和 Docker Compose
- **監控集成**: 可選安裝 Prometheus Node Exporter
- **Cloud-Init 配置**: 完整的雲初始化設定
- **靈活配置**: 支持預設和進階設定模式

#### 使用方法

##### 本地執行

```bash
# 在 Proxmox VE 主機上執行
sudo bash debian13-vm.sh
```

##### 遠程安裝 (推薦)

```bash
# 從 GitHub 直接下載並執行
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-vm.sh)"
```

#### 支援的 Proxmox VE 版本

- Proxmox VE 8.0 – 8.9
- Proxmox VE 9.0+

### 2. `debian13-tool.sh` - Debian 13 工具腳本

額外的工具和維護腳本。

### 3. `lxc.sh` - LXC 容器管理腳本

LXC (Linux Containers) 相關的管理工具。

## 📋 功能特點

- **互動式配置**: 使用 whiptail 提供友好的圖形化配置界面
- **錯誤處理**: 完善的錯誤處理和清理機制
- **多存儲支援**: 支持各種 Proxmox 存儲類型 (NFS, ZFS, LVM 等)
- **網路配置**: 靈活的網路設定選項
- **安全預設**: 安全的預設配置和最佳實踐

## 🔧 系統需求

- **Proxmox VE**: 8.0+ (推薦 9.0+)
- **架構**: AMD64
- **網路**: 有效的互聯網連接 (用於下載映像)
- **權限**: root 權限

## 📖 相關文檔

- [README-LXC.md](README-LXC.md) - LXC 容器資源配置指南
- [Proxmox VE 文檔](https://pve.proxmox.com/pve-docs/)
- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)

## ⚠️ 注意事項

1. **測試環境**: 建議先在測試環境中驗證腳本
2. **備份重要資料**: 在生產環境使用前請備份重要資料
3. **網路配置**: 確保網路設定符合您的環境需求
4. **資源規劃**: 根據您的硬體資源合理配置 VM 參數

## 🤝 貢獻

歡迎提交 Issue 和 Pull Request 來改進這些腳本。

---

*這些腳本由社群維護，用於簡化 Proxmox VE 的常見操作任務。*
