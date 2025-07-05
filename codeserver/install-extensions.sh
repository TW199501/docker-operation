#!/bin/bash

# 創建臨時目錄
mkdir -p /app/tmp/extensions

# 安裝擴展函數
install_vsix() {
    local extension_id=$1
    local vsix_url=$2
    
    echo "下載擴展: $extension_id"
    wget -O "/tmp/extensions/$extension_id.vsix" "$vsix_url"
    
    if [ $? -eq 0 ]; then
        echo "安裝擴展: $extension_id"
        code-server --install-extension "/tmp/extensions/$extension_id.vsix"
        
        if [ $? -eq 0 ]; then
            echo "成功安裝: $extension_id"
        else
            echo "警告: 無法安裝擴展: $extension_id"
        fi
    else
        echo "警告: 無法下載擴展: $extension_id"
    fi
}

# 安裝所有擴展
install_vsix "ms-python.python" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-python/vsextensions/python/latest/vspackage"
install_vsix "esbenp.prettier-vscode" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/esbenp/vsextensions/prettier-vscode/latest/vspackage"
install_vsix "dbaeumer.vscode-eslint" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/dbaeumer/vsextensions/vscode-eslint/latest/vspackage"
install_vsix "eamodio.gitlens" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/eamodio/vsextensions/gitlens/latest/vspackage"
install_vsix "ms-azuretools.vscode-docker" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-azuretools/vsextensions/vscode-docker/latest/vspackage"
install_vsix "shd101wyy.markdown-preview-enhanced" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/shd101wyy/vsextensions/markdown-preview-enhanced/latest/vspackage"
install_vsix "humao.rest-client" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/humao/vsextensions/rest-client/latest/vspackage"
install_vsix "MS-CEINTL.vscode-language-pack-zh-hant" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/MS-CEINTL/vsextensions/vscode-language-pack-zh-hant/latest/vspackage"
install_vsix "ms-toolsai.jupyter" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-toolsai/vsextensions/jupyter/latest/vspackage"
install_vsix "lightyen.vscode-fanhuaji" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/lightyen/vsextensions/vscode-fanhuaji/latest/vspackage"
install_vsix "codeium.codeium" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/codeium/vsextensions/codeium/latest/vspackage"

# 清理臨時文件
rm -rf /tmp/extensions

echo "所有擴展安裝完成"

