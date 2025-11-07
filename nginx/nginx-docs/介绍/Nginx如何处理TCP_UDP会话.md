# nginx 如何處理 TCP/UDP 會話

來自用戶端的 TCP/UDP 會話以階段的形式被逐步處理：

|階 段&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|描 述|
|:----|:----|
| Post-accept | 接收用戶端請求後的第一個階段。[ngx_stream_realip_module](http://nginx.org/en/docs/stream/ngx_stream_realip_module.html) 模組在此階段被調用。|
| Pre-access | 初步檢查訪問，[ngx_stream_limit_conn_module](http://nginx.org/en/docs/stream/ngx_stream_limit_conn_module.html) 模組在此階段被調用。 |
| Access | 實際處理之前的用戶端訪問限制，ngx_stream_access_module 模組在此階段被調用。 |
| SSL | TLS/SSL 終止，ngx_stream_ssl_module 模組在此階段被調用。 |
| Preread | 將數據的初始位元組讀入 [預讀緩衝區](http://nginx.org/en/docs/stream/ngx_stream_core_module.html#preread_buffer_size) 中，以允許如 [ngx_stream_ssl_preread_module](http://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html) 之類的模組在處理前分析數據。 |
| Content | 實際處理數據的強制階段，通常 [代理](http://nginx.org/en/docs/stream/ngx_stream_proxy_module.html) 到 [upstream](http://nginx.org/en/docs/stream/ngx_stream_upstream_module.html) 伺服器，或者返回一個特定的值給用戶端 |
| Log | 此為最後階段，用戶端會話處理結果將被記錄， [ngx_stream_log_module module](http://nginx.org/en/docs/stream/ngx_stream_log_module.html) 模組在此階段被調用。 |

## 原文件
[http://nginx.org/en/docs/stream/stream_processing.html](http://nginx.org/en/docs/stream/stream_processing.html)
