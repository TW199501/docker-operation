# 使用 DTrace pid 提供程序除錯 nginx

本文假設讀者對 nginx 內部原理和 [DTrace](http://nginx.org/en/docs/nginx_dtrace_pid_provider.html#see_also) 有了一定的了解。

雖然使用了 [--with-debug](http://nginx.org/en/docs/debugging_log.html) 選項構建的 nginx 已經提供了大量關於請求處理的資訊，但有時候更有必要詳細地跟蹤代碼路徑的特定部分，同時省略其餘不必要的除錯輸出。DTrace pid 提供程序（在 Solaris，MacOS 上可用）是一個用於瀏覽用戶程序內部的有用工具，因為它不需要更改任何代碼，就可以幫助您完成任務。跟蹤和列印 nginx 函數調用的簡單 DTrace 腳本範例如下所示：

```d
#pragma D option flowindent

pid$target:nginx::entry {
}

pid$target:nginx::return {
}
```

儘管如此，DTrace 的函數調用跟蹤功能僅提供有限的有用資訊。即時檢查的功能參數通常更加有趣，但也更複雜一些。以下範例旨在幫助讀者熟悉 DTrace 以及使用 DTrace 分析 nginx 行為的過程。

使用 DTrace 與 nginx 的常見方案之一是：附加到 nginx 的工作進程來記錄請求行和請求開始時間。附加的相應函數是 `ngx_http_process_request()`，參數指向的是一個 `ngx_http_request_t` 結構的指針。使用 DTrace 腳本實現這種請求日誌記錄可以簡單到：

```d
pid$target::*ngx_http_process_request:entry
{
    this->request = (ngx_http_request_t *)copyin(arg0, sizeof(ngx_http_request_t));
    this->request_line = stringof(copyin((uintptr_t)this->request->request_line.data,
                                         this->request->request_line.len));
    printf("request line = %s\n", this->request_line);
    printf("request start sec = %d\n", this->request->start_sec);
}
```

需要注意的是，在上面的範例中，DTrace 需要引用 `ngx_http_process_request` 結構的一些相關資訊。不幸的是，雖然可以在 DTrace 腳本中使用特定的 `#include` 指令，然後將其傳遞給 C 前處理器（使用 `-C` 標誌），但這並不能真正奏效。由於大量的交叉依賴，幾乎所有的 nginx 頭文件都必須包含在內。反過來，基於 `configure` 腳本設置，nginx 頭將包括 PCRE、OpenSSL 和各種系統頭文件。理論上，在 DTrace 腳本預處理和編譯時，與特定的 nginx 構建相關的所有頭文件都有可能被包含進來，實際上 DTrace 腳本很有可能由於某些頭文件中的未知語法而造成無法編譯。

上述問題可以通過在 DTrace 腳本中僅包含相關且必要的結構和類型定義來解決。DTrace 必須知道結構、類型和欄位偏移的大小。因此，透過手動最佳化用於 DTrace 的結構定義，可以進一步降低依賴。

讓我們使用上面的 DTrace 腳本範例，看看它需要哪些結構定義才能正常地工作。

首先應該包含由 configure 生成的 `objs/ngx_auto_config.h` 文件，因為它定義了一些影響各個方面的 `＃ifdef` 常量。之後，一些基本類型和定義（如 `ngx_str_t`，`ngx_table_elt_t`，`ngx_uint_t` 等）應放在 DTrace 腳本的開頭。這些定義經常被使用但不太可能經常改變的。

那裡有一個包含許多指向其他結構的指針的 ngx_http_process_request_t 結構。因為這些指針與這個腳本無關，而且因為它們具有相同的大小，所以可以用 void 指針來替換它們。但最好添加合適的 typedef，而不是更改定義：

```d
typedef ngx_http_upstream_t     void;
typedef ngx_http_request_body_t void;
```

最後但同樣重要的是，需要添加兩個成員結構的定義（`ngx_http_headers_in_t`，`ngx_http_headers_out_t`）、回調函數聲明和常量定義。

最後，DTrace 腳本可以從 [這裡](http://nginx.org/download/trace_process_request.d) 下載。

以下範例是運行此腳本的輸出：

```
# dtrace -C -I ./objs -s trace_process_request.d -p 4848
dtrace: script 'trace_process_request.d' matched 1 probe
CPU     ID                    FUNCTION:NAME
  1      4 .XAbmO.ngx_http_process_request:entry request line = GET / HTTP/1.1
request start sec = 1349162898

  0      4 .XAbmO.ngx_http_process_request:entry request line = GET /en/docs/nginx_dtrace_pid_provider.html HTTP/1.1
request start sec = 1349162899
```

使用類似的技術，讀者應該能夠跟蹤其他 nginx 函數調用。

## 相關閱讀

- [Solaris 動態跟蹤指南](http://docs.oracle.com/cd/E19253-01/817-6223/index.html)
- [DTrace pid 提供程式介紹](http://dtrace.org/blogs/brendan/2011/02/09/dtrace-pid-provider/)

## 原文件

[http://nginx.org/en/docs/nginx_dtrace_pid_provider.html](http://nginx.org/en/docs/nginx_dtrace_pid_provider.html)
