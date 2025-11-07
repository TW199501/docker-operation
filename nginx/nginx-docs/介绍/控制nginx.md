# 控制 nginx

- [控制 nginx](#控制-nginx)
  - [配置變更](#配置變更)
  - [日誌輪轉](#日誌輪轉)
  - [升級可執行文件](#升級可執行文件)
  - [原文件](#原文件)

可以用信號控制 nginx。默認情況下，主進程（Master）的 pid 寫在 `/use/local/nginx/logs/nginx.pid` 文件中。這個文件的位置可以在配置時更改或者在 nginx.conf 文件中使用 `pid` 指令更改。Master 進程支持以下信號：

信號 | 作用
:---|:---
TERM, INT | 快速關閉
QUIT| 正常退出
HUP	| 當改變設定檔時，將有一段過渡時間段（僅 FreeBSD 和 Linux），新啟動的 Worker 進程將應用新的配置，舊的 Worker 進程將被平滑退出
USR1| 重新打開日誌檔案
USR2| 升級可執行文件
WINCH| 正常關閉 Worker 進程

Worker 進程也是可以用信號控制的，儘管這不是必須的。支持以下信號：

信號 | 作用
:---|:---
TERM, INT | 快速關閉
QUIT | 正常關閉
USR1 | 重新打開日誌檔案
WINCH | 除錯異常終止（需要開啟 [debug_points](http://nginx.org/en/docs/ngx_core_module.html#debug_points)）

## 配置變更

為了讓 nginx 重新讀取設定檔，應將 `HUP` 信號發送給 Master 進程。Master 進程首先會檢查設定檔的語法有效性，之後嘗試應用新的配置，即打開日誌檔案和新的 socket。如果失敗了，它會回滾更改並繼續使用舊的配置。如果成功，它將啟動新的 Worker 進程並向舊的 Worker 進程發送消息請求它們正常關閉。舊的 Worker 進程關閉監聽 socket 並繼續為舊的用戶端服務，當所有舊的用戶端被處理完成，舊的 Worker 進程將被關閉。

我們來舉例說明一下。 假設 nginx 是在 FreeBSD 4.x 命令行上運行的

```bash
ps axw -o pid,ppid,user,%cpu,vsz,wchan,command | egrep '(nginx|PID)'
```

得到以下輸出結果：

```bash
  PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1148 pause  nginx: master process /usr/local/nginx/sbin/nginx
33127 33126 nobody   0.0  1380 kqread nginx: worker process (nginx)
33128 33126 nobody   0.0  1364 kqread nginx: worker process (nginx)
33129 33126 nobody   0.0  1364 kqread nginx: worker process (nginx)
```

如果把 `HUP` 信號發送到 master 進程，輸出的結果將會是：

```bash
 PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1164 pause  nginx: master process /usr/local/nginx/sbin/nginx
33129 33126 nobody   0.0  1380 kqread nginx: worker process is shutting down (nginx)
33134 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
33135 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
33136 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
```

其中一個 PID 為 33129 的 worker 進程仍然在繼續工作，過一段時間之後它退出了：

```bash
PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1164 pause  nginx: master process /usr/local/nginx/sbin/nginx
33134 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
33135 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
33136 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
```

## 日誌輪轉

為了做日誌輪轉，首先需要重命名。之後應該發送 `USR1` 信號給 master 進程。Master 進程將會重新打開當前所有的日誌檔案，並將其分配給一個正在運行未經授權的用戶為所有者的 worker 進程。成功重新打開之後 Master 進程將會關閉所有打開的文件並且發送消息給 worker 進程要求它們重新打開文件。Worker 進程重新打開新文件和立即關閉舊文件。因此，舊的文件幾乎可以立即用於後期處理，例如壓縮。

## 升級可執行文件

為了升級伺服器可執行文件，首先應該將新的可執行文件替換舊的可執行文件。之後發送 `USR2` 信號到 master 進程。Master 進程首先將以進程 ID 文件重命名為以 `.oldbin` 為後綴的新文件，例如 `/usr/local/nginx/logs/nginx.pid.oldbin`。之後啟動新的二進制文件和依次期待能夠新的 worker 進程：

```bash
  PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1164 pause  nginx: master process /usr/local/nginx/sbin/nginx
33134 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
33135 33126 nobody   0.0  1380 kqread nginx: worker process (nginx)
33136 33126 nobody   0.0  1368 kqread nginx: worker process (nginx)
36264 33126 root     0.0  1148 pause  nginx: master process /usr/local/nginx/sbin/nginx
36265 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36266 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36267 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
```

之後所有的 worker 進程（舊的和新的）繼續接收請求，如果 `WINCH` 信號被發送給了第一個 master 進程，它將向其 worker 進程發送消息要求它們正常關閉，之後它們開始退出：

```
  PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1164 pause  nginx: master process /usr/local/nginx/sbin/nginx
33135 33126 nobody   0.0  1380 kqread nginx: worker process is shutting down (nginx)
36264 33126 root     0.0  1148 pause  nginx: master process /usr/local/nginx/sbin/nginx
36265 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36266 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36267 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
```

過一段時間，僅有新的 worker 進程處理請求：

```bash
  PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
33126     1 root     0.0  1164 pause  nginx: master process /usr/local/nginx/sbin/nginx
36264 33126 root     0.0  1148 pause  nginx: master process /usr/local/nginx/sbin/nginx
36265 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36266 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36267 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
```

需要注意的是舊的 master 進程不會關閉它的監聽 socket，並且如果需要的話，可以管理它來啟動 worker 進程。如果出於某些原因不能接受新的可執行文件工作方式，可以執行以下操作之一：

- 發送 `HUP` 信號給舊的 master 進程，舊的 master 進程將會啟動不會重新讀取設定檔的 worker 進程。之後，透過將 `QUIT` 信號發送到新的主進程就可以正常關閉所有的新進程。
- 發送 `TERM` 信號到新的 master 進程，它將會發送一個消息給 worker 進程要求它們立即關閉，並且它們立即退出（如果由於某些原因新的進程沒有退出，應該發送 `KILL` 信號讓它們強制退出）。當新的 master 進程退出時，舊 master 將會自動啟動新的 worker 進程。

新的 master 進程退出之後，舊的 master 進程會從以進程 ID 命名的文件中忽略掉 `.oldbin` 後綴的文件。

如果升級成功，應該發送 `QUIT` 信號給舊的 master 進程，僅僅新的進程駐留：

```bash
  PID  PPID USER    %CPU   VSZ WCHAN  COMMAND
36264     1 root     0.0  1148 pause  nginx: master process /usr/local/nginx/sbin/nginx
36265 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36266 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
36267 36264 nobody   0.0  1364 kqread nginx: worker process (nginx)
```

## 原文件

- [http://nginx.org/en/docs/control.html](http://nginx.org/en/docs/control.html)
