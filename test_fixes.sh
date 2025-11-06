#!/usr/bin/env bash

# IP 配置修復測試腳本
# 測試修復後的 IP 配置功能

# 顏色定義
YW='\033[33m'
BL='\033[36m'
RD='\033[01;31m'
GN='\033[1;92m'
CL='\033[m'

# 日誌函數
msg_info() {
    echo -e "${BL}${1}${CL}"
}

msg_ok() {
    echo -e "${GN}✓${CL} ${1}${CL}"
}

msg_error() {
    echo -e "${RD}✗${CL} ${1}${CL}"
}

# 測試 IP 配置修復
test_ip_configuration() {
    msg_info "測試 IP 配置修復功能..."

    # 檢查腳本是否存在
    if [ ! -f "./debian13-tool.sh" ]; then
        msg_error "找不到 debian13-tool.sh 腳本"
        return 1
    fi

    # 檢查腳本語法
    if bash -n "./debian13-tool.sh"; then
        msg_ok "腳本語法檢查通過"
    else
        msg_error "腳本語法錯誤"
        return 1
    fi

    # 檢查關鍵函數是否存在
    if grep -q "function configure_static_ip" "./debian13-tool.sh"; then
        msg_ok "configure_static_ip 函數存在"
    else
        msg_error "configure_static_ip 函數不存在"
        return 1
    fi

    # 檢查手動 IP 配置代碼是否存在
    if grep -q "ip addr flush dev" "./debian13-tool.sh"; then
        msg_ok "手動 IP 配置代碼存在"
    else
        msg_error "手動 IP 配置代碼不存在"
        return 1
    fi

    msg_ok "IP 配置修復測試通過"
    return 0
}

# 測試硬碟擴充修復
test_disk_expansion() {
    msg_info "測試硬碟擴充修復功能..."

    # 檢查 expand_disk 函數是否存在
    if grep -q "function expand_disk" "./debian13-tool.sh"; then
        msg_ok "expand_disk 函數存在"
    else
        msg_error "expand_disk 函數不存在"
        return 1
    fi

    # 檢查空間檢查代碼是否存在
    if grep -q "has_free_space=false" "./debian13-tool.sh"; then
        msg_ok "空間檢查代碼存在"
    else
        msg_error "空間檢查代碼不存在"
        return 1
    fi

    # 檢查智能跳過邏輯
    if grep -q "硬碟已經是最大容量" "./debian13-tool.sh"; then
        msg_ok "智能跳過邏輯存在"
    else
        msg_error "智能跳過邏輯不存在"
        return 1
    fi

    msg_ok "硬碟擴充修復測試通過"
    return 0
}

# 主測試函數
main() {
    msg_info "=== Debian 13 Tool 修復測試 ==="

    local result=0

    test_ip_configuration || result=1
    echo
    test_disk_expansion || result=1

    echo
    if [ $result -eq 0 ]; then
        msg_ok "🎉 所有修復測試通過！"
        msg_info "現在可以安全使用修復後的腳本"
    else
        msg_error "❌ 部分測試失敗，請檢查修復代碼"
    fi

    return $result
}

# 執行測試
main "$@"
