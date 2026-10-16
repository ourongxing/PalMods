# 隨處開啟終端

1.0.0 · ourongxing

按 K 隨處開啟原版帕魯終端，在野外與地下城也能查看、整理及調整帕魯。

## 功能與使用

- 在自己公會的據點內，開啟目前據點的終端。
- 在野外或地下城，開啟公會中建築物最多的據點終端；建築數相同時選擇距離玩家最近的據點，每次按鍵重新選擇。
- 公會需要已有據點，且對應終端可用。
- 位於其他公會據點內時不會開啟終端。
- 使用原版終端介面；其他選單開啟、畫面切換或玩家尚未就緒時，按鍵不生效。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/AnywherePalBox/Scripts/config.lua`，儲存後完全退出並重新啟動遊戲。

`Hotkey = "K"` 設定快捷鍵，可改為 `"J"`、`"F6"` 等單一按鍵，不區分大小寫。設定缺失或無效時使用 K。

## 使用須知

已在單人遊戲中測試，包括地下城。多人遊戲尚未驗證。

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
