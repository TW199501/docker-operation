# 貢獻導引

請嚴格按照以下步驟操作，如有任何問題，請提出 issue

* 在 GitHub 上點擊 `fork` 將本倉庫 fork 到自己的倉庫，如 `yourname/nginx-docs`，然後 `clone` 到本地。

```bash
$ git clone git@github.com:yourname/nginx-docs.git
$ cd nginx-docs
# 將項目與上游關聯
$ git remote add source git@github.com:DocsHome/nginx-docs.git
```

* 增加內容或者修復錯誤後提交，並推送到自己的倉庫。

```bash
$ git add .
$ git commit -am "Fix issue #1: change helo to hello"
$ git push origin master
```

* 在 GitHub 上提交 `pull request`。

* 請定期更新自己倉庫內容。

```bash
$ git fetch source
$ git rebase source/master
$ git push -f origin master
```

# 排版規範

本項目排版遵循 [中文排版指南](https://github.com/mzlogin/chinese-copywriting-guidelines) 規範。
