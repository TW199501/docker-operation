#!/usr/bin/env bash

# 端到端測試 - 測試腳本功能完整性
# End-to-End Test for script functionality

echo "Running End-to-End Tests for Docker Operation Scripts..."
echo "======================================================="

# 設置變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
skipped=0

# 測試函數
test_script_loads() {
    local script_name="$1"
    local script_path="$PROJECT_ROOT/$2"

    echo "Testing $script_name script loading..."

    if [ ! -f "$script_path" ]; then
        echo "❌ Script not found: $script_path"
        ((failed++))
        return 1
    fi

    # 測試腳本語法
    if bash -n "$script_path" 2>/dev/null; then
        echo "✅ Syntax check passed for $script_name"
        ((passed++))
    else
        echo "❌ Syntax error in $script_name"
        ((failed++))
        return 1
    fi

    # 測試腳本可執行性
    if [ -x "$script_path" ]; then
        echo "✅ Script is executable: $script_name"
        ((passed++))
    else
        echo "⚠️  Script not executable: $script_name (this may be OK)"
        ((skipped++))
    fi

    # 測試函數定義
    local function_count=$(grep -c "^function " "$script_path" 2>/dev/null || echo "0")
    if [ "$function_count" -gt 0 ]; then
        echo "✅ Found $function_count functions in $script_name"
        ((passed++))
    else
        echo "⚠️  No functions found in $script_name"
        ((skipped++))
    fi
}

# 測試主要腳本
test_main_scripts() {
    echo
    echo "Testing Main Scripts..."
    echo "----------------------"

    # 測試 proxmox9.0 目錄下的腳本
    test_script_loads "debian13-tool.sh" "proxmox9.0/debian13-tool.sh"
    test_script_loads "123.sh" "proxmox9.0/123.sh"

    # 測試根目錄腳本
    test_script_loads "docker-vm.sh" "docker-vm.sh"
    test_script_loads "docker-vm-backup.sh" "docker-vm-backup.sh"
}

# 測試配置文件
test_configuration_files() {
    echo
    echo "Testing Configuration Files..."
    echo "-----------------------------"

    local config_files=(
        ".hadolint.yaml:Hadolint configuration"
        ".dockerignore:Docker ignore file"
        ".github/workflows/docker-ci.yml:Docker CI workflow"
        ".github/workflows/script-test.yml:Script test workflow"
    )

    for config_entry in "${config_files[@]}"; do
        local file_path="${config_entry%%:*}"
        local description="${config_entry##*:}"

        if [ -f "$PROJECT_ROOT/$file_path" ]; then
            echo "✅ Found $description: $file_path"
            ((passed++))
        else
            echo "❌ Missing $description: $file_path"
            ((failed++))
        fi
    done
}

# 測試依賴項
test_dependencies() {
    echo
    echo "Testing Dependencies..."
    echo "----------------------"

    # 測試 shellcheck
    if command -v shellcheck >/dev/null 2>&1; then
        echo "✅ shellcheck available"
        ((passed++))
    else
        echo "⚠️  shellcheck not available (install for better testing)"
        ((skipped++))
    fi

    # 測試 docker
    if command -v docker >/dev/null 2>&1; then
        echo "✅ docker available"
        ((passed++))
    else
        echo "⚠️  docker not available (some tests may fail)"
        ((skipped++))
    fi

    # 測試 docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        echo "✅ docker-compose available"
        ((passed++))
    else
        echo "⚠️  docker-compose not available (some tests may fail)"
        ((skipped++))
    fi
}

# 測試 CI/CD 配置
test_ci_cd_setup() {
    echo
    echo "Testing CI/CD Setup..."
    echo "---------------------"

    # 檢查 GitHub Actions 工作流程
    local workflows=(
        ".github/workflows/docker-ci.yml"
        ".github/workflows/docker-publish.yml"
        ".github/workflows/script-test.yml"
    )

    for workflow in "${workflows[@]}"; do
        if [ -f "$PROJECT_ROOT/$workflow" ]; then
            echo "✅ Found workflow: $(basename "$workflow")"
            ((passed++))
        else
            echo "❌ Missing workflow: $(basename "$workflow")"
            ((failed++))
        fi
    done

    # 檢查 Dependabot 配置
    if [ -f "$PROJECT_ROOT/.github/dependabot.yml" ]; then
        echo "✅ Dependabot configuration found"
        ((passed++))
    else
        echo "❌ Dependabot configuration missing"
        ((failed++))
    fi
}

# 測試文檔
test_documentation() {
    echo
    echo "Testing Documentation..."
    echo "-----------------------"

    local docs=(
        "README.md:Main README"
        "DOCKER-CI-CD-GUIDE.md:Docker CI/CD Guide"
    )

    for doc_entry in "${docs[@]}"; do
        local doc_file="${doc_entry%%:*}"
        local description="${doc_entry##*:}"

        if [ -f "$PROJECT_ROOT/$doc_file" ]; then
            echo "✅ Found $description: $doc_file"
            ((passed++))

            # 檢查文檔大小（確保不是空的）
            local size=$(stat -f%z "$PROJECT_ROOT/$doc_file" 2>/dev/null || stat -c%s "$PROJECT_ROOT/$doc_file" 2>/dev/null || echo "0")
            if [ "$size" -gt 100 ]; then
                echo "   📄 Document has content (${size} bytes)"
            else
                echo "   ⚠️  Document seems empty (${size} bytes)"
            fi
        else
            echo "❌ Missing $description: $doc_file"
            ((failed++))
        fi
    done
}

# 運行所有測試
run_all_tests() {
    test_main_scripts
    test_configuration_files
    test_dependencies
    test_ci_cd_setup
    test_documentation
}

# 生成測試報告
generate_report() {
    echo
    echo "======================================================="
    echo "           端到端測試報告 / E2E Test Report"
    echo "======================================================="
    echo "測試腳本 / Test Scripts    : $passed ✅"
    echo "失敗項目 / Failed Items    : $failed ❌"
    echo "跳過項目 / Skipped Items   : $skipped ⚠️"

    local total=$((passed + failed + skipped))
    if [ $total -gt 0 ]; then
        local success_rate=$((passed * 100 / total))
        echo "總項目 / Total Items       : $total"
        echo "成功率 / Success Rate      : ${success_rate}%"
    fi

    echo "======================================================="

    if [ $failed -eq 0 ]; then
        echo "🎉 所有端到端測試通過！"
        echo "🎉 All end-to-end tests passed!"
        return 0
    else
        echo "❌ 部分測試失敗，請檢查上述錯誤。"
        echo "❌ Some tests failed, please check the errors above."
        return 1
    fi
}

# 主函數
main() {
    echo "開始端到端測試 / Starting End-to-End Tests"
    echo

    run_all_tests
    generate_report
}

# 執行測試
main "$@"
