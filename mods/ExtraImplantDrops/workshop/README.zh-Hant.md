# 植入體掉落

1.0.0 · ourongxing

帕魯死亡或被肢解時，有機率額外掉落與其詞條對應的植入體。

## 功能與使用

- 支援 28 種植入體，每種符合條件的詞條獨立判定掉落。
- 預設掉落機率為 50%，基礎數量為 1。
- 數量受遊戲掉落加成與世界設定影響。
- 保留原有材料掉落。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/ExtraImplantDrops/config.ini`，儲存後完全退出並重新啟動遊戲。

- `[Harvest]` 中的 `DropChance=0.5`：掉落機率，範圍 0～1；0 為不掉落，1 為必定通過機率判定。
- `[Implants]`：依詞條分別設定植入體掉落，1 開啟、0 關閉。開啟後仍需通過機率判定。

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
