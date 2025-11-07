# 在 Win32 平台上使用 Visual C 構建 nginx

## 先決條件

要在 Microsoft Win32® 平台上構建 nginx，您需要：

- Microsoft Visual C編譯器。已知 Microsoft Visual Studio® 8 和 10 可以正常工作。
- [MSYS](http://www.mingw.org/wiki/MSYS)。
- 如果您要構建 OpenSSL® 和有 SSL 支持的 nginx，則需要 Perl。例如 [ActivePerl](http://www.activestate.com/activeperl) 或 [Strawberry Perl](http://strawberryperl.com/)。
- [Mercurial](https://www.mercurial-scm.org/) 用戶端
- [PCRE](http://www.pcre.org/)、[zlib](http://zlib.net/) 和 [OpenSSL](http://www.openssl.org/) 庫原始碼。

## 構建步驟

在開始構建之前，確保將 Perl、Mercurial 和 MSYS 的 bin 目錄路徑添加到 PATH 環境變數中。從 Visual C 目錄運行 vcvarsall.bat 腳本設置 Visual C 環境。

構建 nginx：

- 啟動 MSYS bash。
- 檢出 hg.nginx.org 倉庫中的 nginx 原始碼。例如：

```bash
hg clone http://hg.nginx.org/nginx
```

- 創建一個 build 和 lib 目錄，並將 zlib、PCRE 和 OpenSSL 庫原始碼解壓到 lib 目錄中：

```bash
mkdir objs
mkdir objs/lib
cd objs/lib
tar -xzf ../../pcre-8.41.tar.gz
tar -xzf ../../zlib-1.2.11.tar.gz
tar -xzf ../../openssl-1.0.2k.tar.gz
```

- 運行 configure 腳本：

```bash
auto/configure --with-cc=cl --builddir=objs --prefix= \
--conf-path=conf/nginx.conf --pid-path=logs/nginx.pid \
--http-log-path=logs/access.log --error-log-path=logs/error.log \
--sbin-path=nginx.exe --http-client-body-temp-path=temp/client_body_temp \
--http-proxy-temp-path=temp/proxy_temp \
--http-fastcgi-temp-path=temp/fastcgi_temp \
--with-cc-opt=-DFD_SETSIZE=1024 --with-pcre=objs/lib/pcre-8.41 \
--with-zlib=objs/lib/zlib-1.2.11 --with-openssl=objs/lib/openssl-1.0.2k \
--with-select_module --with-http_ssl_module
```

- 運行 make：

```bash
nmake -f objs/Makefile
```

## 相關內容

[Windows 下的 nginx](../介紹/Windows下的Nginx.md)

## 原文件

[http://nginx.org/en/docs/howto_build_on_win32.html](http://nginx.org/en/docs/howto_build_on_win32.html)
