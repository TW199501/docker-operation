# 測試演示腳本 - 展示如何使用測試框架
# Test Demo Script - Shows how to use the testing framework

echo "=== Docker 操作專案測試框架演示 ==="
echo "=== Docker Operations Project Test Framework Demo ==="
echo

# 設置腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "項目根目錄: $PROJECT_ROOT"
echo "測試目錄: $SCRIPT_DIR"
echo

echo "📋 可用的測試文件 / Available test files:"
ls -la "$SCRIPT_DIR"/*.sh
echo

echo "🚀 快速測試示例 / Quick test examples:"
echo

echo "1. 運行所有測試 / Run all tests:"
echo "   cd tests && bash run_all_tests.sh"
echo

echo "2. 只運行單元測試 / Run only unit tests:"
echo "   bash run_all_tests.sh unit"
echo

echo "3. 詳細模式運行集成測試 / Run integration tests in verbose mode:"
echo "   bash run_all_tests.sh -v integration"
echo

echo "4. 安靜模式運行端到端測試 / Run E2E tests in quiet mode:"
echo "   bash run_all_tests.sh -q e2e"
echo

echo "5. 保存測試報告 / Save test report:"
echo "   bash run_all_tests.sh -o test-results.txt all"
echo

echo "📊 測試覆蓋範圍 / Test coverage:"
echo "✅ 單元測試 - 測試個別函數 / Unit tests - individual functions"
echo "✅ 集成測試 - 測試組件交互 / Integration tests - component interactions"
echo "✅ 端到端測試 - 測試完整工作流程 / E2E tests - complete workflows"
echo "✅ 語法檢查 - Shell 腳本語法 / Syntax checks - shell script syntax"
echo "✅ 配置驗證 - Docker Compose 文件 / Config validation - docker-compose files"
echo "✅ CI/CD 檢查 - GitHub Actions 配置 / CI/CD checks - GitHub Actions setup"
echo

echo "🛠️  編寫新測試 / Writing new tests:"
echo "
創建新測試文件時，請遵循以下結構：

#!/usr/bin/env bash
# 測試描述 / Test description

echo 'Running [測試名稱]...'
passed=0
failed=0

# 測試函數 / Test functions
test_example() {
    # 測試邏輯 / Test logic
    if [ '\$expected' = '\$actual' ]; then
        echo '✅ Test passed'
        ((passed++))
    else
        echo '❌ Test failed'
        ((failed++))
    fi
}

# 運行測試 / Run tests
test_example

# 結果報告 / Results
echo \"Results: \$passed passed, \$failed failed\"
exit \$((failed > 0 ? 1 : 0))
"

echo
echo "📚 詳細文檔 / Detailed documentation:"
echo "請查看 tests/README.md 獲取完整說明"
echo "Please check tests/README.md for complete documentation"
echo

echo "🎯 下一步 / Next steps:"
echo "1. 運行 'bash run_all_tests.sh' 開始測試"
echo "2. 查看測試結果和報告"
echo "3. 根據需要添加或修改測試"
echo "4. 將測試集成到 CI/CD 流程中"
echo

echo "✨ 享受測試！ / Happy testing!"
