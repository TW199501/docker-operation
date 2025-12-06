# Debian 13 VM Script – Merge Plan

> 目標：把 `1.sh` 與新的 `debian13-vm.sh` 各自的優點整合，再逐步實作；每完成一項就勾掉。

## 0. Baseline

- [x] 建立 `feature/debian13-merge` 分支（若已有分支可跳過）
- [x] 以新版 `debian13-vm.sh` 為主幹，備份舊版 `1.sh` 供參考

## 1. 儲存類型支援

- [x] 從 `1.sh` 取回 `zfs/zfspool/lvm/lvm-thin` case 區段，補回 `debian13-vm.sh`
- [x] 確保 `zfspool` 使用 `vm-<id>-disk-*`（無副檔名），其他類型依資料夾/副檔名設定
- [x] 針對不存在的類型給 `msg_error` 並終止

## 2. Docker / virt-customize 選項

- [x] 保留新腳本預設「不安裝 Docker」，但增加互動選項（yes/no）決定是否在匯入前灌
- [x] 重新加入 `virt-customize` 流程（含 `qemu-guest-agent`），沿用 `1.sh` 的指令
- [x] 在執行前導入 `LIBGUESTFS_RESOLV_CONF` 參數（可讀 `.env` 或 fallback `/etc/resolv.conf`）
- [x] 若 `virt-customize` 任一步驟失敗，`msg_error` 並 `exit 1`，不要印成功訊息

## 3. Cloud-init 與映像選擇

- [x] 保留新版的 cloud-init 切換（genericcloud vs nocloud）
- [x] 互動流程中同時顯示「是否配置 Cloud-init」與「是否預裝 Docker」，避免互斥
- [x] `QM` 指令依 Cloud-init 選項決定是否掛 `scsi1 …:cloudinit`

## 4. 預設值與互動提示

- [x] 讓預設資源（disk=10G、RAM=4096、hostname=docker）回到 `1.sh` 的設定，同時允許使用者修改
- [x] 對新加入的選項（Docker install、Cloud-init）在 default/advanced 兩模式都要提示
- [x] 調整描述與標籤：可保留 community 版的 `description` HTML，但改成中性內容（選填）

## 5. 測試與文件

- [ ] 在 PVE 9.1.x（含 zfs 與 lvm 儲存）各跑一次：`INSTALL_DOCKER=yes/no`、`CLOUD_INIT=yes/no`
- [ ] 若 `virt-customize` 需特定 resolv conf，把使用方式寫到 README 或註解
- [ ] 測試完成後勾選以上項目，最後由 TODO.md 刪除或移到 DONE 區塊
