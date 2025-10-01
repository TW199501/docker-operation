貨櫃Cloudflare隧道
Docker為Cloudflare隧道組成貨櫃設置。此設置使您可以使用CloudFlare的基礎架構安全地將本地服務曝光到Internet。

目錄
介紹
CloudFlare隧道提供了一種安全的方法，可以將在本地網路上運行的Web伺服器公開到公共Internet上。這對於開發，遠端存取內部服務或安全地發布服務可能特別有用，而無需在路由器上打開埠。該項目中的容器設置了Cloudflare隧道，使其易於部署。

設置
要求
Docker
Docker組成
該設置假定CloudFlare是您域的DNS提供商。

環境變數
在.env文件中添加環境變數的遺失資訊：

cloudflare_tunnel_token =''
CloudFlare_Tunnel_Token：創建新隧道時，CloudFlare提供了這個令牌。用實際的令牌替換。
如何獲得Cloudflare隧道令牌
要獲得Cloudflare隧道令牌，請按照以下步驟：

登錄到您的Cloudflare儀錶板。
導航到零信任部分或訪問部分（取決於Cloudflare介面）。
從“導航”菜單中選擇隧道。
單擊創建隧道。
請按照螢幕上的說明命名隧道並選擇所需的配置。
創建隧道後，CloudFlare將提供隧道令牌。複製此令牌並將其黏貼到Cloudflare_tunnel_token下的.env文件中。
確保編輯.env文件並添加您的特定令牌：

奈米.env
為防止.env通過版本控制跟蹤，請運行以下命令：

git Update-index - Assume-Hunganged .ENV
主機配置
如果需要，修改主機文件以定義任何自訂主機名映射：

Nano Config/Hosts
添加需要在容器中映射的任何其他主機。為避免跟蹤此文件的更改，請運行：

git Updation-index - Assume Hinganged Config/Hosts

用法
啟動容器
要啟動Cloudflare隧道容器，請運行：

Docker組成-D
此命令將在獨立模式下啟動容器。

停止容器
要停止運行容器，請使用：

Docker構成
查看日誌
要查看運行容器的日誌，這可以幫助解決故障排除：

Docker記錄Cloudflare-Tunnel
清理
如果要刪除所有容器，網路和相關卷：

Docker撰寫 - volumes-槍手孔
