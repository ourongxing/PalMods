local M = {}
local language = "auto"
local messages = {
    ["zh-Hans"] = {
        confirm = "强化帕鲁", cost = "本次消耗：%s", cost_heading = "消耗的帕鲁魂", stock = "自动换算可用帕鲁魂，选择目标强化等级。",
        minimum = "回到当前已强化等级", maximum = "选择剩余帕鲁魂可支持的最高等级",
        tiers = { "小", "中", "大", "究极" }, failed = "强化未完成：%s", success = "帕鲁强化完成。",
        insufficient_souls = "帕鲁魂不足", backpack_full = "请腾出背包空位供帕鲁魂转换",
        disabled_after_error = "请重新进入游戏后检查帕鲁和库存", no_change = "请选择更高的强化等级",
        retry = "请重新选择帕鲁，并检查帕鲁魂库存", rollback_failed = "库存恢复失败，请退出并从备份恢复存档",
    },
    ["zh-Hant"] = {
        confirm = "強化帕魯", cost = "本次消耗：%s", cost_heading = "消耗的帕魯魂", stock = "自動換算可用帕魯魂，選擇目標強化等級。",
        minimum = "回到目前已強化等級", maximum = "選擇剩餘帕魯魂可支援的最高等級",
        tiers = { "小", "中", "大", "究極" }, failed = "強化未完成：%s", success = "帕魯強化完成。",
        insufficient_souls = "帕魯魂不足", backpack_full = "請騰出背包空位供帕魯魂轉換",
        disabled_after_error = "請重新進入遊戲後檢查帕魯和庫存", no_change = "請選擇更高的強化等級",
        retry = "請重新選擇帕魯，並檢查帕魯魂庫存", rollback_failed = "庫存恢復失敗，請退出並從備份恢復存檔",
    },
    en = {
        confirm = "Enhance Pal", cost = "Total cost: %s", cost_heading = "Pal Soul cost", stock = "Souls convert automatically. Select target enhancement ranks.",
        minimum = "Return to the current enhancement rank", maximum = "Select the highest affordable rank",
        tiers = { "Small", "Medium", "Large", "Giant" }, failed = "Enhancement failed: %s", success = "Pal enhanced.",
        insufficient_souls = "Not enough Pal Souls", backpack_full = "Free backpack slots for soul conversion",
        disabled_after_error = "Reload the world and check the Pal and inventory", no_change = "Select a higher enhancement rank",
        retry = "Select the Pal again and check your Pal Souls", rollback_failed = "Inventory restoration failed. Exit and restore a save backup",
    },
    ja = {
        confirm = "パルを強化", cost = "必要な合計：%s", cost_heading = "必要なパルソウル", stock = "パルソウルを自動変換します。強化先のランクを選んでください。",
        minimum = "現在の強化ランクに戻す", maximum = "残りのソウルで可能な最高ランクを選ぶ",
        tiers = { "小", "中", "大", "巨大" }, failed = "強化できませんでした：%s", success = "パルを強化しました。",
        insufficient_souls = "パルソウルが足りません", backpack_full = "ソウル変換用の空きスロットを確保してください",
        disabled_after_error = "ワールドを再読み込みし、パルと所持品を確認してください", no_change = "より高い強化ランクを選んでください",
        retry = "パルを選び直し、パルソウルの所持数を確認してください", rollback_failed = "所持品の復元に失敗しました。終了してセーブのバックアップを復元してください",
    },
}
function M.configure(value) language = value or "auto" end
local function strings()
    local tag = language
    if tag == "auto" then
        local ok, value = pcall(function()
            local system = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
            -- Palworld's language settings page reads GetCurrentCulture.
            local cultureOk, value = pcall(function() return system:GetCurrentCulture() end)
            if not cultureOk then value = system:GetCurrentLanguage() end
            return type(value) == "string" and value or value:ToString()
        end)
        tag = ok and tostring(value) or "en"
    end
    tag = tag:lower():gsub("_", "-")
    if tag:match("^zh%-hant") or tag == "zh-tw" or tag == "zh-hk" then return messages["zh-Hant"] end
    if tag:match("^zh") then return messages["zh-Hans"] end
    if tag:match("^ja") then return messages.ja end
    return messages.en
end
function M.text(key, ...)
    local message = strings()[key] or messages.en[key] or key
    return select("#", ...) > 0 and string.format(message, ...) or message
end
function M.cost(required)
    local parts = {}
    for i, id in ipairs(require("BetterPalSouls.Plan").items) do
        if required[id] > 0 then parts[#parts + 1] = strings().tiers[i] .. " ×" .. required[id] end
    end
    return M.text("cost", #parts > 0 and table.concat(parts, " · ") or "0")
end
function M.reason(reason)
    reason = tostring(reason)
    for _, key in ipairs({ "rollback_failed", "insufficient_souls", "backpack_full", "disabled_after_error", "no_change" }) do
        if reason:find(key, 1, true) then return M.text(key) end
    end
    return M.text("retry")
end
return M
