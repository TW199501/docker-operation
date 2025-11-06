#!/usr/bin/env bash

# Docker 操作專案測試運行器
# Docker Operations Project Test Runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 顯示幫助信息
show_help() {
    cat << EOF
Docker 操作專案測試運行器 / Docker Operations Project Test Runner

用法 / Usage:
    $0 [選項] [測試類型]

選項 / Options:
    -h, --help          顯示此幫助信息 / Show this help
    -v, --verbose       詳細輸出 / Verbose output
    -q, --quiet         安靜模式 / Quiet mode
    -c, --config FILE   指定配置文件 / Specify config file
    -o, --output FILE   輸出報告到文件 / Output report to file

測試類型 / Test Types:
    all                 運行所有測試 / Run all tests (default)
    unit                單元測試 / Unit tests
    integration         集成測試 / Integration tests
    e2e                 端到端測試 / End-to-end tests
    performance         性能測試 / Performance tests
    security            安全測試 / Security tests

範例 / Examples:
    $0                      # 運行所有測試
    $0 unit                 # 只運行單元測試
    $0 -v integration       # 詳細模式運行集成測試
    $0 -o results.txt all   # 運行所有測試並保存報告

EOF
}

# 解析命令行參數
VERBOSE=false
QUIET=false
CONFIG_FILE="$SCRIPT_DIR/test-config.ini"
OUTPUT_FILE=""
TEST_TYPE="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        unit|integration|e2e|performance|security|all)
            TEST_TYPE="$1"
            shift
            ;;
        *)
            echo -e "${RED}錯誤: 未知選項 '$1'${NC}" >&2
            echo "使用 '$0 --help' 查看幫助" >&2
            exit 1
            ;;
    esac
done

# 日誌函數
log_info() {
    if ! $QUIET; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if ! $QUIET; then
        echo -e "${GREEN}[PASS]${NC} $1"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    if ! $QUIET; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

# 檢查依賴項
check_dependencies() {
    log_info "檢查測試依賴項 / Checking test dependencies..."

    local missing_deps=()

    # 檢查 bash
    if ! command -v bash >/dev/null 2>&1; then
        missing_deps+=("bash")
    fi

    # 檢查必要的命令
    local required_cmds=("grep" "awk" "sed" "find")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少必要的依賴項 / Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi

    log_success "所有依賴項都可用 / All dependencies available"
    return 0
}

# 運行單元測試
run_unit_tests() {
    log_info "運行單元測試 / Running unit tests..."

    local test_files=(
        "$SCRIPT_DIR/test_prefix_to_netmask.sh"
    )

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            log_info "執行測試: $(basename "$test_file")"

            if bash "$test_file"; then
                ((passed++))
            else
                ((failed++))
            fi
        else
            log_warning "測試文件不存在: $(basename "$test_file")"
        fi
    done

    log_info "單元測試完成: $passed 通過, $failed 失敗"
    return $((failed > 0 ? 1 : 0))
}

# 運行集成測試
run_integration_tests() {
    log_info "運行集成測試 / Running integration tests..."

    local test_files=(
        "$SCRIPT_DIR/test_docker_compose.sh"
    )

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            log_info "執行測試: $(basename "$test_file")"

            if bash "$test_file"; then
                ((passed++))
            else
                ((failed++))
            fi
        else
            log_warning "測試文件不存在: $(basename "$test_file")"
        fi
    done

    log_info "集成測試完成: $passed 通過, $failed 失敗"
    return $((failed > 0 ? 1 : 0))
}

# 運行端到端測試
run_e2e_tests() {
    log_info "運行端到端測試 / Running end-to-end tests..."

    local test_file="$SCRIPT_DIR/test_e2e.sh"

    if [ -f "$test_file" ]; then
        if bash "$test_file"; then
            log_success "端到端測試通過"
            return 0
        else
            log_error "端到端測試失敗"
            return 1
        fi
    else
        log_warning "端到端測試文件不存在"
        return 1
    fi
}

# 運行性能測試
run_performance_tests() {
    log_info "運行性能測試 / Running performance tests..."

    log_info "性能測試功能尚未實現 / Performance test not implemented yet"
    return 0
}

# 運行安全測試
run_security_tests() {
    log_info "運行安全測試 / Running security tests..."

    log_info "安全測試功能尚未實現 / Security test not implemented yet"
    return 0
}

# 檢查是否在 WSL 環境中
is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSLENV" ] || grep -q "microsoft" /proc/version 2>/dev/null
}

# 檢查 Docker 是否可用
is_docker_available() {
    command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1
}

# WSL 環境警告
wsl_warning() {
    if is_wsl && ! is_docker_available; then
        log_warning "⚠️  檢測到 WSL 環境，但 Docker 不可用"
        log_warning "💡 建議啟動 Docker Desktop 並啟用 WSL 集成"
        log_warning "📖 參考: https://docs.docker.com/desktop/windows/wsl/"
        echo
    fi
}

# 主函數
main() {
    log_info "Docker 操作專案測試套件 / Docker Operations Project Test Suite"
    log_info "======================================================="

    # 檢查依賴項
    if ! check_dependencies; then
        exit 1
    fi

    # WSL 環境檢查和警告
    wsl_warning

    local overall_result=0

    # 根據測試類型運行相應測試
    case "$TEST_TYPE" in
        unit)
            run_unit_tests || overall_result=1
            ;;
        integration)
            run_integration_tests || overall_result=1
            ;;
        e2e)
            run_e2e_tests || overall_result=1
            ;;
        performance)
            run_performance_tests || overall_result=1
            ;;
        security)
            run_security_tests || overall_result=1
            ;;
        all)
            run_unit_tests || overall_result=1
            run_integration_tests || overall_result=1
            run_e2e_tests || overall_result=1
            run_performance_tests || overall_result=1
            run_security_tests || overall_result=1
            ;;
        *)
            log_error "未知的測試類型: $TEST_TYPE"
            exit 1
            ;;
    esac

    log_info "======================================================="

    if [ $overall_result -eq 0 ]; then
        log_success "🎉 所有測試完成！ / All tests completed successfully!"
    else
        log_error "❌ 部分測試失敗 / Some tests failed"
    fi

    return $overall_result
}

# 執行主函數
main "$@"
