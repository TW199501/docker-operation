# 轉換重寫規則

## 重定向到主站點

使用共享主機的用戶以前僅使用 Apache 的 `.htaccess` 文件來配置一切，通常翻譯下列規則：

```apacheconf
RewriteCond  %{HTTP_HOST}  example.org
RewriteRule  (.*)          http://www.example.org$1
```

像這樣：

```nginx
server {
    listen       80;
    server_name  www.example.org  example.org;
    if ($http_host = example.org) {
        rewrite  (.*)  http://www.example.org$1;
    }
    ...
}
```

這是一個錯誤、麻煩而無效的做法。正確的方式是為 `example.org` 定義一個單獨的伺服器：

```nginx
server {
    listen       80;
    server_name  example.org;
    return       301 http://www.example.org$request_uri;
}

server {
    listen       80;
    server_name  www.example.org;
    ...
}
```

在 0.9.1 之前的版本，重定向可以透過以下方式實現：

```nginx
rewrite ^ http://www.example.org$request_uri?;
```

另一個例子是使用了顛倒邏輯，即 **所有不是 `example.com` 和 `www.example.com` 的**：

```apacheconf
RewriteCond  %{HTTP_HOST}  !example.com
RewriteCond  %{HTTP_HOST}  !www.example.com
RewriteRule  (.*)          http://www.example.com$1
```

應該簡單地定義 `example.com`、`www.example.com` 和 **其他一切**：

```nginx
server {
    listen       80;
    server_name  example.com www.example.com;
    ...
}

server {
    listen       80 default_server;
    server_name  _;
    return       301 http://example.com$request_uri;
}
```

在 0.9.1 之前的版本，重定向可以透過以下方式實現：

```nginx
rewrite ^ http://example.com$request_uri?;
```

## 轉換 Mongrel 規則

典型的 Mongrel 規則：

```apacheconf
DocumentRoot /var/www/myapp.com/current/public

RewriteCond %{DOCUMENT_ROOT}/system/maintenance.html -f
RewriteCond %{SCRIPT_FILENAME} !maintenance.html
RewriteRule ^.*$ %{DOCUMENT_ROOT}/system/maintenance.html [L]

RewriteCond %{REQUEST_FILENAME} -f
RewriteRule ^(.*)$ $1 [QSA,L]

RewriteCond %{REQUEST_FILENAME}/index.html -f
RewriteRule ^(.*)$ $1/index.html [QSA,L]

RewriteCond %{REQUEST_FILENAME}.html -f
RewriteRule ^(.*)$ $1.html [QSA,L]

RewriteRule ^/(.*)$ balancer://mongrel_cluster%{REQUEST_URI} [P,QSA,L]
```

應該轉換為：

```nginx
location / {
    root       /var/www/myapp.com/current/public;

    try_files  /system/maintenance.html
               $uri  $uri/index.html $uri.html
               @mongrel;
}

location @mongrel {
    proxy_pass  http://mongrel;
}
```

## 原文件

[http://nginx.org/en/docs/http/converting_rewrite_rules.html](http://nginx.org/en/docs/http/converting_rewrite_rules.html)
