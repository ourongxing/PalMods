-- Item names are provided by PalUIUtility, preserving the game's translations.
local M = {}
local override = "auto"
local strings = {
    ["zh-Hant"] = {
        start = "開始分解", title = "分解 · %s",
        backpack_full = "背包空間不足，請先騰出空間。",
        insufficient_products = "持有的成品不足。",
        disassembly_in_progress = "正在分解，請稍候。",
        disassembly_disabled_after_inventory_error = "已停止分解。請重新啟動遊戲並檢查背包。",
        retry = "請檢查背包，並重新開啟工作台。",
        failed = "無法分解：%s", consumed = "已分解 %s × %d",
        returned = "返還素材：%s", separator = "、",
        complete = "分解完成，原配方的素材已全數返還至背包。",
    },
    en = {
        start = "Start Disassembly", title = "Disassemble: %s",
        backpack_full = "Not enough inventory space. Free up some space first.",
        insufficient_products = "Not enough items to disassemble.",
        disassembly_in_progress = "Disassembly in progress. Please wait.",
        disassembly_disabled_after_inventory_error = "Disassembly has been stopped. Restart the game and check your inventory.",
        retry = "Check your inventory, then reopen the crafting station.",
        failed = "Unable to disassemble: %s", consumed = "Disassembled %s × %d",
        returned = "Materials returned: %s", separator = ", ",
        complete = "Disassembly complete. All recipe materials have been returned to your inventory.",
    },
    ja = {
        start = "分解を開始", title = "分解：%s",
        backpack_full = "インベントリに空きがありません。空きを作ってから再度お試しください。",
        insufficient_products = "分解するアイテムが足りません。",
        disassembly_in_progress = "分解中です。しばらくお待ちください。",
        disassembly_disabled_after_inventory_error = "分解を停止しました。ゲームを再起動し、インベントリを確認してください。",
        retry = "インベントリを確認し、作業台の画面を開き直してください。",
        failed = "分解できません：%s", consumed = "%s × %d を分解しました",
        returned = "返却した素材：%s", separator = "、",
        complete = "分解が完了しました。レシピの素材をすべてインベントリに返却しました。",
    },
    ["zh-Hans"] = {
        start = "开始分解", title = "分解 · %s",
        backpack_full = "背包空间不足，请先腾出空间。",
        insufficient_products = "已有成品不足。",
        disassembly_in_progress = "正在分解，请稍候。",
        disassembly_disabled_after_inventory_error = "分解已停止，请重新进入游戏后检查背包。",
        retry = "请检查背包并重新打开工作台。",
        failed = "分解失败：%s", consumed = "已分解 %s × %d",
        returned = "返还：%s", separator = "、",
        complete = "分解完成，原始材料已全额返还到背包。",
    },
}

function M.normalize(language)
    local tag = tostring(language or ""):lower():gsub("_", "-")
    -- Explicit script tags take precedence over region aliases.
    if tag == "zh-hant" or tag:match("^zh%-hant%-") then return "zh-Hant" end
    if tag == "zh-hans" or tag:match("^zh%-hans%-") then return "zh-Hans" end
    if tag == "zh-tw" or tag == "zh-hk" or tag == "zh-mo" then return "zh-Hant" end
    if tag == "zh" or tag:match("^zh%-") then return "zh-Hans" end
    if tag == "ja" or tag:match("^ja%-") then return "ja" end
    return "en"
end

function M.configure(language) override = language or "auto" end

function M.language()
    if override ~= "auto" then return M.normalize(override) end
    local ok, language = pcall(function()
        local result = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary"):GetCurrentLanguage()
        return type(result) == "string" and result or result:ToString()
    end)
    return M.normalize(ok and language or "en")
end

function M.text(key, ...)
    local message = assert(strings[M.language()][key] or strings.en[key], "Unknown translation: " .. key)
    if select("#", ...) == 0 then return message end
    return string.format(message, ...)
end

return M
