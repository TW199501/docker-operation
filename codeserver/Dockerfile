# 使用官方 code-server 鏡像
FROM codercom/code-server:latest

# 設置 USER 為 root 進行安裝
USER root

# 安裝基本依賴
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
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# 安裝 Node.js 和 npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version

# 創建必要的目錄
RUN mkdir -p /app \
    && mkdir -p /home/coder/.local/share/code-server/extensions

# 複製所有文件到 /app
COPY . /app/

# 設置工作目錄
WORKDIR /app

# 設置腳本權限
RUN chmod +x /app/start-code-server.sh /app/install-extensions.sh \
    && chown -R coder:coder /app

# 建立預設設定資料夾並設置權限
RUN mkdir -p /home/coder/.local/share/code-server/User \
    && chown -R coder:coder /home/coder/.local

# 設置環境變量
ENV SHELL=/bin/bash \
    PATH="/home/coder/.local/bin:${PATH}" \
    NPM_CONFIG_PREFIX=/home/coder/.npm-global \
    PATH="/home/coder/.npm-global/bin:${PATH}" \
    VSCODE_CLI=1 \
    EXTENSIONS_GALLERY='{"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery"}' \
    VSCODE_CLI_EXTRA_ARGS="--install-extension"

# 安裝擴展
RUN /app/install-extensions.sh

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

# 設置啟動命令
CMD ["/app/start-code-server.sh"]
