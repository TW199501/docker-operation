# CHAT2API

🤖 一個簡單的 ChatGPT TO API 代理

🌟 無需賬號即可使用免費、無限的 `GPT-3.5`

💥 支持 AccessToken 使用賬號，支持 `O3-mini/high`、`O1/mini/Pro`、`GPT-4/4o/mini`、`GPTs`

🔍 回覆格式與真實 API 完全一致，適配幾乎所有客户端

👮 配套用户管理端[Chat-Share](https://github.com/h88782481/Chat-Share)使用前需提前配置好環境變量（ENABLE_GATEWAY設置為True，AUTO_SEED設置為False）


## 交流羣

[https://t.me/chat2api](https://t.me/chat2api)

要提問請先閲讀完倉庫文檔，尤其是常見問題部分。

提問時請提供：

1. 啓動日誌截圖（敏感信息打碼，包括環境變量和版本號）
2. 報錯的日誌信息（敏感信息打碼）
3. 接口返回的狀態碼和響應體

## 功能

### 最新版本號存於 `version.txt`

### 逆向API 功能
> - [x] 流式、非流式傳輸
> - [x] 免登錄 GPT-3.5 對話
> - [x] GPT-3.5 模型對話（傳入模型名不包含 gpt-4，則默認使用 gpt-3.5，也就是 text-davinci-002-render-sha）
> - [x] GPT-4 系列模型對話（傳入模型名包含: gpt-4，gpt-4o，gpt-4o-mini，gpt-4-moblie 即可使用對應模型，需傳入 AccessToken）
> - [x] O1 系列模型對話（傳入模型名包含 o1-preview，o1-mini 即可使用對應模型，需傳入 AccessToken）
> - [x] GPT-4 模型畫圖、代碼、聯網
> - [x] 支持 GPTs（傳入模型名：gpt-4-gizmo-g-*）
> - [x] 支持 Team Plus 賬號（需傳入 team account id）
> - [x] 上傳圖片、文件（格式為 API 對應格式，支持 URL 和 base64）
> - [x] 可作為網關使用，可多機分佈部署
> - [x] 多賬號輪詢，同時支持 `AccessToken` 和 `RefreshToken`
> - [x] 請求失敗重試，自動輪詢下一個 Token
> - [x] Tokens 管理，支持上傳、清除
> - [x] 定時使用 `RefreshToken` 刷新 `AccessToken` / 每次啓動將會全部非強制刷新一次，每4天晚上3點全部強制刷新一次。
> - [x] 支持文件下載，需要開啓歷史記錄
> - [x] 支持 `O3-mini/high`、`O1/mini/Pro` 等模型推理過程輸出

### 官網鏡像 功能
> - [x] 支持官網原生鏡像
> - [x] 後台賬號池隨機抽取，`Seed` 設置隨機賬號
> - [x] 輸入 `RefreshToken` 或 `AccessToken` 直接登錄使用
> - [x] 支持 `O3-mini/high`、`O1/mini/Pro`、`GPT-4/4o/mini`
> - [x] 敏感信息接口禁用、部分設置接口禁用
> - [x] /login 登錄頁面，註銷後自動跳轉到登錄頁面
> - [x] /?token=xxx 直接登錄, xxx 為 `RefreshToken` 或 `AccessToken` 或 `SeedToken` (隨機種子)
> - [x] 支持不同 SeedToken 會話隔離
> - [x] 支持 `GPTs` 商店
> - [x] 支持 `DeepReaserch`、`Canvas` 等官網獨有功能
> - [x] 支持切換各國語言


> TODO
> - [ ] 暫無，歡迎提 `issue`

## 逆向API

完全 `OpenAI` 格式的 API ，支持傳入 `AccessToken` 或 `RefreshToken`，可用 GPT-4, GPT-4o, GPT-4o-Mini, GPTs, O1-Pro, O1, O1-Mini, O3-Mini, O3-Mini-High：

```bash
curl --location 'http://127.0.0.1:5005/v1/chat/completions' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer {{Token}}' \
--data '{
     "model": "gpt-3.5-turbo",
     "messages": [{"role": "user", "content": "Say this is a test!"}],
     "stream": true
   }'
```

將你賬號的 `AccessToken` 或 `RefreshToken` 作為 `{{ Token }}` 傳入。
也可填寫你設置的環境變量 `Authorization` 的值, 將會隨機選擇後台賬號

如果有team賬號，可以傳入 `ChatGPT-Account-ID`，使用 Team 工作區：

- 傳入方式一：
`headers` 中傳入 `ChatGPT-Account-ID`值

- 傳入方式二：
`Authorization: Bearer <AccessToken 或 RefreshToken>,<ChatGPT-Account-ID>`

如果設置了 `AUTHORIZATION` 環境變量，可以將設置的值作為 `{{ Token }}` 傳入進行多 Tokens 輪詢。

> - `AccessToken` 獲取: chatgpt官網登錄後，再打開 [https://chatgpt.com/api/auth/session](https://chatgpt.com/api/auth/session) 獲取 `accessToken` 這個值。
> - `RefreshToken` 獲取: 此處不提供獲取方法。
> - 免登錄 gpt-3.5 無需傳入 Token。

## Tokens 管理

1. 配置環境變量 `AUTHORIZATION` 作為 `授權碼` ，然後運行程序。

2. 訪問 `/tokens` 或者 `/{api_prefix}/tokens` 可以查看現有 Tokens 數量，也可以上傳新的 Tokens ，或者清空 Tokens。

3. 請求時傳入 `AUTHORIZATION` 中配置的 `授權碼` 即可使用輪詢的Tokens進行對話

![tokens.png](docs/tokens.png)

## 官網原生鏡像

1. 配置環境變量 `ENABLE_GATEWAY` 為 `true`，然後運行程序, 注意開啓後別人也可以直接通過域名訪問你的網關。

2. 在 Tokens 管理頁面上傳 `RefreshToken` 或 `AccessToken`

3. 訪問 `/login` 到登錄頁面

![login.png](docs/login.png)

4. 進入官網原生鏡像頁面使用

![chatgpt.png](docs/chatgpt.png)

## 環境變量

每個環境變量都有默認值，如果不懂環境變量的含義，請不要設置，更不要傳空值，字符串無需引號。

| 分類   | 變量名               | 示例值                                                         | 默認值                   | 描述                                                           |
|------|-------------------|-------------------------------------------------------------|-----------------------|--------------------------------------------------------------|
| 安全相關 | API_PREFIX        | `your_prefix`                                               | `None`                | API 前綴密碼，不設置容易被人訪問，設置後需請求 `/your_prefix/v1/chat/completions` |
|      | AUTHORIZATION     | `your_first_authorization`,<br/>`your_second_authorization` | `[]`                  | 你自己為使用多賬號輪詢 Tokens 設置的授權碼，英文逗號分隔                             |
|      | AUTH_KEY          | `your_auth_key`                                             | `None`                | 私人網關需要加`auth_key`請求頭才設置該項                                    |
| 請求相關 | CHATGPT_BASE_URL  | `https://chatgpt.com`                                       | `https://chatgpt.com` | ChatGPT 網關地址，設置後會改變請求的網站，多個網關用逗號分隔                           |
|      | PROXY_URL         | `http://ip:port`,<br/>`http://username:password@ip:port`    | `[]`                  | 全局代理 URL，出 403 時啓用，多個代理用逗號分隔                                 |
|      | EXPORT_PROXY_URL  | `http://ip:port`或<br/>`http://username:password@ip:port`    | `None`                | 出口代理 URL，防止請求圖片和文件時泄漏源站 ip                                   |
| 功能相關 | HISTORY_DISABLED  | `true`                                                      | `true`                | 是否不保存聊天記錄並返回 conversation_id                                 |
|      | POW_DIFFICULTY    | `00003a`                                                    | `00003a`              | 要解決的工作量證明難度，不懂別設置                                            |
|      | RETRY_TIMES       | `3`                                                         | `3`                   | 出錯重試次數，使用 `AUTHORIZATION` 會自動隨機/輪詢下一個賬號                      |
|      | CONVERSATION_ONLY | `false`                                                     | `false`               | 是否直接使用對話接口，如果你用的網關支持自動解決 `POW` 才啓用                           |
|      | ENABLE_LIMIT      | `true`                                                      | `true`                | 開啓後不嘗試突破官方次數限制，儘可能防止封號                                       |
|      | UPLOAD_BY_URL     | `false`                                                     | `false`               | 開啓後按照 `URL+空格+正文` 進行對話，自動解析 URL 內容並上傳，多個 URL 用空格分隔           |
|      | SCHEDULED_REFRESH | `false`                                                     | `false`               | 是否定時刷新 `AccessToken` ，開啓後每次啓動程序將會全部非強制刷新一次，每4天晚上3點全部強制刷新一次。  |
|      | RANDOM_TOKEN      | `true`                                                      | `true`                | 是否隨機選取後台 `Token` ，開啓後隨機後台賬號，關閉後為順序輪詢                         |
| 網關功能 | ENABLE_GATEWAY    | `false`                                                     | `false`               | 是否啓用網關模式，開啓後可以使用鏡像站，但也將會不設防                                  |
|      | AUTO_SEED          | `false`                                                     | `true`               | 是否啓用隨機賬號模式，默認啓用，輸入`seed`後隨機匹配後台`Token`。關閉之後需要手動對接接口，來進行`Token`管控。    |

## 部署

### Zeabur 部署

[![Deploy on Zeabur](https://zeabur.com/button.svg)](https://zeabur.com/templates/6HEGIZ?referralCode=LanQian528)

### 直接部署

```bash
git clone https://github.com/LanQian528/chat2api
cd chat2api
pip install -r requirements.txt
python app.py
```

### Docker 部署

您需要安裝 Docker 和 Docker Compose。

```bash
docker run -d \
  --name chat2api \
  -p 5005:5005 \
  lanqian528/chat2api:latest
```

### (推薦，可用 PLUS 賬號) Docker Compose 部署

創建一個新的目錄，例如 chat2api，並進入該目錄：

```bash
mkdir chat2api
cd chat2api
```

在此目錄中下載庫中的 docker-compose.yml 文件：

```bash
wget https://raw.githubusercontent.com/LanQian528/chat2api/main/docker-compose-warp.yml
```

修改 docker-compose-warp.yml 文件中的環境變量，保存後：

```bash
docker-compose up -d
```


## 常見問題

> - 錯誤代碼：
>   - `401`：當前 IP 不支持免登錄，請嘗試更換 IP 地址，或者在環境變量 `PROXY_URL` 中設置代理，或者你的身份驗證失敗。
>   - `403`：請在日誌中查看具體報錯信息。
>   - `429`：當前 IP 請求1小時內請求超過限制，請稍後再試，或更換 IP。
>   - `500`：服務器內部錯誤，請求失敗。
>   - `502`：服務器網關錯誤，或網絡不可用，請嘗試更換網絡環境。

> - 已知情況：
>   - 日本 IP 很多不支持免登，免登 GPT-3.5 建議使用美國 IP。
>   - 99%的賬號都支持免費 `GPT-4o` ，但根據 IP 地區開啓，目前日本和新加坡 IP 已知開啓概率較大。

> - 環境變量 `AUTHORIZATION` 是什麼？
>   - 是一個自己給 chat2api 設置的一個身份驗證，設置後才可使用已保存的 Tokens 輪詢，請求時當作 `APIKEY` 傳入。
> - AccessToken 如何獲取？
>   - chatgpt官網登錄後，再打開 [https://chatgpt.com/api/auth/session](https://chatgpt.com/api/auth/session) 獲取 `accessToken` 這個值。


## License

MIT License

