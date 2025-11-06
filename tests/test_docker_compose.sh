#!/usr/bin/env bash

# 集成測試 - 測試 docker-compose 文件驗證
# Integration Test for docker-compose file validation

echo "Testing docker-compose file validation..."

# 設置腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
skipped=0

# 檢查是否有 docker-compose 命令
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "⚠️  docker-compose command not found"

    # 檢查是否在 WSL 環境中
    if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSLENV" ]; then
        echo "   💡 您似乎在 WSL 環境中運行"
        echo "   💡 請確保 Docker Desktop 正在運行並啟用了 WSL 集成"
        echo "   📖 參考: https://docs.docker.com/desktop/windows/wsl/"
    fi

    echo "   🔄 跳過 docker-compose 測試，但仍檢查 YAML 語法..."
    skipped=$((skipped + 1))

    # 嘗試使用 Python 檢查 YAML 語法
    if command -v python3 >/dev/null 2>&1; then
        echo "   🐍 使用 Python 檢查 YAML 語法..."

        # 查找所有 docker-compose 文件
        compose_files=$(find "$PROJECT_ROOT" -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

        if [ -z "$compose_files" ]; then
            echo "   ⚠️  沒有找到 docker-compose 文件"
            skipped=$((skipped + 1))
        else
            for file in $compose_files; do
                echo "   檢查: $(basename "$file")"
                if python3 -c "
import yaml
import sys
try:
    with open('$file', 'r', encoding='utf-8') as f:
        yaml.safe_load(f)
    print('   ✅ YAML 語法正確')
    sys.exit(0)
except Exception as e:
    print(f'   ❌ YAML 語法錯誤: {e}')
    sys.exit(1)
" 2>/dev/null; then
                    passed=$((passed + 1))
                else
                    failed=$((failed + 1))
                fi
            done
        fi
    else
        echo "   ⚠️  Python3 不可用，跳過 YAML 語法檢查"
        skipped=$((skipped + 1))
    fi

else
    # 正常的 docker-compose 測試
    echo "✅ docker-compose available, running full tests..."

    # 查找所有 docker-compose 文件
    compose_files=$(find "$PROJECT_ROOT" -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

    if [ -z "$compose_files" ]; then
        echo "⚠️  No docker-compose files found in project"
        echo "✅ Integration test skipped (no files to test)"
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
fi

echo
echo "Integration Test Results:"
echo "✅ Passed: $passed"
echo "❌ Failed: $failed"
echo "⚠️  Skipped: $skipped"

total=$((passed + failed + skipped))
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
