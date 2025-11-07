# 從原始碼構建 nginx

編譯時使用 `configure` 命令進行配置。它定義了系統的各個方面，包括了 nginx 進行連接處理使用的方法。最終它會創建出一個 `Makefile`。

`configure` 命令支持以下參數：

- **--help**

    列印幫助資訊
- **--prefix=path**

    定義一個用於保留伺服器文件的目錄。此目錄也將用於所有通過 `configure` 設置的相對路徑（除了庫原始碼路徑外）和 `nginx.conf` 設定檔。默認設置為 `/usr/local/nginx` 目錄。
- **--sbin-path=path**

    設置 nginx 可執行文件的名稱。此名稱僅在安裝過程中使用。默認情況下，檔案名為 `prefix/sbin/nginx`。
- **--modules-path=path**

    定義將安裝 nginx 動態模組的目錄。默認情況下，使用 `prefix/modules` 目錄。
- **--conf-path=path**

    設置 `nginx.conf` 設定檔的名稱。如果需要，nginx 可以使用不同的設定檔啟動，方法是使用命令行參數 `-c` 指定文件。默認情況下，檔案名為 `prefix/conf/nginx.conf`。
- **--error-log-path=path**

    設置主要錯誤、警告和診斷文件的名稱。安裝後，可以在 `nginx.conf` 設定檔中使用 [error_log](http://nginx.org/en/docs/ngx_core_module.html#error_log) 指令更改檔案名。默認情況下，檔案名為 `prefix/logs/error.log`。
- **--pid-path=path**

    設置儲存主進程的進程 ID 的 nginx.pid 檔案名稱。安裝後，可以在 `nginx.conf` 設定檔中使用 [pid](http://nginx.org/en/docs/ngx_core_module.html#pid) 指令更改檔案名。默認檔案名為 `prefix/logs/nginx.pid`。
- **--lock-path=path**

    設置鎖文件的名稱前綴。安裝後，可以在 `nginx.conf` 設定檔中使用 [lock_file](http://nginx.org/en/docs/ngx_core_module.html#lock_file) 指令更改對應的值。預設值為 `prefix/logs/nginx.lock`。
- **--user=name**

    設置一個非特權使用者名稱，其憑據將由工作進程使用。安裝後，可以在 `nginx.conf` 設定檔中使用 [user](http://nginx.org/en/docs/ngx_core_module.html#user) 指令更改名稱。預設的使用者名稱為 `nobody`。
- **--group=name**

    設置一個組的名稱，其憑據將由工作進程使用。安裝後，可以在 `nginx.conf` 設定檔中使用 [user](http://nginx.org/en/docs/ngx_core_module.html#user) 指令更改名稱。默認情況下，組名稱設置為一個非特權用戶的名稱。
- **--build=name**

    設置一個可選的 nginx 構建名稱
- **--builddir=path**

    設置構建文件夾
- **--http-log-path=path**

    設置 HTTP 伺服器主請求日誌檔案名稱。安裝後，可以在 `nginx.conf` 設定檔中使用 [access_log](http://nginx.org/en/docs/http/ngx_http_log_module.html#access_log) 指令更改檔案名。默認情況下，檔案名為 `prefix/logs/access.log`。
- **--with-select_module 和 --without-select_module**

    啟用或禁用構建允許伺服器使用 `select()` 方法的模組。如果平台不支持其他更合適的方法（如 kqueue、epoll 或 /dev/poll），則將自動構建該模組。
- **--with-poll_module 和 --without-poll_module**

    啟用或禁用構建允許伺服器使用 `poll()` 方法的模組。如果平台不支持其他更合適的方法（如 kqueue、epoll 或 /dev/poll），則將自動構建該模組。
- **with-threads**
    
    允許使用執行緒池[thread pools](http://nginx.org/en/docs/ngx_core_module.html#thread_pool)
- **with-file-aio**

    啟用在FreeBSD和Linux上[asynchronous file I/O](http://nginx.org/en/docs/http/ngx_http_core_module.html#aio) (aio)指令的使用
- **--without-http_gzip_module**

    禁用構建 HTTP 伺服器[響應壓縮](http://nginx.org/en/docs/http/ngx_http_gzip_module.html)模組。需要 zlib 庫來構建和運行此模組。
- **--without-http_rewrite_module**

    禁用構建允許 HTTP 伺服器[重定向請求](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html)和[更改請求 URI](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html) 的模組。需要 PCRE 庫來構建和運行此模組。
- **--without-http_proxy_module**

    禁用構建 HTTP 伺服器[代理模組](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)。
- **--with-http_ssl_module**

    允許構建可將 [HTTPS 協議支持](http://nginx.org/en/docs/http/ngx_http_ssl_module.html)添加到 HTTP 伺服器的模組。默認情況下，此模組參與構建。構建和運行此模組需要 OpenSSL 庫支持。
- **with-http_v2_module**

    允許構建一個支持[HTTP/2](http://nginx.org/en/docs/http/ngx_http_v2_module.html) 的模組。默認情況下，該模組不構建。
- **with-http_realip_module**
    
    允許構建[ngx_http_realip_module](http://nginx.org/en/docs/http/ngx_http_realip_module.html) 模組，該模組將用戶端地址更改為在指定的header中發送的地址。該模組默認不構建。
- **with-http_addition_module**

    允許構建[ngx_http_addition_module](http://nginx.org/en/docs/http/ngx_http_addition_module.html) 模組，該模組能夠在響應之前和之後添加文本。該模組默認不構建。
- **with-http_xslt_module**和**with-http_xslt_module=dynamic**

    允許構建使用一個或者多個XSLT樣式錶轉化為XML響應的[ngx_http_xslt_module](http://nginx.org/en/docs/http/ngx_http_xslt_module.html)。該模組默認不構建。[libxslt](http://xmlsoft.org/XSLT/) 和 [libxml2](http://xmlsoft.org/) 庫需要這個模組來構建和啟動。
- **with-http_image_filter_module**和**with-http_image_filter_module=dynamic**

    允許構建[ngx_http_image_filter_module](http://nginx.org/en/docs/http/ngx_http_image_filter_module.html) 模組，該模組可以轉換 JPEG, GIF, PNG, 和 WebP 格式的圖片。該模組默認不構建。
- **with-http_geoip_module**和**with-http_geoip_module=dynamic**
    
    允許構建[ngx_http_geoip_module](http://nginx.org/en/docs/http/ngx_http_geoip_module.html) 模組。該模組根據用戶端 IP 地址和預編譯[MaxMind](https://www.maxmind.com/en/home) 的資料庫創建變數。該模組默認不構建。
- **with-http_sub_module**

    允許構建[ngx_http_sub_module](http://nginx.org/en/docs/http/ngx_http_sub_module.html) 模組。該模組透過將一個指定的字串替換為另一個來修改相應。該模組默認不構建。
- **with-http_dav_module**
    
    允許構建[ngx_http_dav_module ](http://nginx.org/en/docs/http/ngx_http_dav_module.html) 模組。該模組通過WebDEV協議提供文件管理自動化。該模組默認不構建。
- **with-http_flv_module**
    
    允許構建[ngx_http_flv_module](http://nginx.org/en/docs/http/ngx_http_flv_module.html) 模組。該模組為 Flash Videos (FLV) 文件提供偽流伺服器端的支持。該模組默認不構建。
- **with-http_mp4_module**
    
    允許構建[ngx_http_mp4_module](http://nginx.org/en/docs/http/ngx_http_mp4_module.html) 模組。該模組為 MP4 文件提供偽流伺服器端的支持。該模組默認不構建。
- **with-http_gunzip_module**
    
    允許構建[ngx_http_gunzip_module](http://nginx.org/en/docs/http/ngx_http_gunzip_module.html) 模組。該模組使用 `Content-Encoding: gzip` 來解壓縮響應對於那些不支持`gzip`編碼方法的用戶端。該模組默認不構建。
- **with-http_auth_request_module**
    
    允許構建[ngx_http_auth_request_module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html) 模組。該模組基於子請求的結果實現用戶端授權。該模組默認不構建。
- **with-http_random_index_module**
    
    允許構建[ngx_http_random_index_module](http://nginx.org/en/docs/http/ngx_http_random_index_module.html) 模組。該模組處理斜槓字元 ('/') 結尾的請求，並選擇目錄中的隨機文件作為索引文件。該模組默認不構建。
- **with-http_secure_link_module**
    
    允許構建[ngx_http_secure_link_module](http://nginx.org/en/docs/http/ngx_http_secure_link_module.html) 模組。該模組默認不構建。
- **with-http_degradation_module**
    
    允許構建 `with-http_degradation_module` 模組。該模組默認不構建。
- **with-http_slice_module**
    
    允許構建[ngx_http_slice_module](http://nginx.org/en/docs/http/ngx_http_slice_module.html) 將請求拆分為子請求的模組，每個模組都返回一定範圍的響應。該模組提供了更有效的大響應快取。該模組默認不構建。
- **with-http_stub_status_module**
    
    允許構建[ngx_http_stub_status_module](http://nginx.org/en/docs/http/ngx_http_stub_status_module.html) 模組。該模組提供對基本狀態資訊的訪問。該模組默認不構建。
- **without-http_charset_module**
    
    禁用構建壓縮 HTTP 響應的[ngx_http_charset_module](http://nginx.org/en/docs/http/ngx_http_charset_module.html) 模組。該模組將指定的字元集添加到 `Content-Type` 響應頭欄位，還可以將數據從一個字元集轉化為另一個字元集。
- **without-http_gzip_module**
    
    禁用構建壓縮 HTTP 響應的[compresses responses](http://nginx.org/en/docs/http/ngx_http_gzip_module.html) 模組。構建和運行這個模組需要 zlib 庫。
- **without-http_ssi_module**
    
    禁用構建[without-http_ssi_module](http://nginx.org/en/docs/http/ngx_http_gzip_module.html) 模組。該模組在通過它的響應中處理 SSI (服務端包含) 命令。
- **without-http_userid_module**
    
    允許構建[ngx_http_userid_module](http://nginx.org/en/docs/http/ngx_http_userid_module.html) 模組。該模組設置適合用戶端識別的cookie。
- **without-http_access_module**
    
    禁用構建[ngx_http_access_module](http://nginx.org/en/docs/http/ngx_http_access_module.html) 模組。該模組允許限制對某些用戶端地址的訪問。
- **without-http_auth_basic_module**
 
    禁用構建[ngx_http_auth_basic_module](http://nginx.org/en/docs/http/ngx_http_auth_basic_module.html) 模組。該模組允許透過使用HTTP基本身份驗證協議驗證使用者名稱密碼來限制對資源的訪問。
- **without-http_mirror_module**
 
    禁用構建[ngx_http_mirror_module](http://nginx.org/en/docs/http/ngx_http_mirror_module.html) 模組。該模組透過創建後台鏡像子請求來實現原始請求的鏡像。
- **without-http_autoindex_module**
 
    禁用構建[ngx_http_autoindex_module](http://nginx.org/en/docs/http/ngx_http_autoindex_module.html) 模組。該模組處理以斜槓('/')結尾的請求，並在[ngx_http_index_module](http://nginx.org/en/docs/http/ngx_http_index_module.html) 模組找不到索引文件的情況下生成目錄列表。
- **without-http_geo_module**
 
    禁用構建[ngx_http_geo_module](http://nginx.org/en/docs/http/ngx_http_geo_module.html) 模組。該模組使用取決於用戶端IP位址的值創建變數。
- **without-http_map_module**
 
    禁用構建[ngx_http_map_module](http://nginx.org/en/docs/http/ngx_http_map_module.html) 模組。該模組使用取決於其他變數的值創建變數。
- **without-http_split_clients_module**
 
    禁用構建[ngx_http_split_clients_module](http://nginx.org/en/docs/http/ngx_http_split_clients_module.html) 模組。該模組為 A/B 測試創建變數。
- **without-http_referer_module**
 
    禁用構建[ngx_http_referer_module](http://nginx.org/en/docs/http/ngx_http_referer_module.html) 模組。該模組可以阻止對 “Referer” 頭欄位中具有無效值的請求訪問站點。
- **without-http_proxy_module**
 
    禁用構建允許HTTP伺服器重定向的請求和更改請求URI [redirect requests and change URI of requests](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html) 的模組。
- **without-http_proxy_module**
 
    禁用構建[proxying module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html) HTTP伺服器代理模組。 
- **without-http_fastcgi_module**
 
    禁用構建將請求傳遞給FastCGI伺服器的[ngx_http_fastcgi_module](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)模組。
- **without-http_uwsgi_module**
 
    禁用構建將請求傳遞給uwsgi伺服器的[ngx_http_uwsgi_module](http://nginx.org/en/docs/http/ngx_http_uwsgi_module.html) 模組。
- **without-http_scgi_module**
 
    禁用構建將請求傳遞給SCGI伺服器的[ngx_http_scgi_module](http://nginx.org/en/docs/http/ngx_http_scgi_module.html) 模組。
- **without-http_grpc_module**
 
    禁用構建將請求傳遞給個RPC伺服器[ngx_http_grpc_module](http://nginx.org/en/docs/http/ngx_http_grpc_module.html) 模組。
- **without-http_memcached_module**
 
    禁用構建[ngx_http_memcached_module](http://nginx.org/en/docs/http/ngx_http_memcached_module.html) 模組。該模組從 memcached 伺服器獲得響應。
- **without-http_limit_conn_module**
 
    禁用構建[ngx_http_limit_conn_module](http://nginx.org/en/docs/http/ngx_http_limit_conn_module.html) 模組。該模組限制每個金鑰的連結數，例如，來自單個IP位址的連結數。
- **without-http_limit_req_module**
 
    禁用構建限制每個鍵的請求處理速率[ngx_http_limit_req_module](http://nginx.org/en/docs/http/ngx_http_limit_req_module.html) 模組。例如，來自單個IP位址的請求的處理速率。
- **without-http_empty_gif_module**
 
    禁用構建發出單像素透明GIF[emits single-pixel transparent GIF](http://nginx.org/en/docs/http/ngx_http_empty_gif_module.html) 模組。
- **without-http_browser_module**
 
    禁用構建[ngx_http_browser_module](http://nginx.org/en/docs/http/ngx_http_browser_module.html) 模組。該模組創建的值的變數取決於 “User-Agent” 請求標頭欄位的值。
- **without-http_upstream_hash_module**
 
    禁用構建實現散列負載均衡的方法[hash](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#hash) 模組。  
- **without-http_upstream_ip_hash_module**
 
    禁用構建實現[IP_Hash](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#ip_hash) 負載均衡方法的模組。 
- **without-http_upstream_least_conn_module**
 
    禁用構建實現[least_conn](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#least_conn) 負載均衡方法的模組。 
- **without-http_upstream_keepalive_module**
 
    禁用構建[caching of connections](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive) 模組。該模組提供到上游伺服器的連結快取。 
- **without-http_upstream_zone_module**
 
    禁用構建[zone](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#zone) 模組。該模組可以將上游組的運行時狀態儲存在共享記憶體區域中。 
- **with-http_perl_module**和**with-http_perl_module=dynamic**
 
    構建[嵌入式Perl](http://nginx.org/en/docs/http/ngx_http_perl_module.html) 模組。該模組默認不構建。 
- **--with-perl_modules_path=path**
 
    定義一個保留Perl模組的路徑。 
- **with-perl=path**
 
    設置Perl二進制文件的名字。 
- **http-client-body-temp-path**
 
    定義用於儲存保存用戶端的請求主體的臨時文件的目錄。安裝後，可以使用[client_body_temp_path](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_temp_path) 指令在nginx.conf設定檔中始終更改目錄。預設的目錄名為 `prefix/client_body_temp`。 
- **http-proxy-temp-path=path**
 
    定義一個目錄，用於儲存臨時文件和從代理伺服器接受的數據。安裝後可以使用[proxy_temp_path](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_temp_path) 指令在nginx.conf設定檔中更改。預設的目錄名為 `profix/proxy_temp`
- **http-fastcgi-temp-path=path**
 
    定義一個目錄，用於儲存臨時文件和從 FastCGI 伺服器接受的數據。安裝後可以使用[fastcgi_temp_path](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html#fastcgi_temp_path) 指令在nginx.conf設定檔中更改。 預設的目錄為 `prefix/fastcgi_temp`
- **http-uwsgi-temp-path=path**
 
    定義一個目錄，用於儲存臨時文件和從 uwsgi  伺服器接受的數據。安裝後可以使用[uwsgi_temp_path](http://nginx.org/en/docs/http/ngx_http_uwsgi_module.html#uwsgi_temp_path) 指令在nginx.conf設定檔中更改。 預設的目錄為 `prefix/uwsgi_temp`
- **http-scgi-temp-path=path**
 
    定義一個目錄，用於儲存臨時文件和從 SCGI 伺服器接受的數據。安裝後可以使用[scgi_temp_path](http://nginx.org/en/docs/http/ngx_http_scgi_module.html#scgi_temp_path) 指令在nginx.conf設定檔中更改。 預設的目錄為 `prefix/scgi_temp`
- **without-http**
 
    禁用構建[HTTP](http://nginx.org/en/docs/http/ngx_http_core_module.html) 模組。 
- **without-http-cache**
 
    禁用 HTTP 快取。                                                                                                           
- **with-mail**和**with-mail=dynamic**
 
    啟用構建 POP3/IMAP4/SMTP [mail proxy](http://nginx.org/en/docs/mail/ngx_mail_core_module.html) 模組。
- **with-mail_ssl_module**
 
    啟用構建[SSL/TLS protocol support](http://nginx.org/en/docs/mail/ngx_mail_ssl_module.html) 模組，將SSL/TLS協議支持添加到郵件代理伺服器。默認不構建此模組。需要OpenSSL庫來構建和運行此模組。
- **without-mail_pop3_module**
 
    禁用郵件代理伺服器中的[POP3](http://nginx.org/en/docs/mail/ngx_mail_pop3_module.html) 協議。
- **without-mail_imap_module**
 
    禁用郵件代理伺服器中的[IMAP](http://nginx.org/en/docs/mail/ngx_mail_imap_module.html) 協議。
- **without-mail_smtp_module**
 
    禁用郵件代理伺服器中的[SMTP](http://nginx.org/en/docs/mail/ngx_mail_smtp_module.html) 協議。
- **with-stream**和**with-stream=dynamic**
 
    啟用構建[流模組](http://nginx.org/en/docs/stream/ngx_stream_core_module.html) 模組以進行通用的 TCP/UDP 代理和負載均衡。該模組默認不構建。
- **with-stream_ssl_module**
 
    啟用構建[SSL/TLS protocol support](http://nginx.org/en/docs/stream/ngx_stream_ssl_module.html) 模組。為流模組添加SSL/TLS協議支持。默認不構建此模組。需要OpenSSL庫來構建和運行此模組。
- **with-stream_realip_module**
 
    啟用構建[ngx_stream_realip_module](http://nginx.org/en/docs/http/ngx_stream_realip_module.html) 模組。該模組將用戶端地址更改為 PROXY 協議頭中發送的地址。默認不構建此模組。
- **with-stream_geoip_module**和**with-stream_geoip_module=dynamic**
 
    啟用構建[ngx_stream_geoip_module](http://nginx.org/en/docs/stream/ngx_stream_geoip_module.html) 模組。該模組根據用戶端地址和預編譯的[MaxMind](http://www.maxmind.com/) 資料庫創建變數。默認不構建。
- **with-stream_ssl_preread_module**
 
    禁用構建[with-http_degradation_modulengx_stream_ssl_preread_module](http://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html) 模組。該模組允許從[ClientHello](https://tools.ietf.org/html/rfc5246#section-7.4.1.2) 消息中提取消息而不終止SSL/TLS。
- **without-stream_limit_conn_module**
 
    禁用構建[ngx_stream_limit_conn_module](http://nginx.org/en/docs/stream/ngx_stream_limit_conn_module.html) 模組。該模組限制每個金鑰的連接數，例如，來自單個IP位址的連接數。
- **without-stream_geo_module**
 
    禁用構建[ngx_stream_geo_module](http://nginx.org/en/docs/stream/ngx_stream_geo_module.html) 模組。該模組使用取決於用戶端IP位址的值創建變數。
- **without-stream_map_module**
 
    禁用構建[ngx_stream_map_module](http://nginx.org/en/docs/stream/ngx_stream_map_module.html) 模組。該模組根據其他變數的值創建值。
- **without-stream_split_clients_module**
 
    禁用構建[ngx_stream_split_clients_module](http://nginx.org/en/docs/stream/ngx_stream_split_clients_module.html) 模組。該模組為 A/B 測試創建變數
- **without-stream_return_module**
 
    禁用構建[ngx_stream_return_module](http://nginx.org/en/docs/stream/ngx_stream_return_module.html) 模組。該模組將一些指定值發送到用戶端，然後關閉連接。
- **without-stream_upstream_hash_module**
 
    禁用構建[hash](http://nginx.org/en/docs/stream/ngx_stream_upstream_module.html#hash) 實現散列負載平衡方法的模組。
- **without-stream_upstream_least_conn_module**
 
    禁用構建[least_conn](http://nginx.org/en/docs/stream/ngx_stream_upstream_module.html#least_conn) 實現散列負載平衡方法的模組。
- **without-stream_upstream_zone_module**
 
    禁用構建[zone](http://nginx.org/en/docs/stream/ngx_stream_upstream_module.html#zone) 的模組。該模組可以將上游組的運行時狀態儲存在共享記憶體區域中
- **with-google_perftools_module**
 
    禁用構建[ngx_google_perftools_module ](http://nginx.org/en/docs/ngx_google_perftools_module.html) 模組。該模組可以使用 [Google Performance Tools](https://github.com/gperftools/gperftools) 分析nginx工作進程。該模組適用於nginx開發人員，默認情況下不構建。
- **with-cpp_test_module**
 
    啟用構建ngx_cpp_test_module模組。
- **add-module=path**
 
    啟用外部模組。
- **add-dynamic-module=path**
 
    啟用動態模組。
- **with-compat**
 
    實現動態相容模組。
- **with-cc=path**
 
    設置C編譯器的名稱。
- **with-cpp=path**
 
    設置C++處理器的名稱。
- **with-cc-opt=parameters**
 
    設置將添加到CFLAGS變數的其他參數。在FreeBSD下使用系統PCRE庫時，應指定`--with-cc-opt =" - I / usr / local / include"`。如果需要增加 select() 支持的文件數，也可以在此處指定，例如： `- with-cc-opt =" - D FD_SETSIZE = 2048"`。
- **with-ld-opt=parameters**
 
    設置將在連結期間使用的其他參數。在FreeBSD下使用系統PCRE庫時，應指定`--with-ld-opt =" - L / usr / local / lib"`。
- **with-cpu-opt=cpu**
 
    指定編譯的 CPU ，pentium, pentiumpro, pentium3, pentium4, athlon, opteron, sparc32, sparc64, ppc64。
- **without-pcre**
 
    禁用 PCRE 庫的使用。
- **with-pcre**
 
    強制使用 PCRE 庫。
- **with-pcre=path**
 
    設置 PCRE 庫源的路徑。需要從 [PCRE](http://www.pcre.org/) 站點下載分發（版本4.4 - 8.42）並將其解壓縮。剩下的工作由nginx的./configure和make完成。該位置指令和 [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html) 模組中的正則表達式支持需要該庫。
- **with-pcre-opt=parameters**
 
    為PCRE設置其他構建選項。
- **with-zlib-opt=parameters**
 
    為zlib設置其他構建選項。
- **with-zlib-asm=cpu**
 
    啟用使用針對其中一個指定CPU最佳化的zlib匯編程序源：pentium，pentiumpro。
- **with-libatomic**
 
    強制libatomic_ops庫使用。
- **with-libatomic=path**
 
    設置libatomic_ops庫源的路徑。
- **with-openssl=path**
 
    設置OpenSSL庫源的路徑。
- **with-openssl-opt=parameters**
 
    為OpenSSL設置其他構建選項。
- **with-debug**
 
    啟用 [除錯日誌](http://nginx.org/en/docs/debugging_log.html) 。                                                                                                                                                             
- **--with-pcre=path**

    設置 PCRE 庫的源路徑。發行版（4.4 至 8.40 版本）需要從 [PCRE](http://www.pcre.org/) 站點下載並提取。其餘工作由 nginx 的 `./configure` 和 `make` 完成。該庫是 [location](http://nginx.org/en/docs/http/ngx_http_core_module.html#location) 指令和 [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html) 模組中正則表達式支持所必需的。
- **--with-pcre-jit**

    使用“即時編譯（just-in-time compilation）”支持（1.1.12版本的 [pcre_jit](http://nginx.org/en/docs/ngx_core_module.html#pcre_jit) 指令）構建 PCRE 庫。
- **--with-zlib=path**

    設置 zlib 庫的源路徑。發行版（1.1.3 至 1.2.11 版本）需要從 [zlib](http://zlib.net/) 站點下載並提取。其餘工作由 nginx 的 `./configure` 和 `make` 完成。該庫是 [ngx_http_gzip_module](http://nginx.org/en/docs/http/ngx_http_gzip_module.html) 模組所必需的。
- **--with-cc-opt=parameters**

    設置添加到 CFLAGS 變數的額外參數。當在 FreeBSD 下使用系統的 PCRE 庫時，應指定 `--with-cc-opt="-I /usr/local/include"`。如果需要增加 `select()` 所支持的文件數量，也可以在這裡指定，如：`--with-cc-opt="-D FD_SETSIZE=2048"`。
- **--with-ld-opt=parameters**

    設置連結期間使用的其他參數。在 FreeBSD 下使用系統 PCRE 庫時，應指定--with-ld-opt="-L /usr/local/lib"`。

參數使用範例：

```bash
./configure \
    --sbin-path=/usr/local/nginx/nginx \
    --conf-path=/usr/local/nginx/nginx.conf \
    --pid-path=/usr/local/nginx/nginx.pid \
    --with-http_ssl_module \
    --with-pcre=../pcre-8.40 \
    --with-zlib=../zlib-1.2.11
```

配置完成之後，使用 `make` 和 `make install` 編譯和安裝 nginx。

## 原文件

[http://nginx.org/en/docs/configure.html](http://nginx.org/en/docs/configure.html)
