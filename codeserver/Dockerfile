FROM codercom/code-server:latest

# 安裝基本依賴
USER root
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    fontconfig \
    curl \
    git \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 設置環境變量
ENV SHELL=/bin/bash \
    PATH="/home/coder/.local/bin:${PATH}" \
    # 避免 npm 安裝時的權限問題
    NPM_CONFIG_PREFIX=/home/coder/.npm-global \
    PATH="/home/coder/.npm-global/bin:${PATH}" \
    # 跳過擴展安裝確認
    VSCODE_CLI=1 \
    EXTENSIONS_GALLERY='{"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery"}' \
    # 自動信任所有擴展
    VSCODE_CLI_EXTRA_ARGS="--install-extension"

# 創建必要的目錄並設置權限
RUN mkdir -p /home/coder/.local/share/code-server/extensions \
    && chown -R coder:coder /home/coder

# 切換到 coder 用戶
USER coder

# 安裝 Node.js 和 npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - \
    && sudo apt-get install -y nodejs \
    && node --version \
    && npm --version

# 複製擴展列表文件
COPY extensions.txt /tmp/extensions.txt

# 安裝擴展
RUN cat /tmp/extensions.txt | grep -v '^#' | grep -v '^$' | while read extension; do \
    echo "Installing $extension..." && \
    code-server --install-extension "$extension" || echo "Failed to install $extension"; \
    done && \
    rm /tmp/extensions.txt

# 切換回 root 用戶進行系統設置
USER root

# 下載並安裝 Maple 主題
RUN mkdir -p /tmp/maple-theme \
    && wget -O /tmp/maple-theme.zip https://github.com/subframe7536/vscode-theme-maple/archive/refs/tags/v0.7.6.zip \
    && unzip /tmp/maple-theme.zip -d /tmp/maple-theme \
    && mkdir -p /home/coder/.local/share/code-server/extensions/maple-theme \
    && cp -r /tmp/maple-theme/vscode-theme-maple-0.7.6/* /home/coder/.local/share/code-server/extensions/maple-theme/ \
    && chown -R coder:coder /home/coder/.local/share/code-server/extensions/maple-theme \
    && rm -rf /tmp/maple-theme /tmp/maple-theme.zip

# 下載並安裝字體
RUN mkdir -p /usr/share/fonts/maple && \
    wget -O /tmp/maple.zip https://github.com/subframe7536/maple-font/releases/download/v7.4/MapleMono-NF-CN-unhinted.zip && \
    unzip /tmp/maple.zip -d /usr/share/fonts/maple && \
    rm /tmp/maple.zip && \
    fc-cache -fv

# 建立預設設定資料夾並設置權限
RUN mkdir -p /home/coder/.local/share/code-server/User && \
    chown -R coder:coder /home/coder/.local

# 切換回 coder 用戶
USER coder

# 寫入繁體中文與基本偏好設定
RUN mkdir -p /home/coder/.local/share/code-server/User && \
    echo '\
{\n\
  "locale": "zh-hant",\n\
  "workbench.colorTheme": "Default Dark+",\n\
  "editor.fontFamily": "Maple Mono NF CN, Fira Code, monospace",\n\
  "editor.fontLigatures": true,\n\
  "editor.fontSize": 14,\n\
  "editor.tabSize": 2,\n\
  "editor.wordWrap": "on",\n\
  "files.autoSave": "afterDelay",\n\
  "terminal.integrated.fontFamily": "Maple Mono NF CN, monospace",\n\
  "terminal.integrated.fontSize": 13\n\
}' > /home/coder/.local/share/code-server/User/settings.json

# 確保權限正確
RUN chown -R coder:coder /home/coder/.local

# 預設開啟資料夾，可依需求掛載覆蓋 /home/coder/project
WORKDIR /home/coder/project
