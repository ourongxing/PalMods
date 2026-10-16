# 更好的工作台

1.0.0 · ourongxing

在同一座工作台自動計算缺少的中間素材，捲動查看完整素材清單，並將成品即時分解為原材料。

## 功能與使用

- 製作時優先使用已有的中間素材，僅將不足的部分繼續展開為目前工作台已解鎖配方的原料。無法使用其他工作台的配方。
- 例如需要 3 個鐵錠、已有 1 個時，若同一工作台可製作鐵錠，就使用這 1 個鐵錠與製作剩餘 2 個所需的礦石。
- 素材清單預設顯示 5 行，素材較多時可用滑鼠滾輪查看。
- 點選配方詳情右上角的成品持有數量，切換製作／分解模式。選擇批次數並確認後，按完整配方批次消耗成品，原配方素材全數返還背包。
- 單次製作最多 256 批。製作時間依所選成品配方計算，不額外增加中間素材的製作時間。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/BetterWorkbench/Scripts/config.lua`，儲存後完全退出並重新啟動遊戲。

- `Enabled`：開啟或關閉功能。
- `MaterialScroll.Enabled`、`MaterialScroll.VisibleRows`：開啟素材清單捲動、設定顯示行數。
- `Disassembly.Enabled`：開啟或關閉即時分解。
- `Disassembly.Language`：預設 `auto`，跟隨遊戲語言；也可指定 `zh-Hans`、`zh-Hant`、`ja` 或 `en`。道具名稱使用遊戲譯名。

## 使用須知

分解僅支援單人遊戲與連線房主本人。多人製作任務同步尚未支援。

道具扣除、素材返還、儲存後還原與控制器操作尚未完成遊戲內驗證。備份或移轉存檔時，請同時保留本 Mod 目錄下的 `Jobs` 資料夾，其中儲存未完成製作任務所需的資料。

## 問題回報

請到 GitHub Issues 回報問題：https://github.com/ourongxing/PalMods/issues

沒有 UE4SS 日誌，我無法定位並修復 Bug。

請提供以下資訊，方便查明原因：

- Mod 名稱、遊戲與 Mod 版本、遊戲語言。
- 單人遊戲、連線房主、加入他人房間或專用伺服器。
- 重現步驟、預期與實際情況，以及相關截圖和已啟用的其他 Mod。
- 發生問題後的完整 `UE4SS.log` 檔案，請以附件上傳。

在 Steam 中以右鍵點選 Palworld → 管理 → 瀏覽本機檔案，然後開啟 `Mods\NativeMods\UE4SS\UE4SS.log`。
例如，遊戲安裝在 G 槽時，完整路徑為：
`G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\UE4SS.log`

磁碟代號和 Steam 收藏庫目錄請依實際安裝位置調整。請在再次啟動遊戲前複製日誌，避免本次問題的紀錄被覆蓋。

## 開放原始碼

本 Mod 以 GPL-3.0 授權開放原始碼。
https://github.com/ourongxing/PalMods
