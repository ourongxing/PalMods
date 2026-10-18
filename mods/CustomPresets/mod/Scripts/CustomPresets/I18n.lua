local M = {}
local messages = {
    ["en"] = {
        unsaved = "Unsaved changes",
        title = "Preset name",
        appearance_presets = "Custom presets",
        save = "Save preset",
        add = "Save as new",
        delete = "Delete preset",
        saved = "Preset saved",
        none = "No preset selected",
        easy = "Easy",
        normal = "Normal",
        hard = "Hard",
        hardcore = "Hardcore",
        custom = "Custom",
        invalid_name = "Use 1–30 characters without line breaks",
    },
    ["zh-Hans"] = {
        unsaved = "未保存修改",
        title = "预设名称",
        appearance_presets = "自定义预设",
        save = "保存当前预设",
        add = "添加为新预设",
        delete = "删除预设",
        saved = "当前预设已保存",
        none = "未选择预设",
        easy = "简单",
        normal = "普通",
        hard = "困难",
        hardcore = "硬核",
        custom = "自定义",
        invalid_name = "名称需为 1–30 个字符，不能包含换行",
    },
    ["zh-Hant"] = {
        unsaved = "尚未儲存",
        title = "預設名稱",
        appearance_presets = "自訂預設",
        save = "儲存目前預設",
        add = "新增為預設",
        delete = "刪除預設",
        saved = "目前預設已儲存",
        none = "未選擇預設",
        easy = "簡單",
        normal = "普通",
        hard = "困難",
        hardcore = "硬核",
        custom = "自訂",
        invalid_name = "名稱需為 1–30 個字元，不能包含換行",
    },
    ["ja"] = {
        unsaved = "未保存の変更",
        title = "プリセット名",
        appearance_presets = "カスタムプリセット",
        save = "上書き保存",
        add = "新規保存",
        delete = "削除",
        saved = "保存しました",
        none = "未選択",
        easy = "カジュアル",
        normal = "ノーマル",
        hard = "ハード",
        hardcore = "ハードコア",
        custom = "カスタム",
        invalid_name = "改行を含めず1～30文字で入力してください",
    },
}
local function strings()
    local ok, value = pcall(function()
        local system = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
        -- Palworld's language settings page reads GetCurrentCulture.
        local cultureOk, value = pcall(function() return system:GetCurrentCulture() end)
        if not cultureOk then value = system:GetCurrentLanguage() end
        return type(value) == "string" and value or value:ToString()
    end)
    local tag = ok and tostring(value) or "en"
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
return M
