當然可以！以下是**依照您貼的順序**，詳細說明 Ollama 伺服器環境變數的功能、推薦設法、與實務備註（含設定範例），全部用表格方式呈現。

---

### Ollama 主要環境變數說明表

| 參數名稱                        | 功能說明                                         | 設定範例/建議                                          | 實務備註 / 什麼情境要改                  |
| --------------------------- | -------------------------------------------- | ------------------------------------------------ | ------------------------------ |
| CUDA\_VISIBLE\_DEVICES      | 指定可用的 NVIDIA GPU 卡號                          | `export CUDA_VISIBLE_DEVICES=0,1`                | 多卡主機只給 Ollama 用某幾張卡            |
| GPU\_DEVICE\_ORDINAL        | 類似 CUDA\_VISIBLE\_DEVICES，指定 GPU 卡序號（不同架構時用） | `export GPU_DEVICE_ORDINAL=0,1`                  | 一般用 CUDA\_VISIBLE\_DEVICES 較常見 |
| HIP\_VISIBLE\_DEVICES       | 指定可用 AMD GPU                                 | `export HIP_VISIBLE_DEVICES=0,1`                 | ROCm/AMD 平台才用                  |
| HSA\_OVERRIDE\_GFX\_VERSION | 強制覆蓋 AMD GPU GFX 版本（進階）                      | `export HSA_OVERRIDE_GFX_VERSION=10.3.0`         | 極少用到，AMD ROCm 專用               |
| HTTPS\_PROXY / HTTP\_PROXY  | 設定 HTTP/HTTPS 代理                             | `export HTTP_PROXY=http://proxy:8080`            | 企業/學校內網需代理上網時                  |
| NO\_PROXY                   | 指定不經過代理的網域清單                                 | `export NO_PROXY=localhost,127.0.0.1`            | 常和 HTTP\_PROXY 搭配              |
| OLLAMA\_CONTEXT\_LENGTH     | 單請求最大上下文長度（input+output token 總數）            | `export OLLAMA_CONTEXT_LENGTH=40960`             | 大模型長文本要用，預設 4096，記憶體夠可調大       |
| OLLAMA\_DEBUG               | Log 等級（INFO, DEBUG）                          | `export OLLAMA_DEBUG=DEBUG`                      | 想看詳細 log 或 debug 問題時開          |
| OLLAMA\_FLASH\_ATTENTION    | 是否啟用 FlashAttention（提升推理速度）                  | `export OLLAMA_FLASH_ATTENTION=true`             | 預設 true，建議保持                   |
| OLLAMA\_GPU\_OVERHEAD       | GPU 記憶體保留百分比，避免爆卡                            | `export OLLAMA_GPU_OVERHEAD=10`                  | 預設 10%，若常 OOM 可調高              |
| OLLAMA\_HOST                | 伺服器綁定 IP/PORT                                | `export OLLAMA_HOST=http://0.0.0.0:11434`        | 本機或網路服務自訂                      |
| OLLAMA\_INTEL\_GPU          | 是否使用 Intel GPU                               | `export OLLAMA_INTEL_GPU=true`                   | 用 Intel GPU 時設 true，否則 false   |
| OLLAMA\_KEEP\_ALIVE         | 伺服器 idle 保活時間                                | `export OLLAMA_KEEP_ALIVE=1h0m0s`                | 離線後多久自動關閉                      |
| OLLAMA\_KV\_CACHE\_TYPE     | KV cache 儲存類型（ram, disk）                     | `export OLLAMA_KV_CACHE_TYPE=ram`                | 一般不用改，高階效能調校                   |
| OLLAMA\_LLM\_LIBRARY        | 指定 LLM 後端（如 cuda、rocm）                       | `export OLLAMA_LLM_LIBRARY=cuda`                 | GPU 架構選擇                       |
| OLLAMA\_LOAD\_TIMEOUT       | 模型加載最大等待時間                                   | `export OLLAMA_LOAD_TIMEOUT=20m0s`               | 載大模型怕 timeout 可加大              |
| OLLAMA\_MAX\_LOADED\_MODELS | 同時常駐的模型數量上限                                  | `export OLLAMA_MAX_LOADED_MODELS=2`              | 多模型服務建議調高                      |
| OLLAMA\_MAX\_QUEUE          | 請求佇列長度                                       | `export OLLAMA_MAX_QUEUE=1024`                   | 高併發或服務多用戶調高                    |
| OLLAMA\_MODELS              | 模型資料夾路徑                                      | `export OLLAMA_MODELS=/models`                   | 更改模型儲存目錄時設                     |
| OLLAMA\_MULTIUSER\_CACHE    | 是否多用戶共用快取                                    | `export OLLAMA_MULTIUSER_CACHE=true`             | 多人共用才需設                        |
| OLLAMA\_NEW\_ENGINE         | 是否啟用新引擎（內部參數）                                | `export OLLAMA_NEW_ENGINE=true`                  | 正式環境預設即可                       |
| OLLAMA\_NOHISTORY           | 是否不保存歷史紀錄                                    | `export OLLAMA_NOHISTORY=true`                   | 隱私敏感、測試環境                      |
| OLLAMA\_NOPRUNE             | 不自動快取清理（實驗用）                                 | `export OLLAMA_NOPRUNE=true`                     | 測試或空間足夠時                       |
| OLLAMA\_NUM\_PARALLEL       | 同時推理/服務數量                                    | `export OLLAMA_NUM_PARALLEL=2`                   | 多人多任務時調高                       |
| OLLAMA\_ORIGINS             | CORS 白名單（允許網頁/域存取）                           | `export OLLAMA_ORIGINS="* http://localhost ..."` | 若 API 要給網頁用需設                  |
| OLLAMA\_SCHED\_SPREAD       | 啟用 worker 負載分散                               | `export OLLAMA_SCHED_SPREAD=true`                | 伺服器高併發環境可打開                    |
| ROCR\_VISIBLE\_DEVICES      | 指定可用 AMD GPU（ROCm）                           | `export ROCR_VISIBLE_DEVICES=0,1`                | 只在 AMD GPU/ROCm 架構需設           |
| http\_proxy / https\_proxy  | HTTP/HTTPS 代理                                | `export http_proxy=...`                          | 同上，與 HTTP\_PROXY 相同            |
| no\_proxy                   | 不用代理的網域清單                                    | `export no_proxy=...`                            | 同上，與 NO\_PROXY 相同              |

---

CUDA_VISIBLE_DEVICES: 
GPU_DEVICE_ORDINAL:0,1,2,3,4,5 
HIP_VISIBLE_DEVICES: 
HSA_OVERRIDE_GFX_VERSION: 
HTTPS_PROXY: 
HTTP_PROXY: 
NO_PROXY:
OLLAMA_CONTEXT_LENGTH:4096 
OLLAMA_DEBUG:INFO 
OLLAMA_FLASH_ATTENTION:true 
OLLAMA_GPU_OVERHEAD:10 
OLLAMA_HOST:http://0.0.0.0:11434 
OLLAMA_INTEL_GPU:false 
OLLAMA_KEEP_ALIVE:1h0m0s 
OLLAMA_KV_CACHE_TYPE: 
OLLAMA_LLM_LIBRARY:cuda 
OLLAMA_LOAD_TIMEOUT:20m0s 
OLLAMA_MAX_LOADED_MODELS:2 
OLLAMA_MAX_QUEUE:1024 
OLLAMA_MODELS:/models 
OLLAMA_MULTIUSER_CACHE:false 
OLLAMA_NEW_ENGINE:false 
OLLAMA_NOHISTORY:false 
OLLAMA_NOPRUNE:false 
OLLAMA_NUM_PARALLEL:1 
OLLAMA_ORIGINS:[* http://localhost https://localhost http://localhost:* https://localhost:* http://127.0.0.1 https://127.0.0.1 http://127.0.0.1:* https://127.0.0.1:* http://0.0.0.0 https://0.0.0.0 http://0.0.0.0:* https://0.0.0.0:* app://* file://* tauri://* vscode-webview://* vscode-file://*] 
OLLAMA_SCHED_SPREAD:true 
ROCR_VISIBLE_DEVICES: 
http_proxy: https_proxy: no_proxy:]"
