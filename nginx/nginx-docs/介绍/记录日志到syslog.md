# 記錄日誌到 syslog

[error_log](http://nginx.org/en/docs/ngx_core_module.html#error_log) 和 [access_log](http://nginx.org/en/docs/http/ngx_http_log_module.html#access_log) 指令支持把日誌記錄到 syslog。以下配置參數將使 nginx 日誌記錄到 syslog：

```yaml
server=address
```
> 定義 syslog 伺服器的地址，可以將該地址指定為附帶可選埠的域名或者 IP，或者指定為 “unix:” 前綴之後跟著一個特定的 UNIX 域套接字路徑。如果沒有指定埠，則使用 UDP 的 514 埠。如果域名解析為多個 IP 地址，則使用第一個地址。

<!--more -->

```yaml
facility=string
```

> 設置 syslog 的消息 facility（設備），[RFC3164](https://tools.ietf.org/html/rfc3164#section-4.1.1) 中定義，facility可以是 `kern`，`user`，`mail`，`daemon`，`auth`，`intern`，`lpr`，`news`，`uucp`，`clock`，`authpriv`，`ftp`，`ntp`，`audit`，`alert`，`cron`，`local0`，`local7` 中的一個，預設是 `local7`。

```yaml
severity=string
```

> 設置 [access_log](http://nginx.org/en/docs/http/ngx_http_log_module.html#access_log) 的消息嚴重程度，在 [RFC3164](https://tools.ietf.org/html/rfc3164#section-4.1.1) 中定義。可能值與 [error_log](http://nginx.org/en/docs/ngx_core_module.html#error_log) 指令的第二個參數（ `level`，級別）相同，預設是 `info`。錯誤消息的嚴重程度由 nginx 確定，因此在 `error_log` 指令中將忽略該參數。

```yaml
tag=string
```
> 設置 syslog 消息標籤。預設是 `nginx`。

```yaml
nohostname
```
> 禁止將 `hostname` 域添加到 syslog 的消息（1.9.7）頭中。

syslog配置範例：

```yaml
error_log syslog:server=192.168.1.1 debug;

access_log syslog:server=unix:/var/log/nginx.sock,nohostname;
access_log syslog:server=[2001:db8::1]:12345,facility=local7,tag=nginx,severity=info combined;
```

記錄日誌到 syslog 的功能自從 1.7.2 版本開始可用。作為我們 [商業訂閱](http://nginx.com/products/?_ga=2.80571039.986778370.1500745948-1890203964.1497190280) 的一部分，記錄日誌到 syslog 的功能從 1.5.3 開始可用。

## 原文件

- [http://nginx.org/en/docs/syslog.html](http://nginx.org/en/docs/syslog.html)
