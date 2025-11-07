# QUIC 和 HTTP/3 支持

- [QUIC 和 HTTP/3 支持](#quic-和-http3-支持)
  - [從原始碼構建](#從原始碼構建)
  - [配置](#配置)
  - [配置範例](#配置範例)
  - [故障排除](#故障排除)

從1.25.0後，對 [QUIC](https://datatracker.ietf.org/doc/html/rfc9000) 和 [HTTP/3](https://datatracker.ietf.org/doc/html/rfc9114) 協議的支持可用。同時，1.25.0之後，QUIC 和 HTTP/3 支持在Linux二進制包 ([binary package](https://nginx.org/en/linux_packages.html))中可用。

> QUIC 和 HTTP/3 支持是實驗性的，請謹慎使用。

## 從原始碼構建

使用`configure`命令配置構建。請參考[從原始碼構建 nginx ](../How-To/從原始碼構建nginx.md)以獲得更多細節。

當配置nginx時，可以使用 [`--with-http_v3_module`](../How-To/從原始碼構建nginx.md#http_v3_module) 配置參數來啟用 QUIC 和 HTTP/3。

構建nginx時建議使用支持 QUIC 的 SSL 庫，例如 [BoringSSL](https://boringssl.googlesource.com/boringssl)，[LibreSSL](https://www.libressl.org/)，或者 [QuicTLS](https://github.com/quictls/openssl)。否則，將使用不支持[早期數據](../模組參考/http/ngx_http_ssl_module.md#ssl_early_data)的[OpenSSL](https://openssl.org/)相容層。

使用以下命令為 nginx 配置 [BoringSSL](https://boringssl.googlesource.com/boringssl)：

```bash
./configure
    --with-debug
    --with-http_v3_module
    --with-cc-opt="-I../boringssl/include"
    --with-ld-opt="-L../boringssl/build/ssl
                   -L../boringssl/build/crypto"
```

或者，可以使用 [QuicTLS](https://github.com/quictls/openssl) 配置 nginx：

```bash
./configure
    --with-debug
    --with-http_v3_module
    --with-cc-opt="-I../quictls/build/include"
    --with-ld-opt="-L../quictls/build/lib"
```

或者，可以使用現代版本的 [LibreSSL](https://www.libressl.org/) 配置 nginx：

```bash
./configure
    --with-debug
    --with-http_v3_module
    --with-cc-opt="-I../libressl/build/include"
    --with-ld-opt="-L../libressl/build/lib"
```

配置完成後，使用 `make` 編譯和安裝 nginx。

## 配置

[ngx_http_core_module](../模組參考/http/ngx_http_core_module.md) 模組中的 `listen` 指令獲得了一個新參數 [`quic`](../模組參考/http/ngx_http_core_module.md#quic)，它在指定埠上透過啟用 HTTP/3 over QUIC。

除了 `quic` 參數外，還可以指定 [`reuseport`](../模組參考/http/ngx_http_core_module.md#reuseport) 參數，使其在多個工作執行緒中正常工作。

有關指令列表，請參閱 [ngx_http_v3_module](https://nginx.org/en/docs/http/ngx_http_v3_module.html)。

要[啟用](https://nginx.org/en/docs/http/ngx_http_v3_module.html#quic_retry)地址驗證：

```nginx
quic_retry on;
```

要[啟用](../模組參考/http/ngx_http_ssl_module.md#ssl_early_data) 0-RTT：

```nginx
ssl_early_data on;
```

要[啟用](https://nginx.org/en/docs/http/ngx_http_v3_module.html#quic_gso) GSO (Generic Segmentation Offloading)：

```nginx
quic_gso on;
```

為多個 token [設置](https://nginx.org/en/docs/http/ngx_http_v3_module.html#quic_host_key) host key：

```nginx
quic_host_key <filename>;
```

QUIC 需要 TLSv1.3 協議版本，該版本在 [`ssl_protocols`](../模組參考/http/ngx_http_ssl_module.md#ssl_protocols) 指令中預設啟用。

默認情況下，[GSO Linux 特定最佳化](http://vger.kernel.org/lpc_net2018_talks/willemdebruijn-lpc2018-udpgso-paper-DRAFT-1.pdf)處於禁用狀態。如果相應的網路介面配置為支持 GSO，請啟用它。

## 配置範例

```nginx
http {
    log_format quic '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" "$http3"';

    access_log logs/access.log quic;

    server {
        # for better compatibility it's recommended
        # to use the same port for quic and https
        listen 8443 quic reuseport;
        listen 8443 ssl;

        ssl_certificate     certs/example.com.crt;
        ssl_certificate_key certs/example.com.key;

        location / {
            # required for browsers to direct them to quic port
            add_header Alt-Svc 'h3=":8443"; ma=86400';
        }
    }
}
```

## 故障排除

一些可能有助於識別問題的提示：

- 確保 nginx 是使用正確的 SSL 庫構建的。
- 確保 nginx 在運行時使用正確的 SSL 庫（`nginx -V` 顯示當前使用的內容）。
- 確保用戶端實際通過 QUIC 發送請求。建議從簡單的控制台用戶端（如 [ngtcp2](https://nghttp2.org/ngtcp2)）開始，以確保伺服器配置正確，然後再嘗試使用可能對證書非常挑剔的真實瀏覽器。
- 使用[除錯支持](../介紹/除錯日誌.md)構建nginx並檢查除錯日誌。它應包含有關連接及其失敗原因的所有詳細資訊。所有相關消息都包含“`quic`”前綴，可以輕鬆過濾掉。
- 為了進行更深入的調查，可以使用以下宏啟用其他除錯：`NGX_QUIC_DEBUG_PACKETS, NGX_QUIC_DEBUG_FRAMES, NGX_QUIC_DEBUG_ALLOC, NGX_QUIC_DEBUG_CRYPTO`。
```bash
./configure
    --with-http_v3_module
    --with-debug
    --with-cc-opt="-DNGX_QUIC_DEBUG_PACKETS -DNGX_QUIC_DEBUG_CRYPTO"
```
