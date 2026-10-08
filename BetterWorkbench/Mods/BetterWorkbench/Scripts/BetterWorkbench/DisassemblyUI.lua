local Runtime = require("BetterWorkbench.DisassemblyRuntime")
local Service = require("BetterWorkbench.CraftService")
local Util = require("BetterWorkbench.Util")
local M = {}
local WORK = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C"
local BUTTON = "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonButton.WBP_CommonButton_C"
local CLICK_EVENT = "BndEvt__WBP_CommonButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_3_CommonButtonBaseClicked__DelegateSignature"
local clicks, sessions, hooks = {}, {}, {}
local inputTypes = {}
local service
local installHooks
local diagnostics = {}
local guardReady = false
local refreshEntry
local function valid(o)
    local ok, result = pcall(function() return o and o:IsValid() end)
    return ok and result == true
end
local function value(parameter)
    local ok, kind = pcall(function() return parameter:type() end)
    if ok and (kind == "RemoteUnrealParam" or kind == "LocalUnrealParam") then return parameter:get() end
    return parameter
end
local function key(o) return o:GetFullName() end
local function log(message) print("[BetterWorkbench:Disassembly] " .. tostring(message) .. "\n") end
local function once(message)
    if diagnostics[message] then return end
    diagnostics[message] = true
    log(message)
end
local function text(widget, value) widget:SetText(FText(value)) end
local function itemName(session, id)
    local ok, name = pcall(function()
        local out = {}
        StaticFindObject("/Script/Pal.Default__PalUIUtility"):GetItemName(session.workspace, FName(id), out)
        return out.outName:ToString()
    end)
    return ok and name ~= "" and name or id
end
local function button(session, label, callback)
    local class = StaticFindObject(BUTTON)
    if not valid(class) then
        LoadAsset("/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonButton")
        class = StaticFindObject(BUTTON)
    end
    local widget = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        :Create(session.workspace, class, session.workspace:GetOwningPlayer())
    assert(valid(widget), "common button unavailable")
    if installHooks then installHooks() end
    text(widget, label)
    widget:SetVisibility(0)
    widget:SetIsEnabled(true)
    if valid(widget.Text_Main) then widget.Text_Main:SetRenderOpacity(1) end
    clicks[key(widget)] = { session = session, callback = callback }
    return widget
end
local function compactCountTarget(widget)
    local target = widget.WBP_PalInvisibleButton
    assert(valid(target), "owned-count click target unavailable")
    local root = widget.WidgetTree and widget.WidgetTree.RootWidget
    if valid(root) then
        -- Transparent decorations still contribute their normal button size.
        -- Keep only the stretched invisible button in the count overlay.
        for index = 0, root:GetChildrenCount() - 1 do
            local child = root:GetChildAt(index)
            if key(child) ~= key(target) then child:SetVisibility(1) end
        end
    end
    -- The common button expands its hit/focus area by four pixels per side.
    -- The outer count overlay supplies the compact height; avoid extra padding.
    if valid(target.Slot) then
        target.Slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end
    widget:SetToolTipText(FText(""))
    target:SetToolTipText(FText(""))
end
local function navigation(session, handoff)
    local target = session.badge.WBP_PalInvisibleButton
    assert(valid(target), "disassembly focus target unavailable")
    target:SetIsFocusable(true)
    target.HideFocusCursor = false
    target:SetShouldUseFallbackDefaultInputAction(true)
    local start = session.workspace.WBP_IngameMenu_StartButton.WBP_PalInvisibleButton
    assert(valid(start), "production focus target unavailable")
    start:SetIsFocusable(true)
    start.HideFocusCursor = false
    start:SetShouldUseFallbackDefaultInputAction(true)
    target:SetNavigationRuleExplicit(0, session.card) -- Left: selected recipe.
    target:SetNavigationRuleExplicit(3, start) -- Down: production/disassembly confirmation.
    start:SetNavigationRuleExplicit(2, target)
    start:SetNavigationRuleExplicit(0, session.card)
    session.workspace.CommonTileView_146:SetNavigationRuleExplicit(1, target)
    session.workspace:SetNavigationRuleExplicit(2, target) -- Up from quantity controls.
    session.workspace:SetNavigationRuleExplicit(0, session.card)
    local ok, input = pcall(function()
        return StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
            :GetLocalPlayerSubsystem(session.workspace:GetOwningPlayer(),
                StaticFindObject("/Script/CommonInput.CommonInputSubsystem")):GetCurrentInputType()
    end)
    input = inputTypes[key(session.workspace)] or (ok and input)
    if handoff then log("detail selection recipe=" .. session.recipeId .. " input=" .. tostring(input)) end
    if input == 1 then
        -- Do not require existing focus: the original handoff can have failed.
        session.workspace:InputMethodChanged(1)
        if handoff then
            local destination = start:GetIsEnabled() and start or
                (session.badge:GetIsEnabled() and target or session.workspace)
            destination:SetUserFocus(session.workspace:GetOwningPlayer())
            log("detail focus handoff recipe=" .. session.recipeId .. " target=" .. key(destination)
                .. " focused=" .. tostring(destination:HasAnyUserFocus()))
        end
    end
    once("owned-count toggle gamepad focus navigation attached")
end
local function close(session, selectionChanged)
    if not session.mode then return end
    session.mode = false
    for _, old in ipairs(session.saved or {}) do
        if valid(old.widget) then
            if old.label then text(old.widget, old.label) end
            if old.visibility then old.widget:SetVisibility(old.visibility) end
        end
    end
    session.saved = nil
    if valid(session.workspace) then
        local selector = session.workspace.WBP_IngameCommonSelectNum
        if not selectionChanged then
            selector["Set Min Max Num"](selector, session.oldMax, session.oldMin)
            selector:SetNum(session.oldNum, session.group, true)
        end
        session.workspace["Update Recipe Detail"](session.workspace)
        if refreshEntry then refreshEntry(session) end
    end
end
local reasons = { backpack_full = "背包空间不足，请先腾出空间。", insufficient_products = "已有成品不足。",
    disassembly_in_progress = "正在分解，请稍候。",
    disassembly_disabled_after_inventory_error = "分解已停止，请重新进入游戏后检查背包。" }
local function feedback(session, message)
    -- Reuse the game's notification path used by the working reference mod.
    -- A notification failure never changes the completed inventory operation.
    local ok, reason = pcall(function()
        StaticFindObject("/Script/Pal.Default__PalUtility"):Alert(session.workspace:GetOwningPlayer(), FText(message))
    end)
    log(message)
    if not ok then log("notification unavailable: " .. tostring(reason)) end
end
local function successMessage(session, plan)
    local returns = {}
    for _, id in ipairs(Util.keys(plan.Returns)) do
        returns[#returns + 1] = itemName(session, id) .. " × " .. plan.Returns[id]
    end
    return "已分解 " .. itemName(session, plan.ProductItem) .. " × " .. plan.Consumed[plan.ProductItem]
        .. "\n返还：" .. table.concat(returns, "、")
end
local function preview(session, batches, snapshot)
    local ok, plan, reason, state = pcall(service.previewDisassembly, service, session, session.recipeId, batches, snapshot)
    if not ok then return nil, tostring(plan) end
    return plan, reason, state
end
refreshEntry = function(session, plan)
    if not valid(session.badge) then return end
    if not plan then plan = preview(session, 1) end
    local enabled = session.mode == true or
        (plan ~= nil and plan.CanDisassemble == true and not service.backend.disabled)
    session.badge:SetIsEnabled(enabled)
end
local function startButtonLabel(session)
    local seen, count = {}, 0
    local function visit(widget)
        if not valid(widget) or seen[key(widget)] or count >= 64 then return end
        seen[key(widget)], count = true, count + 1
        local ok, label = pcall(function() return widget:GetText():ToString() end)
        if ok and label ~= "" then
            session.saved[#session.saved + 1] = { widget = widget, label = label }
            text(widget, "开始分解")
            return true
        end
        local children, n = pcall(function() return widget:GetChildrenCount() end)
        if children and n <= 32 then
            for index = 0, n - 1 do if visit(widget:GetChildAt(index)) then return true end end
        end
        local hasRoot, root = pcall(function() return widget.WidgetTree.RootWidget end)
        if hasRoot then return visit(root) end
    end
    visit(session.workspace.WBP_IngameMenu_StartButton)
end
local function update(session, status)
    if session.updating then return end
    if not session.mode then refreshEntry(session); return end
    local selected = session.workspace.LastSelectedSlot
    if valid(selected) and key(selected) ~= key(session.card) then return end
    session.updating = true
    local ok, failure = pcall(function()
    local selector = session.workspace.WBP_IngameCommonSelectNum
    local base, problem, snapshot = preview(session, 1)
    assert(base, problem)
    refreshEntry(session, base)
    local maximum = base.MaxBatches
    local minimum = maximum > 0 and 1 or 0
    local requested = Util.integer(selector.nowNum, 0, 1000000000, "disassembly batches")
    session.batches = math.max(minimum, math.min(maximum, requested))
    if selector["Max Num"] ~= maximum or selector.MinNum ~= minimum then
        selector["Set Min Max Num"](selector, maximum, minimum)
    end
    if session.batches ~= requested then selector:SetNum(session.batches, session.group, false) end
    local plan, reason = preview(session, math.max(1, session.batches), snapshot)
    assert(plan, reason)
    session.quantityLogs = session.quantityLogs or {}
    local quantityKey = session.recipeId .. ":" .. session.batches
    if not session.quantityLogs[quantityKey] and (session.quantityLogCount or 0) < 12 then
        session.quantityLogs[quantityKey] = true
        session.quantityLogCount = (session.quantityLogCount or 0) + 1
        local header = session.workspace.Text_ItemNumValue:GetText():ToString()
        log("quantity recipe=" .. session.recipeId .. " header=" .. header .. " backpack=" .. plan.OwnedAmount
            .. " batches=" .. session.batches .. " group=" .. session.group
            .. " consume=" .. (session.batches > 0 and plan.Consumed[plan.ProductItem] or 0) .. " max_batches=" .. plan.MaxBatches)
    end
    local materials = {}
    if session.batches > 0 then
        for _, id in ipairs(Util.keys(plan.Returns)) do
            materials[#materials + 1] = { StaticItemId = FName(id), Num = plan.Returns[id] }
        end
    end
    session.workspace.WBP_InventoryEquipment_ItemInfo_Tecnology:SetDetails(materials, false)
    -- Keep the existing production stock counter and its native refresh path.
    text(session.workspace.BP_PalTextBlock_Name, "分解 · " .. itemName(session, plan.ProductItem))
    text(session.workspace.BP_PalTextBlock_Num, tostring(session.group))
    text(session.workspace.Text_ManMonth_Value, "0")
    session.workspace.WBP_IngameMenu_StartButton:SetEnable(plan.CanDisassemble and not service.backend.disabled)
    if status then log(status) end
    end)
    session.updating = false
    if not ok then error(failure) end
end
local function open(session)
    if session.mode then close(session); return end
    assert(guardReady, "production guard unavailable")
    local plan, reason = preview(session, 1)
    if not plan then log(reason); return end
    if not plan.CanDisassemble or service.backend.disabled then
        refreshEntry(session, plan)
        return
    end
    local workspace, saved = session.workspace, {}
    local selector = workspace.WBP_IngameCommonSelectNum
    session.oldMax, session.oldMin, session.oldNum = selector["Max Num"], selector.MinNum, selector.nowNum
    session.group = plan.Consumed[plan.ProductItem]
    for _, widget in ipairs({workspace.BP_PalTextBlock_Name, workspace.BP_PalTextBlock_Num}) do
        saved[#saved + 1] = { widget = widget, label = widget:GetText():ToString() }
    end
    session.saved, session.mode = saved, true
    assert(workspace["Convert Item Model"]:CanStartProduction() == 1, "production guard did not reject crafting")
    startButtonLabel(session)
    local minimum = plan.MaxBatches > 0 and 1 or 0
    selector["Set Min Max Num"](selector, plan.MaxBatches, minimum)
    selector:SetNum(math.max(minimum, math.min(plan.MaxBatches, session.oldNum)), session.group, false)
    update(session)
    log("disassembly mode entered in production UI")
end
local function attach(workspace, card, handoff)
    if not valid(workspace) or not valid(card) then return end
    local id = key(workspace)
    local session = sessions[id]
    if session then
        local wasDisassembling = session.mode
        local selectedHeader = workspace.Text_ItemNumValue:GetText():ToString()
        close(session, true)
        session.card = card
        session.recipeId = card.RecipeId:ToString()
        if wasDisassembling then
            local current = preview(session, 1)
            if current then text(workspace.BP_PalTextBlock_Name, itemName(session, current.ProductItem)) end
            text(workspace.Text_ItemNumValue, selectedHeader)
        end
        refreshEntry(session)
        navigation(session, handoff)
        return
    end
    session = { workspace = workspace, card = card, recipeId = card.RecipeId:ToString() }
    local plan, reason = preview(session, 1)
    if not plan then once("entry unavailable: " .. tostring(reason)); return end
    log("count source recipe=" .. session.recipeId .. " header=" .. workspace.Text_ItemNumValue:GetText():ToString()
        .. " backpack=" .. plan.OwnedAmount .. " output_per_batch=" .. plan.Consumed[plan.ProductItem])
    local counter = workspace.CanvasPanel_ItemNum
    local parent = counter:GetParent()
    assert(valid(parent), "detail header canvas unavailable")
    -- Remove both the old separate button and earlier count overlays on reload.
    for _, canvas in ipairs({ counter, parent }) do
        for index = canvas:GetChildrenCount() - 1, 0, -1 do
            local child = canvas:GetChildAt(index)
            if child:GetFullName():match("^WBP_CommonButton_C ") then child:RemoveFromParent() end
        end
    end
    local badge = button(session, "", function()
        local selected = workspace.LastSelectedSlot
        if not valid(selected) then return end
        session.card, session.recipeId = selected, selected.RecipeId:ToString()
        open(session)
    end)
    -- Only the original stock icon and number remain visible. Opacity does not
    -- disable hit testing, so mouse and controller confirm share this target.
    compactCountTarget(badge)
    badge:SetRenderOpacity(0)
    session.badge, session.badgeKey = badge, key(badge)
    local slot = counter:AddChildToCanvas(badge)
    -- Constrain the outer widget too: the game's focus cursor can use its bounds
    -- instead of the inner invisible button. Keep the original count width and
    -- center a 28-unit high target vertically within the count canvas.
    slot:SetAutoSize(false)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0.5 }, Maximum = { X = 1, Y = 0.5 } })
    slot:SetOffsets({ Left = 0, Top = -14, Right = 0, Bottom = 28 }); slot:SetZOrder(100)
    local ancestor = counter
    for _ = 1, 8 do
        if not valid(ancestor) then break end
        if ancestor:GetVisibility() == 3 then ancestor:SetVisibility(4) end
        ancestor = ancestor:GetParent()
    end
    sessions[id] = session
    local padReady, padError = pcall(navigation, session, handoff)
    if not padReady then log("gamepad setup failed: " .. tostring(padError)) end
    refreshEntry(session, plan)
    once("detail-header owned-count toggle attached; outer height=28")
end
local function removeOldCardBadge(workspace, card)
    if not valid(card) then return end
    local parent, removed = card.CanvasPanel_Num, false
    for index = parent:GetChildrenCount() - 1, 0, -1 do
        local child = parent:GetChildAt(index)
        if child:GetFullName():match("^WBP_CommonButton_C ") then child:RemoveFromParent(); removed = true end
    end
    if removed then
        local utility = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
        local out = {}
        local row = utility:GetItemRecipeDataTableAccess(workspace):BP_FindRow(card.RecipeId, out)
        if out.bResult then
            text(card.Text_Num, tostring(row.Product_Count))
            card.Text_Num:SetVisibility(0)
            parent:SetVisibility(row.Product_Count == 1 and 1 or 4)
        end
    end
end
local function guarded(callback)
    return function(...)
        local ok, reason = pcall(callback, ...)
        if not ok then
            for _, session in pairs(sessions) do pcall(close, session) end
            log(reason)
        end
    end
end
function M.start(config)
    if not config or not config.Enabled or type(StaticConstructObject) ~= "function"
        or type(NotifyOnNewObject) ~= "function" or type(ExecuteInGameThread) ~= "function" then return end
    service = Service.new(Runtime.new())
    local function hook(path, callback)
        if hooks[path] then return end
        local ok, pre, post = pcall(RegisterHook, path, guarded(callback))
        if ok then hooks[path] = { pre, post } end
    end
    local entryPath = WORK .. ":OnClickedRecipeSlot"
    local clickPath = BUTTON .. ":" .. CLICK_EVENT
    installHooks = function()
    if not hooks.productionGuard then
        local ok, pre, post = pcall(RegisterHook, "/Script/Pal.PalUIConvertItemModel:CanStartProduction",
            function() end, function(context)
                local model = context:get()
                for _, session in pairs(sessions) do
                    if session.mode and valid(session.workspace) and
                        key(session.workspace["Convert Item Model"]) == key(model) then
                        once("vanilla production blocked during disassembly mode")
                        return 1 -- StartProduce permits only Success (0).
                    end
                end
            end)
        if ok then hooks.productionGuard = {pre, post}; guardReady = true end
    end
    hook(entryPath,
        function(context, entry)
            local workspace, card = context:get(), value(entry)
            local session = sessions[key(workspace)]
            if session and session.refreshingStock then return end
            ExecuteInGameThread(guarded(function() attach(workspace, card, true) end))
        end)
    hook(clickPath,
        function(context)
            local click = clicks[key(context:get())]
            if click then once("owned-count/action click received"); click.callback() end
        end)
    hook(WORK .. ":Update Recipe Detail", function(context)
        local session = sessions[key(context:get())]
        if session and session.mode then update(session) end
    end)
    hook(WORK .. ":InputMethodChanged", function(context, inputType)
        local id, input = key(context:get()), value(inputType)
        inputTypes[id] = input
        local session = sessions[id]
        if session and input == 1 and session.workspace.IsSelectingProductNumFlag then
            -- Vanilla disables all navigation while editing quantity. Restore
            -- stick navigation so the button remains reachable; D-pad keys
            -- retain the original quantity actions and never move focus.
            StaticFindObject("/Script/Pal.Default__PalUIUtility"):SetCustomSlateNavigation(session.workspace,
                { IsEnableAnalogNavigation = true, IsEnableLeftKeyNavigation = false,
                    IsEnableRightKeyNavigation = false, IsEnableUpKeyNavigation = false,
                    IsEnableDownKeyNavigation = false })
        end
    end)
    hook(WORK .. ":StartProduce", function(context)
        local session = sessions[key(context:get())]
        if not session or not session.mode then return end
        -- The native guard makes the original StartProduce skip its craft path.
        -- This post hook is shared by the vanilla button and controller binding.
        local batches = Util.integer(session.workspace.WBP_IngameCommonSelectNum.nowNum, 0, 256, "disassembly batches")
        if batches == 0 then feedback(session, "分解失败：" .. reasons.insufficient_products); return end
        local ok, result, failed = pcall(service.disassemble, service, session, session.recipeId, batches)
        if not ok or not result then
            log(ok and failed or result)
            feedback(session, "分解失败：" .. (reasons[failed] or
                (service.backend.disabled and reasons.disassembly_disabled_after_inventory_error) or "请检查背包并重新打开工作台。"))
            update(session)
            return
        end
        log(successMessage(session, result))
        -- The original selection event owns the header's existing stock count.
        -- Refresh through that event without treating it as a new selection.
        session.refreshingStock = true
        local refreshed, refreshError = pcall(function()
            session.workspace:OnClickedRecipeSlot(session.card)
        end)
        session.refreshingStock = false
        if not refreshed then log("stock header refresh failed: " .. tostring(refreshError)) end
        local current = preview(session, 1)
        local minimum = current.MaxBatches > 0 and 1 or 0
        session.workspace.WBP_IngameCommonSelectNum["Set Min Max Num"](
            session.workspace.WBP_IngameCommonSelectNum, current.MaxBatches, minimum)
        session.workspace.WBP_IngameCommonSelectNum:SetNum(math.max(minimum, math.min(current.MaxBatches, batches)), session.group, false)
        update(session, "分解完成，原始材料已全额返还到背包。")
    end)
    hook("/Script/UMG.UserWidget:Destruct", function(context)
        local object = context:get()
        local id = key(object)
        inputTypes[id] = nil
        for cardId, session in pairs(sessions) do
            if cardId == id or not valid(session.workspace) then
                close(session)
                for buttonId, click in pairs(clicks) do if click.session == session then clicks[buttonId] = nil end end
                sessions[cardId] = nil
            end
        end
    end)
    end
    installHooks()
    NotifyOnNewObject(WORK, function() ExecuteInGameThread(installHooks) end)
    NotifyOnNewObject(BUTTON, function() ExecuteInGameThread(installHooks) end)
    -- Load only the two known UI classes once, so the first workbench opening
    -- does not race its list initialization against a queued new-object hook.
    if type(LoadAsset) == "function" then
        ExecuteInGameThread(function()
            pcall(LoadAsset, "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace")
            pcall(LoadAsset, "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonButton")
            installHooks()
        end)
    end
    if type(FindAllOf) == "function" then
        ExecuteInGameThread(guarded(function()
            local workspaces = FindAllOf("WBP_IngameMenu_WorkSpace_C") or {}
            for index, workspace in ipairs(workspaces) do
                if index > 4 then break end
                if valid(workspace) then
                    local entries = workspace.CommonTileView_146:GetDisplayedEntryWidgets()
                    local count = type(entries) == "table" and #entries or entries:GetArrayNum()
                    once("existing workbench displayed entries=" .. tostring(count))
                    assert(count >= 0 and count <= 256, "invalid displayed recipe count")
                    for item = 1, count do
                        if type(entries) ~= "table" then assert(entries:GetArrayNum() == count, "displayed recipes changed") end
                        removeOldCardBadge(workspace, value(entries[item]))
                    end
                    attach(workspace, workspace.LastSelectedSlot)
                end
            end
        end))
    end
    log("host workbench disassembly enabled; hooks attach when widgets load")
end
return M
