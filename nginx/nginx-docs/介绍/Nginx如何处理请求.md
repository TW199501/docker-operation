# nginx 如何處理請求

- [基於名稱的虛擬伺服器](#name_based_virtual_servers)
- [如何使用未定義的 server 名稱來阻止處理請求](#how_to_prevent_undefined_server_names)
- [基於名稱和 IP 混合的虛擬伺服器](#mixed_name_ip_based_servers)
- [一個簡單的 PHP 站點配置](#simple_php_site_configuration)

<a id="name_based_virtual_servers"></a>

## 基於名稱的虛擬伺服器

nginx 首先決定哪個 `server` 應該處理請求，讓我們從一個簡單的配置開始，三個虛擬伺服器都監聽了 `*:80` 埠：

```nginx
server {
    listen      80;
    server_name example.org www.example.org;
    ...
}

server {
    listen      80;
    server_name example.net www.example.net;
    ...
}

server {
    listen      80;
    server_name example.com www.example.com;
    ...
}
```

在此配置中，nginx 僅檢驗請求的 header 域中的 `Host`，以確定請求應該被路由到哪一個 `server`。如果其值與任何的 `server` 名稱不匹配，或者該請求根本不包含此 header 域，nginx 會將請求路由到該埠的默認 `server` 中。在上面的配置中，默認 `server` 是第一個（這是 nginx 的標準默認行為）。你也可以在 [listen](http://nginx.org/en/docs/http/ngx_http_core_module.html#listen) 指令中使用 `default_server` 參數，明確地設置默認的 `server`。

```
server {
    listen      80 default_server;
    server_name example.net www.example.net;
    ...
}
```

> `default_server` 參數自 0.8.21 版本起可用。在早期版本中，應該使用 `default` 參數。

請注意，`default_server` 是 `listen port` 的屬性，而不是 `server_name` 的。之後會有更多關於這方面的內容。

<a id="how_to_prevent_undefined_server_names"></a>

## 如何使用未定義的 server 名稱來阻止處理請求

如果不允許沒有 “Host” header 欄位的請求，可以定義一個丟棄請求的 server：

```nginx
server {
    listen      80;
    server_name "";
    return      444;
}
```

這裡的 `server` 名稱設置為一個空字串，會匹配不帶 `Host` 的 header 域請求，nginx 會返回一個表示關閉連接的非標準代碼 444。

> 自 0.8.48 版本開始，這是 `server` 名稱的默認設置，因此可以省略 `server name ""`。在早期版本中，機器的主機名被作為 `server` 的默認名稱。

<a id="mixed_name_ip_based_servers"></a>

## 基於名稱和 IP 混合的虛擬伺服器

讓我們看看更加複雜的配置，其中一些虛擬伺服器監聽在不同的 IP 地址上監聽：

```nginx
server {
    listen      192.168.1.1:80;
    server_name example.org www.example.org;
    ...
}

server {
    listen      192.168.1.1:80;
    server_name example.net www.example.net;
    ...
}

server {
    listen      192.168.1.2:80;
    server_name example.com www.example.com;
    ...
}
```

此配置中，nginx 首先根據 [server](http://nginx.org/en/docs/http/ngx_http_core_module.html#server) 塊的 `listen` 指令檢驗請求的 IP 和埠。之後，根據與 IP 和埠相匹配的 `server` 塊的 [server_name](http://nginx.org/en/docs/http/ngx_http_core_module.html#server_name) 項對請求的“Host” header 域進行檢驗。如果找不到伺服器的名稱（server_name），請求將由 `default_server` 處理。例如，在 `192.168.1.1:80` 上收到的對 `www.example.com` 的請求將由 `192.168.1.1:80` 埠的 `default_server` （即第一個 server）處理，因為沒有 `www.example.com` 在此埠上定義。

如上所述，`default_server` 是 `listen port` 的屬性，可以為不同的埠定義不同的 `default_server`：

```nginx
server {
    listen      192.168.1.1:80;
    server_name example.org www.example.org;
    ...
}

server {
    listen      192.168.1.1:80 default_server;
    server_name example.net www.example.net;
    ...
}

server {
    listen      192.168.1.2:80 default_server;
    server_name example.com www.example.com;
    ...
}
```

<a id="simple_php_site_configuration"></a>

## 一個簡單的 PHP 站點配置

現在讓我們來看看 nginx 是如何選擇一個 `location` 來處理典型的簡單 PHP 站點的請求：

```nginx
server {
    listen      80;
    server_name example.org www.example.org;
    root        /data/www;

    location / {
        index   index.html index.php;
    }

    location ~* \.(gif|jpg|png)$ {
        expires 30d;
    }

    location ~ \.php$ {
        fastcgi_pass  localhost:9000;
        fastcgi_param SCRIPT_FILENAME
                      $document_root$fastcgi_script_name;
        include       fastcgi_params;
    }
}
```

nginx 首先忽略排序搜索具有最明確字串的前綴 `location`。在上面的配置中，唯一有符合的是前綴 `location` 為 `/`，因為它匹配任何請求，它將被用作最後的手段。之後，nginx 按照設定檔中列出的順序檢查由 `location` 的正則表達式。第一個匹配表達式停止搜索，nginx 將使用此 `location`。如果沒有正則表達式匹配請求，那麼 nginx 將使用前面找到的最明確的前綴 `location`。

請注意，所有類型的 `location` 僅僅是檢驗請求的 URI 部分，不帶參數。這樣做是因為查詢字串中的參數可以有多種形式，例如：

```
/index.php?user=john&page=1
/index.php?page=1&user=john
```

此外，任何人都可以在查詢字串中請求任何內容：

```
/index.php?page=1&something+else&user=john
```

現在來看看在上面的配置中是如何請求的：
- 請求 `/logo.gif` 首先與 前綴 `location` 為 `/` 相匹配，然後由正則表達式 `\.(gif|jpg|png)$` 匹配，因此由後一個 `location` 處理。使用指令 `root /data/www` 將請求映射到 `/data/www/logo.gif` 文件，並將文件發送給用戶端。
- 一個 `/index.php` 的請求也是首先與前綴 `location` 為 `/` 相匹配，然後是正則表達式 `\.(php)$`。因此，它由後一個 `location` 處理，請求將被傳遞給在 `localhost:9000` 上監聽的 FastCGI 伺服器。[fastcgi_param](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html#fastcgi_param) 指令將 FastCGI 參數 `SCRPT_FILENAME` 設置為 `/data/www/index.php`，FastCGI 伺服器執行該文件。變數 `$document_root` 與 [root](http://nginx.org/en/docs/http/ngx_http_core_module.html#root) 指令的值是一樣的，變數 `$fastcgi_script_name` 的值為請求URI，即 `/index.php`。
- `/about.html` 請求僅與前綴 `location` 為 `/` 相匹配，因此由此 `location` 處理。使用指令 `root /data/www` 將請求映射到 `/data/www/about.html` 文件，並將文件發送給用戶端。
- 處理請求 `/` 更複雜。它與前綴 `location` 為 `/` 相匹配。因此由該 `location` 處理。然後，[index](http://nginx.org/en/docs/http/ngx_http_index_module.html#index) 指令根據其參數和 `root /data/www` 指令檢驗索引文件是否存在。如果文件 `/data/www/index.html` 不存在，並且文件 `/data/www/index.php` 存在，則該指令執行內部重定向到 `/index.php`，就像請求是由用戶端發起的，nginx 將再次搜索 `location`。如之前所述，重定向請求最終由 FastCGI 伺服器處理。

由 Igor Sysoev 撰寫
由 Brian Mercer 編輯

## 原文

- [http://nginx.org/en/docs/http/request_processing.html](http://nginx.org/en/docs/http/request_processing.html)
