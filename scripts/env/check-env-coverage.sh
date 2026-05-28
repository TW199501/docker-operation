#!/usr/bin/env bash
# =============================================================================
# CI 用(advisory):對每個有 compose.yml 的目錄,確認 ${VAR} 都在 .env.example 有定義
# 規範:docs/conventions/env-naming.md
# =============================================================================
set -uo pipefail   # 不設 -e:advisory 不擋

violations=0

while IFS= read -r compose; do
  dir=$(dirname "$compose")
  example="$dir/.env.example"

  # 從 compose 抓所有 ${VAR}(含含 fallback 的也算,只比對 VAR 名)
  used_vars=$(grep -oE '\$\{[A-Z_][A-Z0-9_]*[:?-]*[^}]*\}' "$compose" 2>/dev/null \
              | sed -E 's/^\$\{([A-Z_][A-Z0-9_]*).*/\1/' \
              | sort -u)

  [ -z "$used_vars" ] && continue

  if [ ! -f "$example" ]; then
    while IFS= read -r var; do
      [ -z "$var" ] && continue
      echo "::warning file=$compose::使用 \${$var} 但本目錄無 .env.example"
      violations=$((violations + 1))
    done <<< "$used_vars"
    continue
  fi

  # 對每個 var 確認 .env.example 內有定義
  while IFS= read -r var; do
    [ -z "$var" ] && continue
    if ! grep -qE "^${var}=" "$example"; then
      echo "::warning file=$example::compose.yml 用了 \${$var} 但本檔未定義"
      violations=$((violations + 1))
    fi
  done <<< "$used_vars"
done < <(find . -name "docker-compose*.yml" -not -path "./.git/*" -not -path "./docs/*")

if [ $violations -gt 0 ]; then
  echo ""
  echo "::warning::共 $violations 個覆蓋率缺口(advisory,不擋 PR)"
fi
echo "✅ 覆蓋率掃描完成"
