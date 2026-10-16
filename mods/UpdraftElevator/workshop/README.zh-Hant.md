# 上升氣流

1.1.0 · ourongxing

建造上升氣流，在氣流範圍內按跳躍鍵，透過原版氣流的起跳動畫升空。

## 功能與使用

- 小型：預設升空高度 8 公尺，範圍直徑 2 公尺。
- 中型：預設升空高度 16 公尺，範圍直徑 4 公尺。
- 大型：預設升空高度 32 公尺，範圍直徑 6 公尺。
- 範圍重疊時，採用最高一檔的升空高度。

在第 9 級古代科技中花費 1 點古代科技點，一次解鎖三種尺寸。每座建築需要 10 個帕魯礦碎片、30 個石頭和 3 個古代文明部件。

在建造選單的「基礎設施／上升氣流」分類中放置。建築完成後透明；拆除時進入拆除模式，瞄準氣流下部的底座。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW, PalSchema。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/UpdraftElevator/Scripts/config.lua`，儲存後完全退出並重新啟動遊戲。

`Small`、`Medium`、`Large` 分別設定三種尺寸的升空高度，單位為公尺，預設值為 8、16、32。支援 0.1～1000 及小數，無效數值使用預設值。

建築與科技文字支援簡體中文、繁體中文、日語和英語，其他語言使用英語。切換語言後請重新啟動遊戲。

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
