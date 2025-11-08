#!/usr/bin/env bash

# Integration test: verify nginx deployment scripts contain expected directives

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0

pass() {
    echo "✅ $1"
    ((passed++))
}

fail() {
    echo "❌ $1"
    ((failed++))
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -qE "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description (pattern not found: $pattern)"
    fi
}

assert_file_exists() {
    local file="$1"
    local description="$2"

    if [ -f "$file" ]; then
        pass "$description"
    else
        fail "$description (missing file: $file)"
    fi
}

# Test targets
BUILD_SCRIPT="$PROJECT_ROOT/nginx/10-build-nginx.sh"
NETWORK_SCRIPT="$PROJECT_ROOT/nginx/a87-unified-nginx-network.sh"
GEOIP_SCRIPT="$PROJECT_ROOT/nginx/update_geoip2_cf_ip.sh"
UFW_SCRIPT="$PROJECT_ROOT/nginx/ufw-cf-allow.sh"
DEFAULT_SITE="$PROJECT_ROOT/nginx/sites-available/default.conf"

# 10-build-nginx.sh expectations
assert_file_contains "$BUILD_SCRIPT" 'sudo install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled' "build script creates sites-available/sites-enabled directories"
assert_file_contains "$BUILD_SCRIPT" 'include /etc/nginx/sites-enabled/\*;' "build script includes sites-enabled directive"
assert_file_exists "$DEFAULT_SITE" "default site configuration exists"

# a87-unified-nginx-network.sh expectations
# shellcheck disable=SC2016
assert_file_contains "$NETWORK_SCRIPT" 'SCRIPT_DIR="\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)" && pwd\)"' "network script defines SCRIPT_DIR"
# shellcheck disable=SC2016
assert_file_contains "$NETWORK_SCRIPT" 'install -m 0755 "\$SCRIPT_DIR/ufw-cf-allow.sh" /usr/local/sbin/ufw-cf-allow.sh' "network script deploys ufw-cf-allow.sh"
# shellcheck disable=SC2016
assert_file_contains "$NETWORK_SCRIPT" 'install -m 0755 "\$SCRIPT_DIR/update_cf_ip.sh" /usr/local/sbin/update_cf_ip.sh' "network script deploys update_cf_ip.sh"
# shellcheck disable=SC2016
assert_file_contains "$NETWORK_SCRIPT" 'install -m 0755 "\$SCRIPT_DIR/update_geoip2_cf_ip.sh" /usr/local/sbin/update_geoip2_cf_ip.sh' "network script deploys update_geoip2_cf_ip.sh"

# update_geoip2_cf_ip.sh expectations
assert_file_contains "$GEOIP_SCRIPT" 'SYSTEMD_ON_CALENDAR' "geoip script exposes SYSTEMD_ON_CALENDAR variable"
assert_file_contains "$GEOIP_SCRIPT" 'systemctl enable --now update-geoip2\.timer' "geoip script enables systemd timer"
assert_file_contains "$GEOIP_SCRIPT" '/etc/cron.d/update_geoip2' "geoip script falls back to cron.d"

# ufw-cf-allow.sh expectations
assert_file_contains "$UFW_SCRIPT" 'CF_PORTS_OVERRIDE' "ufw script supports CF_PORTS_OVERRIDE override"

# Summary

total=$((passed + failed))
echo
echo "Integration Test Results (nginx scripts):"
echo "✅ Passed: $passed"
echo "❌ Failed: $failed"
if [ $total -gt 0 ]; then
    success_rate=$((passed * 100 / total))
    echo "📊 Success Rate: ${success_rate}%"
fi

if [ $failed -eq 0 ]; then
    echo "🎉 nginx script integration tests passed!"
    exit 0
else
    echo "❌ nginx script integration tests detected issues."
    exit 1
fi
