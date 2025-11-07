# WebSocket 代理

要將用戶端與伺服器之間的連接從 HTTP/1.1 轉換為 WebSocket，可是使用 HTTP/1.1 中的 [協議切換](https://tools.ietf.org/html/rfc2616#section-14.42) 機制。

然而，有一個微妙的地方：由於 `Upgrade` 是一個[逐跳](https://tools.ietf.org/html/rfc2616#section-13.5.1)（hop-by-hop）頭，它不會從用戶端傳遞到代理伺服器。當使用轉發代理時，用戶端可以使用 `CONNECT` 方法來規避此問題。然而，這不適用於反向代理，因為用戶端不知道任何代理伺服器，這需要在代理伺服器上進行特殊處理。

自 1.3.13 版本以來，nginx 實現了特殊的操作模式，如果代理伺服器返回一個 101響應碼（交換協議），則客戶機和代理伺服器之間將建立隧道，用戶端  通過請求中的 `Upgrade` 頭來請求協議交換。

如上所述，包括 `Upgrade` 和 `Connection` 的逐跳頭不會從用戶端傳遞到代理伺服器，因此為了使代理伺服器知道用戶端將協議切換到 WebSocket 的意圖，這些頭必須明確地傳遞：

```nginx
location /chat/ {
    proxy_pass http://backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

一個更複雜的例子是，對代理伺服器的請求中的 `Connection` 頭欄位的值取決於用戶端請求頭中的 `Upgrade` 欄位的存在：

```nginx
http {
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        ...

        location /chat/ {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
        }
    }
```

默認情況下，如果代理務器在 60 秒內沒有傳輸任何數據，連接將被關閉。這個超時可以通過 [proxy_read_timeout](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_read_timeout) 指令來增加。 或者，代理伺服器可以配置為定期發送 WebSocket ping 幀以重設超時並檢查連接是否仍然活躍。

## 原文件

[http://nginx.org/en/docs/http/websocket.html](http://nginx.org/en/docs/http/websocket.html)
