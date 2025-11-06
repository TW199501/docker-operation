#!/usr/bin/env bash

# 集成測試 - 測試 docker-compose 文件驗證
# Integration Test for docker-compose file validation

echo "Testing docker-compose file validation..."

# 查找項目根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
skipped=0

# 檢查是否有 docker-compose 命令
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "⚠️  docker-compose command not found, installing..."

    # 嘗試安裝 docker-compose
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y docker-compose
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y docker-compose
    else
        echo "❌ Cannot install docker-compose, skipping tests"
        exit 0
    fi
fi

# 查找所有 docker-compose 文件
compose_files=$(find "$PROJECT_ROOT" -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

if [ -z "$compose_files" ]; then
    echo "⚠️  No docker-compose files found in project"
    echo "✓ Integration test skipped (no files to test)"
    exit 0
fi

echo "Found docker-compose files:"
echo "$compose_files" | tr ' ' '\n'
echo

# 測試每個文件
for file in $compose_files; do
    echo "Testing: $(basename "$file")"

    # 檢查文件是否存在
    if [ ! -f "$file" ]; then
        echo "❌ File does not exist: $file"
        ((failed++))
        continue
    fi

    # 嘗試驗證配置
    if docker-compose -f "$file" config --quiet 2>/dev/null; then
        echo "✅ Valid configuration: $(basename "$file")"
        ((passed++))
    else
        echo "❌ Invalid configuration: $(basename "$file")"
        # 顯示具體錯誤
        docker-compose -f "$file" config 2>&1 | head -10
        ((failed++))
    fi

    echo
done

# 測試 docker-compose 版本兼容性
echo "Testing docker-compose version compatibility..."
compose_version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -n "$compose_version" ]; then
    echo "✅ Docker Compose version: $compose_version"

    # 比較版本 (簡單檢查)
    major_version=$(echo "$compose_version" | cut -d. -f1)
    if [ "$major_version" -ge 1 ]; then
        echo "✅ Compatible version (>= 1.0.0)"
        ((passed++))
    else
        echo "❌ Incompatible version (< 1.0.0)"
        ((failed++))
    fi
else
    echo "❌ Could not determine docker-compose version"
    ((failed++))
fi

echo
echo "Integration Test Results:"
echo "✅ Passed: $passed"
echo "❌ Failed: $failed"
echo "⚠️  Skipped: $skipped"

total=$((passed + failed))
if [ $total -gt 0 ]; then
    success_rate=$((passed * 100 / total))
    echo "📊 Success Rate: ${success_rate}%"
fi

if [ $failed -eq 0 ]; then
    echo "🎉 All integration tests passed!"
    exit 0
else
    echo "❌ Some integration tests failed!"
    exit 1
fi
