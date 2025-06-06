
#### 建立服務檔：ollama.service (GPU0)
```bash
sudo nano /etc/systemd/system/ollama.service
```
#### 內容：
```ini
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
Environment="OLLAMA_HOST=0.0.0.0:11434"
LimitNOFILE=65535
Environment="OLLAMA_NUM_GPU_LAYERS=100"
Environment="CUDA_VISIBLE_DEVICES=0,1,2,3"
Environment="OLLAMA_SCHED_SPREAD=1"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_HOST=0.0.0.0"


[Install]
WantedBy=default.target
```
#### 啟動服務檔：
```bash
sudo systemctl daemon-reload
sudo systemctl enable ollama.service
sudo systemctl start ollama.service
```

#### 檢查服務狀態
```bash
sudo systemctl status ollama.service
```

