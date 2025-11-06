#!/usr/bin/env bash

# 單元測試 - 測試 prefix_to_netmask 函數
# Unit Tests for prefix_to_netmask function

source "../proxmox9.0/123.sh"

echo "Testing prefix_to_netmask function..."

# 測試案例
test_cases=(
    "24:255.255.255.0"
    "16:255.255.0.0"
    "8:255.0.0.0"
    "32:255.255.255.255"
    "1:128.0.0.0"
    "2:192.0.0.0"
)

passed=0
failed=0

for test_case in "${test_cases[@]}"; do
    prefix="${test_case%%:*}"
    expected="${test_case##*:}"

    result=$(prefix_to_netmask "$prefix")

    if [ "$result" = "$expected" ]; then
        echo "✓ CIDR /$prefix -> $expected"
        ((passed++))
    else
        echo "✗ CIDR /$prefix -> expected: $expected, got: $result"
        ((failed++))
    fi
done

echo
echo "Results: $passed passed, $failed failed"

# 邊界測試
echo
echo "Boundary tests..."

# 測試無效輸入
result=$(prefix_to_netmask "abc" 2>/dev/null)
if [ "$result" = "255.255.255.0" ]; then
    echo "✓ Invalid input defaults to /24"
    ((passed++))
else
    echo "✗ Invalid input should default to /24"
    ((failed++))
fi

# 測試超出範圍
result=$(prefix_to_netmask "33")
if [ "$result" = "255.255.255.0" ]; then
    echo "✓ Out of range input defaults to /24"
    ((passed++))
else
    echo "✗ Out of range input should default to /24"
    ((failed++))
fi

echo
echo "Final Results: $passed passed, $failed failed"

if [ $failed -eq 0 ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed!"
    exit 1
fi
