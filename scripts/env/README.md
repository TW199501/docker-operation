# scripts/env/

`.env.example` → `.env` bootstrap 工具鏈。

## 用法

詳見 [`docs/conventions/env-naming.md`](../../docs/conventions/env-naming.md) §4。

快速範例:

```bash
# 對單一 stack 產 .env
./scripts/env/bootstrap-env.sh DB/POSTGRES

# 預覽不寫
./scripts/env/bootstrap-env.sh --dry-run DB/POSTGRES

# 強制覆寫(會 backup)
./scripts/env/bootstrap-env.sh --force DB/POSTGRES

# 非互動模式(CI 用)
./scripts/env/bootstrap-env.sh --non-interactive DB/POSTGRES

# 全 repo 跑
./scripts/env/bootstrap-env.sh --all
```

## 檔案

| 檔案 | 用途 |
|---|---|
| `bootstrap-env.sh` | 主入口 |
| `check-env-syntax.sh` | CI 用,擋字面密碼與白名單外命令 |
| `check-env-coverage.sh` | CI 用(advisory),掃 compose.yml `${VAR}` 是否在 example 有定義 |
| `lib/whitelist.sh` | 命令白名單實作 |
| `lib/parse.sh` | `.env.example` parser |
