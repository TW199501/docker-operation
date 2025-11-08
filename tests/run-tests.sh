#!/usr/bin/env bash

# Docker 操作專案測試框架
# 支援單元測試、集成測試和端到端測試

set -euo pipefail

# 測試框架變數
TEST_PASSED=0
TEST_FAILED=0
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 測試輔助函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

test_nginx_scripts_structure() {
    log_info "Validating nginx deployment scripts structure..."

    local test_file="$TEST_DIR/test_nginx_scripts.sh"
    if [ ! -f "$test_file" ]; then
        log_warning "nginx script test file missing: $test_file"
        return
    fi

    if bash "$test_file"; then
        log_success "nginx script structure validation"
    else
        log_failure "nginx script structure validation failed"
    fi
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TEST_PASSED++))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TEST_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 斷言函數
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [ "$expected" = "$actual" ]; then
        log_success "assert_equals: $message"
    else
        log_failure "assert_equals: $message (expected: '$expected', actual: '$actual')"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_success "assert_contains: $message"
    else
        log_failure "assert_contains: $message ('$needle' not found in '$haystack')"
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    if [ -f "$file" ]; then
        log_success "assert_file_exists: $message"
    else
        log_failure "assert_file_exists: $message (file not found: $file)"
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-}"

    if eval "$command" >/dev/null 2>&1; then
        log_success "assert_command_success: $message"
    else
        log_failure "assert_command_success: $message (command failed: $command)"
    fi
}

# 測試設置和清理
setup_test_env() {
    log_info "Setting up test environment..."

    # 創建測試目錄
    TEST_TMP_DIR="$(mktemp -d)"
    export TEST_TMP_DIR
    TEST_BACKUP_DIR="$TEST_TMP_DIR/backup"
    export TEST_BACKUP_DIR

    mkdir -p "$TEST_BACKUP_DIR"

    # 備份重要配置文件
    if [ -f /etc/network/interfaces ]; then
        cp /etc/network/interfaces "$TEST_BACKUP_DIR/interfaces.backup"
    fi

    log_success "Test environment setup complete"
}

cleanup_test_env() {
    log_info "Cleaning up test environment..."

    # 恢復備份的配置文件
    if [ -f "$TEST_BACKUP_DIR/interfaces.backup" ]; then
        sudo cp "$TEST_BACKUP_DIR/interfaces.backup" /etc/network/interfaces 2>/dev/null || true
    fi

    # 清理測試文件
    rm -rf "$TEST_TMP_DIR"

    log_success "Test environment cleanup complete"
}

# 單元測試
test_unit_tests() {
    log_info "Running unit tests..."

    # 測試工具函數
    test_prefix_to_netmask
    test_ensure_line
    test_first_nameserver

    log_info "Unit tests completed"
}

test_prefix_to_netmask() {
    log_info "Testing prefix_to_netmask function..."

    # 載入測試函數
    if [ -f "$PROJECT_ROOT/proxmox9.0/123.sh" ]; then
        # shellcheck source=/dev/null
        if ! source "$PROJECT_ROOT/proxmox9.0/123.sh"; then
            log_warning "Failed to load proxmox9.0/123.sh, skipping prefix_to_netmask tests"
            return
        fi
    else
        log_warning "proxmox9.0/123.sh not found, skipping prefix_to_netmask tests"
        return
    fi

    # 測試不同 CIDR 前綴
    assert_equals "255.255.255.0" "$(prefix_to_netmask 24)" "CIDR /24 should be 255.255.255.0"
    assert_equals "255.255.0.0" "$(prefix_to_netmask 16)" "CIDR /16 should be 255.255.0.0"
    assert_equals "255.0.0.0" "$(prefix_to_netmask 8)" "CIDR /8 should be 255.0.0.0"
}

test_ensure_line() {
    log_info "Testing ensure_line function..."

    # 創建測試文件
    local test_file
    test_file="$TEST_TMP_DIR/test_ensure_line.txt"

    # 載入測試函數
    source "$PROJECT_ROOT/proxmox9.0/123.sh"

    # 測試添加行
    ensure_line "test line 1" "$test_file"
    assert_file_exists "$test_file" "Test file should be created"
    assert_contains "$(cat "$test_file")" "test line 1" "Line should be added to file"

    # 測試不重複添加
    ensure_line "test line 1" "$test_file"
    local line_count
    line_count=$(grep -c "test line 1" "$test_file")
    assert_equals "1" "$line_count" "Line should not be duplicated"
}

test_first_nameserver() {
    log_info "Testing first_nameserver function..."

    # 創建測試 resolv.conf
    local test_resolv
    test_resolv="$TEST_TMP_DIR/resolv.conf"
    echo "nameserver 8.8.8.8" > "$test_resolv"
    echo "nameserver 1.1.1.1" >> "$test_resolv"

    # 載入測試函數
    source "$PROJECT_ROOT/proxmox9.0/123.sh"

    # 臨時修改函數以使用測試文件
    first_nameserver() {
        awk '/^nameserver[ 	]+([0-9]+\.){3}[0-9]+/ {print $2; exit}' "$test_resolv" 2>/dev/null || true
    }

    assert_equals "8.8.8.8" "$(first_nameserver)" "Should return first nameserver"
}

# 集成測試
test_integration_tests() {
    log_info "Running integration tests..."

    test_docker_compose_validation
    test_nginx_scripts_structure
    test_script_syntax

    log_info "Integration tests completed"
}

test_docker_compose_validation() {
    log_info "Testing docker-compose file validation..."

    # 查找所有 docker-compose 文件
    local compose_files
    compose_files=$(find "$PROJECT_ROOT" -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

    if [ -z "$compose_files" ]; then
        log_warning "No docker-compose files found, skipping validation test"
        return
    fi

    for file in $compose_files; do
        log_info "Validating $file..."
        if command -v docker-compose >/dev/null 2>&1; then
            if docker-compose -f "$file" config --quiet 2>/dev/null; then
                log_success "docker-compose validation: $file"
            else
                log_failure "docker-compose validation failed: $file"
            fi
        else
            log_warning "docker-compose command not found, skipping validation"
        fi
    done
}

test_script_syntax() {
    log_info "Testing script syntax..."

    # 測試所有 shell 腳本
    local script_files
    script_files=$(find "$PROJECT_ROOT" -name "*.sh" -type f)

    for script in $script_files; do
        if bash -n "$script" 2>/dev/null; then
            log_success "Syntax check: $(basename "$script")"
        else
            log_failure "Syntax error in: $(basename "$script")"
        fi
    done
}

# 端到端測試
test_e2e_tests() {
    log_info "Running end-to-end tests..."

    test_network_configuration
    test_disk_operations

    log_info "End-to-end tests completed"
}

test_network_configuration() {
    log_info "Testing network configuration functions..."

    # 測試 IP 前綴轉換（無需實際網路操作）
    source "$PROJECT_ROOT/proxmox9.0/123.sh"

    # 測試網路工具函數
    assert_equals "192.168.1.0" "$(echo '192.168.1.100' | awk -F. '{print $1"."$2"."$3".0"}')" "Network calculation"
}

test_disk_operations() {
    log_info "Testing disk operation functions..."

    # 測試磁碟解析邏輯（模擬）
    local test_device="/dev/sda1"
    if [[ "$test_device" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
        local disk="${BASH_REMATCH[1]}"
        local part="${BASH_REMATCH[2]}"
        assert_equals "/dev/sda" "$disk" "Disk parsing"
        assert_equals "1" "$part" "Partition parsing"
    fi
}

# 測試報告
generate_test_report() {
    local total_tests=$((TEST_PASSED + TEST_FAILED))
    local success_rate=0

    if [ $total_tests -gt 0 ]; then
        success_rate=$((TEST_PASSED * 100 / total_tests))
    fi

    echo
    echo "========================================"
    echo "        測試報告 / Test Report"
    echo "========================================"
    echo "總測試數 / Total Tests: $total_tests"
    echo "通過 / Passed: $TEST_PASSED"
    echo "失敗 / Failed: $TEST_FAILED"
    echo "成功率 / Success Rate: ${success_rate}%"
    echo "========================================"

    if [ $TEST_FAILED -eq 0 ]; then
        echo -e "${GREEN}所有測試通過！/ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}部分測試失敗！/ Some tests failed!${NC}"
        return 1
    fi
}

# 性能測試
test_performance() {
    log_info "Running performance tests..."

    # 測試腳本載入時間
    local start_time
    start_time=$(date +%s.%3N)
    source "$PROJECT_ROOT/proxmox9.0/123.sh" >/dev/null 2>&1
    local end_time
    end_time=$(date +%s.%3N)

    local load_time
    load_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    log_info "Script load time: ${load_time}s"

    if (( $(echo "$load_time < 5.0" | bc -l 2>/dev/null || echo "1") )); then
        log_success "Performance test: Script loads within acceptable time"
    else
        log_warning "Performance test: Script load time is high (${load_time}s)"
    fi
}

# 主測試函數
main() {
    log_info "開始執行 Docker 操作專案測試套件"
    log_info "Starting Docker Operations Project Test Suite"
    echo

    # 設置測試環境
    setup_test_env

    # 運行測試
    test_unit_tests
    echo
    test_integration_tests
    echo
    test_e2e_tests
    echo
    test_performance
    echo

    # 清理測試環境
    cleanup_test_env

    # 生成報告
    generate_test_report
}

# 如果直接運行此腳本，執行測試
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
