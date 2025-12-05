#!/bin/sh
# 產生滿足 SQL Server 複雜性要求的強 MSSQL_SA_PASSWORD。
# 用法:./generate-sa-password。sh [長度]

set -eu

if [ "${1:-}" != "" ]; then
  LENGTH="$1"
else
  LENGTH="24"
fi

case "$LENGTH" in
  ''|*[!0-9]* )
    printf "Invalid length: %s\n" "$LENGTH" >&2
    exit 1
    ;;
  * )
    if [ "$LENGTH" -lt 12 ]; then
      printf "Length must be at least 12 characters for SA password.\n" >&2
      exit 1
    fi
    ;;
esac

PYTHON_CMD="python3"
if ! command -v "$PYTHON_CMD" >/dev/null 2>&1; then
  printf "python3 is required but not found on PATH.\n" >&2
  exit 1
fi

SPECIAL_CHARS="!@#$%^&*-_=+"

PASSWORD=$($PYTHON_CMD <<PY
import secrets
import string
import sys

length = int(sys.argv[1])
special = sys.argv[2]

alphabet = string.ascii_letters + string.digits + special

while True:
    pwd = ''.join(secrets.choice(alphabet) for _ in range(length))
    if (any(c.islower() for c in pwd)
            and any(c.isupper() for c in pwd)
            and any(c.isdigit() for c in pwd)
            and any(c in special for c in pwd)):
        print(pwd)
        break
PY
"$LENGTH" "$SPECIAL_CHARS")

printf "Generated MSSQL_SA_PASSWORD: %s\n" "$PASSWORD"
printf "Remember to update your .env or compose file accordingly.\n"
