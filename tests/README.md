# Docker 操作專案測試套件

## 概述

這是一個為 Docker 操作專案設計的完整測試框架，包含單元測試、集成測試、端到端測試和性能測試。

## 測試結構

```text
tests/
├── run_all_tests.sh          # 主測試運行器
├── run-tests.sh              # 完整測試框架 (舊版)
├── test-config.ini           # 測試配置
├── test_prefix_to_netmask.sh # 單元測試示例
├── test_docker_compose.sh    # 集成測試示例
├── test_e2e.sh              # 端到端測試
└── python/
    └── test_nginx_scripts.py # VS Code 測試面板用的 Python 測試包裝
```

## 快速開始

### 運行所有測試

```bash
cd tests
bash run_all_tests.sh
```

### 運行特定測試類型

```bash
# 單元測試
bash run_all_tests.sh unit

# 集成測試
bash run_all_tests.sh integration

# 端到端測試
bash run_all_tests.sh e2e

# 詳細模式
bash run_all_tests.sh -v all
```

## 測試類型說明

### 1. 單元測試 (Unit Tests)

- **目的**: 測試個別函數和組件的正確性
- **示例**: `test_prefix_to_netmask.sh`
- **測試內容**:
  - 網路工具函數
  - 字符串處理函數
  - 數學計算函數

### 2. 集成測試 (Integration Tests)

- **目的**: 測試組件間的交互
- **示例**: `test_docker_compose.sh`
- **測試內容**:
  - Docker Compose 文件驗證
  - 腳本依賴項檢查
  - 配置文件一致性

### 3. 端到端測試 (E2E Tests)

- **目的**: 測試完整的工作流程
- **示例**: `test_e2e.sh`
- **測試內容**:
  - 腳本載入和語法檢查
  - CI/CD 配置驗證
  - 依賴項可用性
  - 文檔完整性

### 4. 性能測試 (Performance Tests)

- **目的**: 測試系統性能指標
- **狀態**: 計劃中

### 5. 安全測試 (Security Tests)

- **目的**: 檢查安全漏洞和配置
- **狀態**: 計劃中

### 6. VS Code 測試面板整合

- **目的**: 讓 VS Code Testing UI 可直接執行 Bash 測試
- **實作**: 透過 `tests/python/test_nginx_scripts.py` 使用 `unittest` 呼叫 `run_all_tests.sh`
- **使用方式**:
  1. 安裝 VS Code Python 擴充，並在命令面板執行 `Python: Configure Tests`
  2. 選擇 `unittest` → 專案根目錄 → `tests/python`
  3. Testing 面板會出現 `TestNginxScripts`，可個別執行 `test_all` / `test_unit` / `test_integration`
  4. 可在 `.vscode/settings.json` 自訂 `python.testing.unittestArgs` 以控制測試目錄

## 命令行選項

```bash
Usage: run_all_tests.sh [選項] [測試類型]

選項 / Options:
    -h, --help          顯示幫助信息
    -v, --verbose       詳細輸出模式
    -q, --quiet         安靜模式 (只顯示錯誤)
    -c, --config FILE   指定配置文件 (默認: test-config.ini)
    -o, --output FILE   輸出報告到文件

測試類型 / Test Types:
    all                 運行所有測試 (默認)
    unit                單元測試
    integration         集成測試
    e2e                 端到端測試
    performance         性能測試
    security            安全測試
```

## 測試配置

編輯 `test-config.ini` 文件來自定義測試行為：

```ini
[tests]
unit_tests = true
integration_tests = true
e2e_tests = true

[environment]
use_real_system = false
create_backups = true
test_timeout = 300
```

## 寫測試案例

### 基本測試結構

```bash
#!/usr/bin/env bash

# 測試描述
echo "Testing [功能名稱]..."

passed=0
failed=0

# 測試案例
test_case_1() {
    # 準備測試數據
    # 執行測試
    # 斷言結果
    if [ "$expected" = "$actual" ]; then
        echo "✓ Test case 1 passed"
        ((passed++))
    else
        echo "✗ Test case 1 failed"
        ((failed++))
    fi
}

# 運行測試
test_case_1

# 報告結果
echo "Results: $passed passed, $failed failed"
exit $((failed > 0 ? 1 : 0))
```

### 斷言函數

測試框架提供了常用的斷言函數：

```bash
# 相等斷言
assert_equals "expected" "actual" "message"

# 包含斷言
assert_contains "haystack" "needle" "message"

# 文件存在斷言
assert_file_exists "/path/to/file" "message"

# 命令成功斷言
assert_command_success "command" "message"
```

## CI/CD 集成

測試自動集成到 GitHub Actions：

```yaml
- name: Run Tests
  run: |
    cd tests
    bash run_all_tests.sh all
```

## 測試最佳實踐

### 1. 測試隔離

- 每個測試應獨立運行
- 不依賴外部狀態
- 清理測試產物

### 2. 測試命名

- 使用描述性名稱
- 遵循 `test_*.sh` 命名約定
- 包含測試目的

### 3. 錯誤處理

- 使用適當的退出代碼
- 提供有意義的錯誤消息
- 不隱藏重要錯誤

### 4. 性能考慮

- 測試應快速運行
- 避免不必要的延遲
- 並行運行獨立測試

## 故障排除

### 常見問題

1. **權限錯誤**

   ```bash
   chmod +x tests/*.sh
   ```

2. **依賴項缺失**

   ```bash
   sudo apt-get install -y shellcheck docker-compose
   ```

3. **測試超時**
   - 檢查網路連接
   - 減少測試範圍
   - 增加超時設置

### 調試測試

```bash
# 詳細模式
bash run_all_tests.sh -v unit

# 只運行失敗的測試
bash run_all_tests.sh --only-failed

# 保存測試輸出
bash run_all_tests.sh -o debug.log all
```

## 擴展測試框架

### 添加新測試類型

1. 在 `run_all_tests.sh` 中添加新的測試函數
2. 更新命令行參數處理
3. 添加對應的測試文件

### 自定義斷言

在 `run-tests.sh` 中添加新的斷言函數：

```bash
assert_network_reachable() {
    local host="$1"
    local message="${2:-}"

    if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
        log_success "assert_network_reachable: $message"
    else
        log_failure "assert_network_reachable: $message (cannot reach $host)"
    fi
}
```

## 貢獻指南

1. 遵循現有測試結構
2. 添加適當的文檔
3. 確保測試通過
4. 更新此 README

## 聯繫與支持

如有測試相關問題，請檢查：

1. GitHub Issues
2. CI/CD 日誌
3. 測試輸出信息
