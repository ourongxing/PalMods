-- Read-only discovery. Does not alter params, return values, recipes or inventory.
local Diagnostics = {}
local StationScope = require("BetterWorkbench.StationScope")
local NativeMaterialView = require("BetterWorkbench.NativeMaterialView")
local NativeCounts = require("BetterWorkbench.NativeCounts")
local classes = {
    "/Script/Pal.PalUIConvertItemModel",
    "/Script/Pal.PalMapObjectConvertItemModel",
    "/Script/Pal.PalMapObjectProductItemModel",
    "/Script/Pal.PalMasterDataTableAccess_ItemRecipe",
    "/Script/Pal.PalItemUtility",
    "/Game/Pal/Blueprint/UI/CovertItemMenu/WBP_PalConvertItemMenu_RecipeSlotButton.WBP_PalConvertItemMenu_RecipeSlotButton_C",
}

local names = {
    Initialize = true, SelectRecipe = true, SetFocusedRecipe = true,
    GetRecipe = true, GetCurrentRecipe = true, GetCurrentRecipeId = true,
    GetRecipes = true, RequestStart = true, RequestStartProduct_ServerInternal = true,
    ChangeRecipe_ServerInternal = true, Cancel_ServerInternal = true,
    Setup = true, SetupProductItemInfo = true, UpdateSufficient = true,
    BP_FindRow = true,
    StartProduction = true, CanStartProduction = true, CalcRequiredAmount = true,
    OnFinishWorkInServer = true, PickupProduct_ServerInternal = true,
}

local frequent = {
    GetCurrentRecipe = true, GetCurrentRecipeId = true, BP_FindRow = true,
    UpdateSufficient = true, CanStartProduction = true, CalcRequiredAmount = true,
}

local fields = {
    SelectedRecipeId = true, FocusedRecipeId = true, CurrentRecipeId = true,
    RequestedProductNum = true, RecipeRequiredItemsOverrideMap = true,
    SelectedProductNum = true,
    RecipeId = true, Sufficient = true,
    RecipeID = true, RemainProductNum = true, bIsWorkable = true,
}

local function valid(object)
    local ok, result = pcall(function() return object ~= nil and object:IsValid() end)
    return ok and result == true
end

local function clean(value)
    return tostring(value):gsub("[\r\n]", " "):sub(1, 220)
end

local function describe(value)
    local kind = type(value)
    if kind == "nil" or kind == "number" or kind == "boolean" or kind == "string" then
        return clean(value)
    end
    local ok, text = pcall(function() return value:ToString() end)
    if ok and type(text) == "string" then return clean(text) end
    if valid(value) then
        ok, text = pcall(function() return value:GetFullName() end)
        if ok then return clean(text) end
    end
    return "<" .. kind .. ">"
end

local function unwrap(value)
    if type(value) ~= "userdata" and type(value) ~= "table" then return value end
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end
    return value
end

function Diagnostics.start(config, api)
    config = config or {}
    api = api or _G
    if config.Enabled == false then return nil, "disabled" end
    if type(api.StaticFindObject) ~= "function" or type(api.RegisterHook) ~= "function"
        or type(api.ExecuteInGameThread) ~= "function" then
        return nil, "UE4SS discovery API is unavailable"
    end
    local maxHits = config.MaxHitsPerHook or 12
    local maxTotal = config.MaxTotalHits or 150
    local focus = config.FocusRecipes
    local focusItems = config.FocusItems
    local setupVisits = 0
    local maxSetupVisits = config.MaxSetupVisits or 600
    assert(type(maxSetupVisits) == "number" and maxSetupVisits % 1 == 0
        and maxSetupVisits >= 1 and maxSetupVisits <= 1000, "invalid MaxSetupVisits")
    if focus then
        assert(type(focus) == "table", "invalid FocusRecipes")
        for id, enabled in pairs(focus) do
            assert(type(id) == "string" and id ~= "" and enabled == true, "invalid focus recipe")
        end
    end
    if focusItems then
        assert(type(focusItems) == "table" and #focusItems >= 1 and #focusItems <= 8, "invalid FocusItems")
        for _, id in ipairs(focusItems) do
            assert(type(id) == "string" and id ~= "" and id ~= "None", "invalid focus item")
        end
    end
    assert(type(maxHits) == "number" and maxHits >= 1 and maxHits <= 100, "invalid MaxHitsPerHook")
    assert(type(maxTotal) == "number" and maxTotal >= 1 and maxTotal <= 1000, "invalid MaxTotalHits")
    local state = { seen = {}, hooks = {}, hits = {}, total = 0, polls = 0, stopped = false, uiCountsSeen = {},
        paths = {}, known = {} }
    for _, path in ipairs(classes) do
        state.paths[#state.paths + 1] = path
        state.known[path] = true
    end
    local function log(message)
        api.print("[BetterWorkbench:Probe] " .. message .. "\n")
    end
    -- MaterialAudit is quarantined after a native access violation. Do not load
    -- it or read recipe return structs / enumerate inventory from callbacks.
    local function hook(path, argNames, propertyNames, nameArrayReturn, materialArray)
        if state.hooks[path] then return end
        local functionName = path:match(":([^:]+)$")
        local hitLimit = frequent[functionName] and math.min(maxHits, 3) or maxHits
        local function callback(phase, context, ...)
            local hitKey = path .. ":" .. phase
            if state.stopped or state.total >= maxTotal or (state.hits[hitKey] or 0) >= hitLimit then return end
            if focus and functionName == "Setup" and materialArray then
                -- Bounded FName-only filtering: unrelated buttons cannot spend
                -- the material sample budget before the requested recipes appear.
                if setupVisits >= maxSetupVisits then return end
                setupVisits = setupVisits + 1
                local first = select(1, ...)
                local ok, id = pcall(function()
                    local recipe = unwrap(first)
                    assert(recipe:type() == "FName", "focus recipe is not FName")
                    return recipe:ToString()
                end)
                if not ok then log("focus filter unavailable: " .. clean(id)); return end
                if focus[id] ~= true then return end
            end
            state.hits[hitKey] = (state.hits[hitKey] or 0) + 1
            state.total = state.total + 1
            local args = table.pack(...)
            local ordered = argNames
            -- Installed UE4SS pushes the return value FIRST in native post hooks.
            if phase == "POST" then
                ordered = {}
                for _, label in ipairs(argNames) do
                    if label == "ReturnValue" then ordered[#ordered + 1] = label end
                end
                for _, label in ipairs(argNames) do
                    if label ~= "ReturnValue" then ordered[#ordered + 1] = label end
                end
            end
            local ok, err = pcall(function()
                local parts = {}
                for index = 1, args.n do
                    parts[#parts + 1] = (ordered[index] or ("arg" .. index)) .. "=" .. describe(unwrap(args[index]))
                end
                local object = unwrap(context)
                if focusItems and state.inventory and (functionName == "ChangeRecipe_ServerInternal"
                    or functionName == "Cancel_ServerInternal" or functionName == "PickupProduct_ServerInternal") then
                    -- Only verified scalar queries; no slot scans, native arrays,
                    -- borrowed result structures, or inventory mutations.
                    local counts, problem = state.inventory:read(object, focusItems)
                    if counts then
                        local rows = {}
                        for _, id in ipairs(focusItems) do
                            rows[#rows + 1] = id .. ":player=" .. counts.PlayerInventory[id]
                                .. ":base_query=" .. counts.InsideBase[id]
                        end
                        log("FOCUS_COUNTS phase=" .. phase .. " event=" .. functionName
                            .. " model=" .. describe(object) .. " values=" .. table.concat(rows, ",")
                            .. " authority=unverified")
                    elseif problem then log("inventory query disabled: " .. clean(problem)) end
                end
                if phase == "POST" and functionName == "GetRecipes" and nameArrayReturn then
                    -- Diagnostic observation only. Future commits must fetch a
                    -- fresh authoritative station scope, never this log sample.
                    local ids, count = StationScope.copyNames(unwrap(args[1]))
                    local list = {}
                    for id in pairs(ids) do list[#list + 1] = id end
                    table.sort(list)
                    log("STATION_RECIPES model=" .. describe(object) .. " count=" .. count
                        .. " ids=" .. table.concat(list, ","))
                end
                if phase == "CALL" and functionName == "Setup" and materialArray then
                    -- The Blueprint callback runs after Setup; MatInfo is borrowed
                    -- only for this callback. This is demand, NOT inventory stock.
                    local recipe = unwrap(args[1])
                    assert(recipe:type() == "FName", "material view recipe is not an FName")
                    local costs = NativeMaterialView.copy(unwrap(args[2]))
                    local items = {}
                    for id in pairs(costs) do items[#items + 1] = id end
                    table.sort(items)
                    local rows = {}
                    for _, id in ipairs(items) do rows[#rows + 1] = id .. "=" .. costs[id] end
                    log("UI_MATERIALS recipe=" .. clean(recipe:ToString())
                        .. " costs=" .. table.concat(rows, ","))
                    local recipeId = recipe:ToString()
                    -- In focused runs reserve quantity samples for creation /
                    -- pickup / cancellation. Repeated UI rebuilds need costs,
                    -- but only the first inventory sample for each recipe.
                    if state.inventory and #items > 0 and (not focus or not state.uiCountsSeen[recipeId]) then
                        if focus then state.uiCountsSeen[recipeId] = true end
                        local counts, problem = state.inventory:read(object, items)
                        if counts then
                            local inventoryRows = {}
                            for _, id in ipairs(items) do
                                inventoryRows[#inventoryRows + 1] = id .. ":player=" .. counts.PlayerInventory[id]
                                    .. ":base_query=" .. counts.InsideBase[id]
                            end
                            log("LOCAL_COUNTS recipe=" .. clean(recipe:ToString())
                                .. " values=" .. table.concat(inventoryRows, ",") .. " authority=unverified")
                        elseif problem then log("inventory query disabled: " .. clean(problem)) end
                    end
                end
                if valid(object) then
                    for _, name in ipairs(propertyNames) do
                        local read, value = pcall(function() return object[name] end)
                        if read then parts[#parts + 1] = name .. "=" .. describe(value) end
                    end
                end
                log(phase .. " " .. path .. " " .. table.concat(parts, " "))
            end)
            if not ok then log("callback error: " .. clean(err)) end
            -- No returned value: original function behavior is preserved.
        end
        local preCallback = function(context, ...) callback("CALL", context, ...) end
        local postCallback = function(context, ...) callback("POST", context, ...) end
        local ok, pre, post
        if path:sub(1, 8) == "/Script/" then
            ok, pre, post = pcall(api.RegisterHook, path, preCallback, postCallback)
        else
            ok, pre, post = pcall(api.RegisterHook, path, preCallback)
        end
        if ok then
            state.hooks[path] = { pre, post }
            log("HOOK " .. path)
        else
            log("hook unavailable " .. path .. " " .. clean(pre))
        end
    end
    function state.scan()
        if state.stopped then return end
        for _, path in ipairs(state.paths) do
            if not state.seen[path] then
                local found, class = pcall(api.StaticFindObject, path)
                if found and valid(class) then
                    local ok, err = pcall(function()
                        local hasParent, parent = pcall(function() return class:GetSuperStruct() end)
                        if hasParent and valid(parent) then
                            local parentPath = parent:GetFullName():match("^%S+%s+(.+)$")
                            if parentPath and parentPath:sub(1, 12) == "/Script/Pal." then
                                log("PARENT " .. path .. " " .. parentPath)
                                if not state.known[parentPath] and #state.paths < 32 then
                                    state.known[parentPath] = true
                                    state.paths[#state.paths + 1] = parentPath
                                end
                            end
                        end
                        local propertyNames = {}
                        class:ForEachProperty(function(property)
                            local name = property:GetFName():ToString()
                            log("PROPERTY " .. path .. " " .. clean(property:GetFullName()))
                            if fields[name] then propertyNames[#propertyNames + 1] = name end
                        end)
                        class:ForEachFunction(function(func)
                            local name = func:GetFName():ToString()
                            local flags = func:GetFunctionFlags()
                            local fullPath = path .. ":" .. name
                            local args = {}
                            local nameArrayReturn = false
                            local materialArray = false
                            func:ForEachProperty(function(property)
                                local label = property:GetFName():ToString()
                                args[#args + 1] = label
                                if name == "GetRecipes" and label == "ReturnValue" then
                                    local schema = property:GetFullName()
                                    if schema:match("^ArrayProperty ") then
                                        local inner = property:GetInner():GetFullName()
                                        nameArrayReturn = inner:match("^NameProperty ") ~= nil
                                        log("RETURN_SCHEMA " .. fullPath .. " inner=" .. clean(inner))
                                    end
                                end
                                if name == "Setup" and label == "MatInfo" then
                                    local schema = property:GetFullName()
                                    if schema:match("^ArrayProperty ") then
                                        local inner = property:GetInner()
                                        if inner:GetFullName():match("^StructProperty ") then
                                            local struct = inner:GetStruct()
                                            if struct:GetFullName() == "ScriptStruct /Script/Pal.PalStaticItemIdAndNum" then
                                                local itemField, numField = false, false
                                                struct:ForEachProperty(function(field)
                                                    local id, definition = field:GetFName():ToString(), field:GetFullName()
                                                    if id == "StaticItemId" then itemField = definition:match("^NameProperty ") ~= nil end
                                                    if id == "Num" then numField = definition:match("^IntProperty ") ~= nil end
                                                end)
                                                materialArray = itemField and numField
                                                log("MATERIAL_SCHEMA " .. fullPath .. " verified=" .. tostring(materialArray))
                                            end
                                        end
                                    end
                                end
                            end)
                            -- Blueprint reflection also includes local variables.
                            log("FUNCTION " .. fullPath .. " flags=" .. flags .. " fields=" .. table.concat(args, ","))
                            local delegate = flags & (0x00100000 | 0x00010000) ~= 0
                                or name:find("DelegateSignature", 1, true) ~= nil
                            if names[name] and not delegate then hook(fullPath, args, propertyNames, nameArrayReturn, materialArray) end
                        end)
                    end)
                    if ok then
                        state.seen[path] = true
                        log("CLASS " .. path .. " inspected")
                        if path == "/Script/Pal.PalItemUtility" then
                            local ready, reader = pcall(NativeCounts.new, class, api.FName, config.MaxInventorySamples)
                            if ready then
                                state.inventory = reader
                                log("COUNT_SCHEMA local player/base scalar queries verified")
                            else log("count queries unavailable: " .. clean(reader)) end
                        end
                    else
                        state.seen[path] = true -- do not repeatedly flood logs after an API mismatch
                        log("reflection unavailable " .. path .. " " .. clean(err))
                    end
                end
            end
        end
    end
    local function schedule()
        local ok, err = pcall(api.ExecuteInGameThread, function()
            local scanned, problem = pcall(state.scan)
            if not scanned then log("scan error: " .. clean(problem)) end
        end)
        if not ok then log("scheduling unavailable: " .. clean(err)) end
    end
    function state.stop()
        state.stopped = true
        if type(api.UnregisterHook) == "function" then
            for path, ids in pairs(state.hooks) do pcall(api.UnregisterHook, path, ids[1], ids[2]) end
        end
    end
    schedule()
    if type(api.LoopAsync) == "function" then
        local loopOk, loopError = pcall(api.LoopAsync, 2000, function()
            if state.stopped or state.polls >= 120 then return true end
            state.polls = state.polls + 1
            schedule()
            return false
        end)
        if not loopOk then log("delayed discovery unavailable: " .. clean(loopError)) end
    end
    log("Read-only discovery active; gameplay remains native.")
    return state
end

return Diagnostics
