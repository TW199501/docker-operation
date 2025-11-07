# Windows 下的 nginx

[已知問題](#已知問題)
[以後可能的發展](#以後可能的發展)

Nginx 的 Windows 版本使用了本地的 Win32 API（而不是 Cygwin 模擬層）。目前僅使用 `select()` 和 `poll()` (1.15.9) 連接處理方式。由於此版本和其他存在已知的問題的 Nginx Windows 版本都被認為是 beta 版本，因此您不應該期望它具有高性能和可擴展性。現在，它提供了與 Unix 版本的 nginx 幾乎相同的功能，除了 XSLT 過濾器、圖像過濾器、GeoIP 模組和嵌入式 Perl 語言。

<!-- more -->

要安裝 nginx 的 Windows 版本，請 [下載](http://nginx.org/en/download.html) 最新的主線發行版（1.17.2），因為 nginx 的主線分支包含了所有已知的補丁。之後解壓文件到 `nginx-1.17.2` 目錄下，然後運行 `nginx`。以下是 `C槽` 的根目錄：

```bash
cd c:\
unzip nginx-1.17.2.zip
cd nginx-1.17.2
start nginx
```

運行 `tasklist` 命令行工具查看 nginx 進程：

```bash
C:\nginx-1.17.2>tasklist /fi "imagename eq nginx.exe"

Image Name           PID Session Name     Session#    Mem Usage
=============== ======== ============== ========== ============
nginx.exe            652 Console                 0      2 780 K
nginx.exe           1332 Console                 0      3 112 K
```
其中有一個是主進程（master），另一個是工作進程（worker）。如果 nginx 未能啟動，請在錯誤日誌 `logs\error.log` 中尋找原因。如果日誌檔案尚未創建，可以在 Windows 事件日誌中尋找原因。如果顯示的頁面為錯誤頁面，而不是預期結果，也可以在 `logs\error.log` 中尋找原因。

Nginx 的 Windows 版本使用運行目錄作為設定檔中的相對路徑前綴。在上面的例子中，前綴是 `C:\nginx-1.17.2\`。在設定檔中的路徑必須使類 Unix 風格的正斜槓：

```nginx
access_log   logs/site.log;
root         C:/web/html;
```
Nginx 的 Windows 版本作為標準的控制台應用程式（而不是服務）運行，可以使用以下命令進行管理：

- `nginx -s stop` 快速退出
- `nginx -s quit` 正常退出
- `nginx -s reload` 重新載入設定檔，使用新的配置啟動工作進程，正常關閉舊的工作進程
- `nginx -s reopen` 重新打開日誌檔案

## 已知問題
- 雖然可以啟動多個工作進程，但實際上只有一個工作進程做完全部的工作
- 不支持 UDP 代理功能

## 以後可能的發展
- 作為服務運行
- 使用 I/O 完成埠作為連接處理方式
- 在單個工作進程中使用多個工作執行緒

## 原文件

[http://nginx.org/en/docs/windows.html](http://nginx.org/en/docs/windows.html)
