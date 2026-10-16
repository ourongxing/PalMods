# 更好的帕魯魂強化

1.0.0 · ourongxing

在力量石像的原版強化介面快速選擇強化等級，並自動兌換本次強化需要的帕魯魂。

## 功能與使用

- ◀：取消該屬性尚未確認的強化選擇，回到目前已強化等級；不會重置屬性或退還已花費的魂。
- ▶：選擇剩餘魂數量允許的最高等級，同時為其他屬性已選的強化保留用量。
- 原版 − / +：逐級調整。四項屬性共用可用帕魯魂，費用仍顯示於原版介面中。

小型、中型、大型、究極帕魯魂依 1 / 2 / 4 / 8 換算。預覽不改變庫存；確認強化時自動兌換所需魂，餘量全部保留為小型魂。

可使用玩家背包和目前據點中原版強化介面允許使用的容器。轉換需要背包空位，空間不足時請先騰出空位。強化效果、等級上限與消耗沿用遊戲設定，重置頁面照常使用。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/BetterPalSouls/Scripts/config.lua`，儲存後完全退出並重新啟動遊戲。

- `Enabled`：開啟或關閉功能。
- `Language`：預設 `auto`，跟隨遊戲語言；也可指定 `zh-Hans`、`zh-Hant`、`ja` 或 `en`。

## 使用須知

僅支援單人遊戲與連線房主本人，不支援加入他人房間的玩家或專用伺服器。

強化確認、儲存與重新讀取、操作失敗後的還原、控制器操作尚未完成遊戲內驗證。首次使用前請備份存檔。

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
