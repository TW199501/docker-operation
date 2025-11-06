# VS Code 測試環境安裝和配置指南

## 📋 概述

本指南將幫助您在 VS Code 中設置完整的 Docker 操作專案測試和開發環境。

## 🚀 快速開始

### 1. 安裝必要的 VS Code 擴展

打開 VS Code，安裝以下推薦擴展：

#### 必裝擴展：
- **ShellCheck** (`timonwong.shellcheck`) - Shell 腳本靜態分析
- **Bash Debug** (`rogalmic.bash-debug`) - 調試 Shell 腳本
- **Docker** (`ms-azuretools.vscode-docker`) - Docker 工具支持
- **YAML** (`redhat.vscode-yaml`) - YAML 語言支持

#### 推薦擴展：
- **GitLens** (`eamodio.gitlens`) - 增強 Git 功能
- **Test Explorer** (`hbenl.vscode-test-explorer`) - 測試管理
- **Prettier** (`esbenp.prettier-vscode`) - 代碼格式化

### 2. 重新載入 VS Code

安裝擴展後，重新載入 VS Code 以應用配置：
- `Ctrl+Shift+P` → "Developer: Reload Window"

## 🎯 使用測試功能

### 測試快捷鍵

| 快捷鍵 | 功能 | 說明 |
|--------|------|------|
| `Ctrl+Shift+T` | 運行所有測試 | 完整的測試套件 |
| `Ctrl+Shift+U` | 運行單元測試 | 快速單元測試 |
| `Ctrl+Shift+I` | 運行集成測試 | 組件間測試 |
| `Ctrl+Shift+E` | 運行端到端測試 | 完整流程測試 |
| `Ctrl+Shift+Y` | 驗證 Docker Compose | 檢查配置語法 |
| `Ctrl+Shift+S` | 檢查 Shell 語法 | 腳本語法檢查 |
| `Ctrl+Shift+H` | 顯示測試幫助 | 測試框架說明 |

### 測試任務面板

1. 打開命令面板：`Ctrl+Shift+P`
2. 輸入 "Tasks: Run Task"
3. 選擇要運行的測試任務

### 調試測試

1. 打開調試面板：`Ctrl+Shift+D`
2. 選擇調試配置：
   - "調試測試腳本 (所有測試)"
   - "調試測試腳本 (單元測試)"
   - "調試單個 Shell 腳本"
3. 設置斷點並開始調試

## 🔧 配置詳解

### settings.json 配置說明

```json
{
  // Shell 腳本配置
  "shellcheck.enable": true,              // 啟用 ShellCheck
  "shellcheck.exclude": ["SC2034"],       // 排除特定警告

  // 文件關聯
  "files.associations": {
    "*.sh": "shellscript",                // Shell 文件關聯
    "Dockerfile*": "dockerfile"           // Dockerfile 關聯
  },

  // YAML 模式
  "yaml.schemas": {
    "docker-compose-spec": ["docker-compose*.yml"]
  },

  // 終端配置
  "terminal.integrated.shell.windows": "powershell.exe",
  "terminal.integrated.shellArgs.windows": ["-NoExit", "-Command", "cd '${workspaceFolder}'"]
}
```

### tasks.json 任務配置

#### 測試任務
- **運行所有測試**: `cd tests && bash run_all_tests.sh all`
- **運行單元測試**: `cd tests && bash run_all_tests.sh unit`
- **驗證 Docker Compose**: 檢查所有 compose 文件語法

#### 構建任務
- **檢查 Shell 語法**: 使用 `bash -n` 檢查語法
- **運行 ShellCheck**: 靜態代碼分析
- **清理測試環境**: 刪除測試臨時文件

### launch.json 調試配置

#### 測試腳本調試
```json
{
  "name": "調試測試腳本 (所有測試)",
  "type": "bashdb",
  "request": "launch",
  "program": "${workspaceFolder}/tests/run_all_tests.sh",
  "args": ["all"]
}
```

#### Shell 腳本調試
```json
{
  "name": "調試單個 Shell 腳本",
  "type": "bashdb",
  "request": "launch",
  "program": "${file}"
}
```

## 📊 測試結果查看

### 終端面板
測試運行時的詳細輸出會顯示在終端面板中。

### 問題面板
測試錯誤會自動顯示在問題面板中：
- 🔴 **錯誤**: 必須修復的問題
- 🟡 **警告**: 建議修復的問題
- ℹ️ **信息**: 一般信息

### 測試總結
每次測試運行後會顯示摘要：
```
測試腳本 / Test Scripts    : 8
失敗項目 / Failed Items    : 0
跳過項目 / Skipped Items   : 2
成功率 / Success Rate      : 100%
```

## 🐛 故障排除

### 常見問題

#### 1. ShellCheck 不工作
```bash
# 檢查擴展是否安裝
code --list-extensions | grep shellcheck

# 重新安裝擴展
code --install-extension timonwong.shellcheck
```

#### 2. Bash Debug 不工作
```bash
# 安裝 bashdb
# Ubuntu/Debian:
sudo apt-get install bashdb

# CentOS/RHEL:
sudo yum install bashdb
```

#### 3. 測試任務失敗
```bash
# 檢查權限
chmod +x tests/*.sh

# 檢查依賴
which bash docker-compose shellcheck
```

#### 4. Docker 命令不可用
```bash
# 檢查 Docker 服務
sudo systemctl status docker

# 添加用戶到 docker 組
sudo usermod -aG docker $USER
```

### 調試技巧

#### 查看詳細日誌
```bash
# 在 VS Code 中設置
"testExplorer.logLevel": "verbose"
```

#### 手動運行測試
```bash
# 直接在終端運行
cd tests
bash run_all_tests.sh -v all
```

## 🎨 自定義配置

### 添加新的測試任務

編輯 `.vscode/tasks.json`:
```json
{
  "label": "我的自定義測試",
  "type": "shell",
  "command": "bash",
  "args": ["-c", "echo '自定義測試邏輯'"],
  "group": "test"
}
```

### 添加新的快捷鍵

編輯 `.vscode/keybindings.json`:
```json
{
  "key": "ctrl+shift+m",
  "command": "workbench.action.tasks.runTask",
  "args": "我的自定義測試"
}
```

### 自定義測試配置

編輯 `tests/test-config.ini`:
```ini
[tests]
unit_tests = true
integration_tests = true

[environment]
use_real_system = false
test_timeout = 300
```

## 📚 進一步閱讀

- [VS Code 官方文檔](https://code.visualstudio.com/docs)
- [ShellCheck 文檔](https://github.com/koalaman/shellcheck)
- [Docker VS Code 擴展](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker)
- [Bash Debug 擴展](https://marketplace.visualstudio.com/items?itemName=rogalmic.bash-debug)

## 🆘 獲取幫助

如果遇到問題：

1. 檢查 VS Code 輸出面板的錯誤信息
2. 查看終端中的詳細錯誤信息
3. 檢查我們的測試文檔：`tests/README.md`
4. 查看 GitHub Issues 中的已知問題

## 🎉 完成設置！

現在您已經擁有了完整的 VS Code 測試和開發環境，可以：

- ✅ **一鍵運行測試** (Ctrl+Shift+T)
- ✅ **調試 Shell 腳本** (F5)
- ✅ **語法檢查和自動補全**
- ✅ **Docker 工具支持**
- ✅ **Git 增強功能**

享受高效的開發體驗！🚀
