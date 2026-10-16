# 爆發技能近身施放

1.1.0 · ourongxing

讓帕魯靠近目標後，再使用熔岩爆發、岩爆與毒雨。

## 功能與使用

這三個技能需要接近目標至約 0.5 公尺內，才會由帕魯自動施放。技能威力、冷卻、攻擊範圍與傷害判定沿用原版。

## 安裝

1. 訂閱並啟用前置 Mod：UE4SSExperimentalPW, PalSchema。
2. 在遊戲的 Mod 管理中啟用本 Mod。
3. 完全退出遊戲，再重新啟動。

## 設定

在 Palworld 安裝目錄中編輯 `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json`，儲存後完全退出並重新啟動遊戲。

`MaxRange` 設定自動施放的最大距離，預設 50 個遊戲單位，約 0.5 公尺。

## 使用須知

與其他修改這三個技能施放距離的 Mod 同時啟用時，結果取決於載入順序。

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
