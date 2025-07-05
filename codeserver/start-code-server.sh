#!/bin/bash

# 確保擴展目錄存在
EXTENSIONS_DIR="/home/coder/.local/share/code-server/extensions"
mkdir -p "$EXTENSIONS_DIR"

# 啟用所有擴展
for ext in $(ls "$EXTENSIONS_DIR" 2>/dev/null); do
    echo "啟用擴展: $ext"
    code-server --install-extension "$ext" --force
    code-server --list-extensions | grep -q "$ext" && echo "已啟用: $ext" || echo "啟用失敗: $ext"
done

if [ -d "$EXTENSIONS_DIR/maple-theme" ]; then
    echo "啟用 Maple 主題"
    code-server --install-extension "maple-theme" --force
fi

# 啟用語言包
if [ -d "$EXTENSIONS_DIR/vscode-language-pack-zh-hant" ]; then
    echo "啟用繁體中文語言包"
    code-server --install-extension "vscode-language-pack-zh-hant" --force
fi

# 啟動 code-server
exec code-server "$@"
