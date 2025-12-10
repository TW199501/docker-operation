#!/bin/bash

# 簡單的 PVE VM 防火牆管理工具
# 在任一 PVE 節點執行即可，需要安裝 jq

set -e

#####################################################################
# 基本檢查
#####################################################################

check_requirements() {
    if ! command -v pvesh >/dev/null 2>&1; then
        echo "❌ 找不到 pvesh，這腳本需要在 PVE 節點上執行。"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ 找不到 jq，請先安裝："
        echo "    apt update && apt install jq -y"
        exit 1
    fi
}

#####################################################################
# VM 列表與選擇
#####################################################################

# 取得所有 VM 清單 (整個 cluster)
get_vm_list() {
    pvesh get /cluster/resources --type vm --output-format json \
      | jq -r '.[] | "\(.vmid)\t\(.node)\t\(.name)"'
}

# 選擇 VM
select_vm() {
    echo "目前叢集 VM 清單："
    echo -e "VMID\tNODE\tNAME"
    echo "--------------------------------"
    get_vm_list
    echo
    read -p "請輸入要操作的 VMID: " VMID

    NODE=$(pvesh get /cluster/resources --type vm --output-format json \
           | jq -r ".[] | select(.vmid == ${VMID}) | .node")

    if [ -z "$NODE" ] || [ "$NODE" = "null" ]; then
        echo "❌ 找不到 VMID=${VMID}，請確認後重試。"
        exit 1
    fi

    echo "✅ 將操作 VM ${VMID} (節點: ${NODE})"
}

#####################################################################
# VM 防火牆啟用 / 停用 & 規則管理
#####################################################################

# 啟用 VM 防火牆
enable_vm_fw() {
    echo "👉 啟用 VM ${VMID} 的防火牆..."
    pvesh set /nodes/${NODE}/qemu/${VMID}/firewall/options -enable 1
}

# 關閉 VM 防火牆
disable_vm_fw() {
    echo "👉 關閉 VM ${VMID} 的防火牆..."
    pvesh set /nodes/${NODE}/qemu/${VMID}/firewall/options -enable 0
}

# 清空 VM 規則
clear_vm_rules() {
    echo "👉 清空 VM ${VMID} 既有的防火牆規則..."
    local rules
    rules=$(pvesh get /nodes/${NODE}/qemu/${VMID}/firewall/rules --output-format json)

    echo "$rules" | jq -r '.[].pos' 2>/dev/null | sort -nr | while read -r POS; do
        [ -n "$POS" ] && pvesh delete /nodes/${NODE}/qemu/${VMID}/firewall/rules/${POS} || true
    done
    echo "✔ 規則已清空。"
}

#####################################################################
# NIC firewall=1 檢查 / 修正
#####################################################################

# 檢查並修正 VM 網卡是否啟用 firewall=1
check_and_fix_vm_nic_firewall() {
    echo
    echo "=== 檢查 VM ${VMID} 的網卡 firewall 設定 ==="

    local cfg
    cfg=$(pvesh get /nodes/${NODE}/qemu/${VMID}/config --output-format json)

    # 把所有 net* 項目抓出來：net0 / net1 / ...
    mapfile -t nics < <(
        echo "$cfg" \
        | jq -r 'to_entries[]
                 | select(.key|test("^net[0-9]+$"))
                 | "\(.key)=\(.value)"'
    )

    if [ "${#nics[@]}" -eq 0 ]; then
        echo "⚠ 此 VM 沒有找到任何 net* 介面（可能尚未設定網卡），略過檢查。"
        return 0
    fi

    local missing=()

    echo "目前網卡狀態："
    for line in "${nics[@]}"; do
        local key val
        key=${line%%=*}
        val=${line#*=}

        if [[ "$val" == *"firewall=1"* ]]; then
            echo " - ${key}: ✅ 已啟用 firewall=1"
        else
            echo " - ${key}: ⚠ 尚未啟用 firewall"
            missing+=("$key")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "✔ 所有網卡都已啟用 firewall=1，無需變更。"
        return 0
    fi

    echo
    echo "⚠ 下列網卡尚未啟用 firewall=1： ${missing[*]}"
    read -p "是否要自動在這些網卡加上 firewall=1 ? (y/N): " ans

    case "$ans" in
        y|Y)
            for nic in "${missing[@]}"; do
                local oldval newval
                oldval=$(echo "$cfg" | jq -r --arg k "$nic" '.[$k]')
                newval="${oldval},firewall=1"

                echo "   -> 設定 ${nic}: ${newval}"

                if [ "$NODE" = "$(hostname)" ]; then
                    qm set "$VMID" -"$nic" "$newval" >/dev/null 2>&1 || true
                else
                    ssh root@"$NODE" "qm set $VMID -$nic '$newval'" >/dev/null 2>&1 || true
                fi
            done
            echo "✅ 網卡 firewall=1 參數已更新。"
            ;;
        *)
            echo "❎ 保持原樣，不修改網卡設定。"
            ;;
    esac
}

#####################################################################
# Input Policy 檢查 / 修正
#####################################################################

# 檢查 VM Input Policy，並強制將 VM 層級改成 ACCEPT（避免被鎖死）
check_and_fix_vm_input_policy() {
    echo
    echo "=== 檢查/修正 VM ${VMID} 的 Input Policy ==="

    local options
    options=$(pvesh get /nodes/${NODE}/qemu/${VMID}/firewall/options --output-format json)

    # 這裡只是看 VM 這一層有沒有設定 policy_in（可能為 null / 未設定）
    local raw
    raw=$(echo "$options" | jq -r '.policy_in // "<未在 VM 上設定，可能沿用上層>"')

    echo "目前 VM 層級的 policy_in = ${raw}"
    echo "為避免被防火牆鎖死，將 VM 的 Input Policy 強制設為 ACCEPT（只影響這台 VM，不動資料中心/節點）..."

    pvesh set /nodes/${NODE}/qemu/${VMID}/firewall/options -policy_in ACCEPT

    echo "✅ 已將 VM ${VMID} 的 Input Policy 設為 ACCEPT"
}

#####################################################################
# Profiles
#####################################################################

# Web Server Profile
apply_profile_web() {
    echo "套用 Web Server Profile 到 VM ${VMID} ..."
    enable_vm_fw
    clear_vm_rules

    # 允許 SSH 從內網 (192.168.0.0/16 可依你環境調整)
    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action ACCEPT -enable 1 -macro SSH -source 192.168.0.0/16

    # 允許 HTTP / HTTPS
    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action ACCEPT -enable 1 -proto tcp -dport 80
    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action ACCEPT -enable 1 -proto tcp -dport 443

    # 其他全部 DROP
    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action DROP -enable 1

    echo "✅ Web Profile 套用完成。"
}

# IP 白名單 Profile
apply_profile_ip_whitelist() {
    read -p "請輸入允許的來源 IP 或網段 (例如 192.168.25.0/24 或 1.2.3.4): " ALLOW_IP

    enable_vm_fw
    clear_vm_rules

    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action ACCEPT -enable 1 -source "${ALLOW_IP}"

    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules \
      -type in -action DROP -enable 1

    echo "✅ IP 白名單 Profile 套用完成。"
}

#####################################################################
# 自訂規則（有選單）
#####################################################################

# 自訂一條規則（方向 / 動作用選單）
add_custom_rule() {
    echo "自訂規則："

    echo "方向："
    echo "  1) in  (預設，進來 VM 的流量)"
    echo "  2) out (VM 出去的流量)"
    read -p "請選擇方向 (1-2，預設 1): " DIR_CH
    case "$DIR_CH" in
        2) DIR="out" ;;
        *) DIR="in" ;;
    esac

    echo "動作："
    echo "  1) ACCEPT (允許)"
    echo "  2) DROP   (直接丟棄，不回應)"
    echo "  3) REJECT (拒絕並回應對方)"
    read -p "請選擇動作 (1-3，預設 1): " ACT_CH
    case "$ACT_CH" in
        2) ACT="DROP" ;;
        3) ACT="REJECT" ;;
        *) ACT="ACCEPT" ;;
    esac

    read -p "通訊協定 (tcp/udp/icmp，可空白代表 ALL): " PROTO
    read -p "目的 Port (如 22 或 80:443，可空白): " PORT
    read -p "來源 IP (例: 192.168.25.0/24，可空白): " SRC

    ARGS="-type ${DIR} -action ${ACT} -enable 1"

    [ -n "$PROTO" ] && ARGS="${ARGS} -proto ${PROTO}"
    [ -n "$PORT" ]  && ARGS="${ARGS} -dport ${PORT}"
    [ -n "$SRC" ]   && ARGS="${ARGS} -source ${SRC}"

    echo "套用規則: ${ARGS}"
    # shellcheck disable=SC2086
    pvesh create /nodes/${NODE}/qemu/${VMID}/firewall/rules ${ARGS}
}

#####################################################################
# 顯示規則
#####################################################################

show_rules() {
    echo
    echo "VM ${VMID} 目前規則："
    pvesh get /nodes/${NODE}/qemu/${VMID}/firewall/rules --output-format json \
      | jq -r '.[] | "\(.pos)\t\(.type)\t\(.action)\t\(.proto // "-")\tport=\(.dport // "-")\tsrc=\(.source // "-")"'
}

#####################################################################
# 主選單
#####################################################################

main_menu() {
    while true; do
        echo
        echo "==== PVE VM 防火牆管理 ===="
        echo "操作 VM: ${VMID} (節點: ${NODE})"
        echo "1) 啟用防火牆"
        echo "2) 關閉防火牆"
        echo "3) 套用 Web Server Profile (22+80+443，其餘 DROP)"
        echo "4) 套用 IP 白名單 Profile (只允許某 IP/網段，其餘 DROP)"
        echo "5) 自訂新增一條規則"
        echo "6) 顯示目前規則"
        echo "7) 清空所有規則"
        echo "0) 離開"
        read -p "請選擇: " CH

        case "$CH" in
            1) enable_vm_fw ;;
            2) disable_vm_fw ;;
            3) apply_profile_web ;;
            4) apply_profile_ip_whitelist ;;
            5) add_custom_rule ;;
            6) show_rules ;;
            7) clear_vm_rules ;;
            0) exit 0 ;;
            *) echo "❌ 選項錯誤，請重試。" ;;
        esac
    done
}

#####################################################################
# 主流程
#####################################################################

check_requirements
select_vm
check_and_fix_vm_nic_firewall
check_and_fix_vm_input_policy
main_menu
