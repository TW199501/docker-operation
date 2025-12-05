# Elf-Nginx 容器化部署方案

## 📖 專案概述

Elf-Nginx 是一個基於 Nginx 1.29.3 的企業級容器化部署解決方案，整合了高可用性、安全防護、地理位置識別和自動化運維等進階功能。

### 🚀 主要特色

- **高性能**: 基於源碼自定義編譯，整合多個效能優化模組
- **高可用**: Keepalived 實現主從故障轉移機制
- **安全防護**: ModSecurity WAF + GeoIP + IP過濾多重保護
- **自動化**: 定期更新地理IP資料庫和Cloudflare配置
- **模組化**: 動態模組載入，靈活配置管理

## 🏗️ 技術架構

### 核心組件

#### Web服務器

- **Nginx版本**: 1.29.3 (自定義編譯)
- **基礎映像**: Debian Bookworm Slim
- **編譯選項**: 完整功能集，包含SSL、HTTP/2、HTTP/3支援

#### 第三方模組集成

| 模組名稱 | 功能描述 | 版本 |
|---------|---------|------|
| ngx_http_geoip2_module | GeoIP2地理位置識別 | 最新版 |
| ngx_brotli | Google Brotli壓縮 | 最新版 |
| headers-more-nginx-module | HTTP頭部自定義 | 最新版 |
| ngx_cache_purge | 快取清理功能 | 最新版 |
| njs | JavaScript支援 | 最新版 |
| ModSecurity-nginx | WAF安全防護 | v1.0.4 |

#### 依賴庫版本

- **OpenSSL**: 3.5.4
- **PCRE2**: 10.47
- **zlib**: 1.3.1
- **libmaxminddb**: 1.12.2

## 🚀 快速開始

### 環境要求

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **系統資源**: 最低2GB RAM, 4GB磁碟空間
- **網路**: 支持80/443端口映射

### 快速部署

```bash
# 構建容器映像
cd nginx1.29.3-docker
docker compose -f docker-compose.build.yml build

# 啟動服務
docker compose -f docker-compose.build.yml up -d --build

# 查看服務狀態
docker compose ps
```

## 📁 文檔結構

- [README.md](./README.md) - 專案總覽與快速開始
- [README.en.md](./README.en.md) - English version
- [deployment-guide.md](./deployment-guide.md) - 詳細部署指南
- [configuration.md](./configuration.md) - 配置詳解
- [network-guide.md](./network-guide.md) - 網路配置教學
- [troubleshooting.md](./troubleshooting.md) - 故障排除
- [development.md](./development.md) - 開發與維護

## 🛠️ 主要功能

### 1. 容器化部署

- 基於 Docker 的完整容器化解決方案
- 支援多環境部署（開發、測試、生產）
- 自動化建置和部署流程

### 2. 高可用性

- Keepalived 實現主從故障轉移
- 健康檢查機制
- 自動故障恢復

### 3. 安全防護

- ModSecurity WAF 整合
- GeoIP 地理位置過濾
- IP 白名單/黑名單管理
- SSL/TLS 強加密配置

### 4. 自動化運維

- GeoIP 資料庫定期更新
- Cloudflare IP 範圍同步
- 自動化日誌管理
- 系統監控告警

## 📞 技術支援

### 相關文檔

- [Nginx官方文檔](https://nginx.org/en/docs/)
- [ModSecurity文檔](https://github.com/SpiderLabs/ModSecurity/wiki)
- [Keepalived文檔](https://keepalived.readthedocs.io/)

### 項目資訊

- **版本**: 1.29.3
- **更新日期**: 2025-12-05
- **維護者**: Elf團隊

---

*本專案致力於提供企業級nginx容器化解決方案，如有問題或建議，歡迎提交Issue或Pull Request。*
