local Plan = require('BetterPalSouls.Plan')
local Slots = require('BetterPalSouls.Slots')
local Runtime = require('BetterPalSouls.Runtime')
local Service = require('BetterPalSouls.Service')
local I18n = require('BetterPalSouls.I18n')
local M = {}
local valid, unwrap = Runtime.valid, Runtime.unwrap
local ROOT = '/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/Buildup/'
local BUTTON = '/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonButton'
local CLICK = 'BndEvt__WBP_CommonButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_3_CommonButtonBaseClicked__DelegateSignature'
local sessions, rows, buttons, hooks, diagnostics = {}, {}, {}, {}, {}
local backend, service, update, installHooks
local stopped = false
local function trace(message) print('[BetterPalSouls] ' .. message .. '\n') end
local function ranks(values) return table.concat(values, ',') end
local function key(o) return o:GetFullName() end
local function text(o, value) o:SetText(FText(value)) end
local function once(message)
    message = tostring(message)
    if diagnostics[message] then return end
    diagnostics[message] = true
    print('[BetterPalSouls] ' .. message .. '\n')
end
local function create(session, label)
    local path = BUTTON .. '.WBP_CommonButton_C'
    local class = StaticFindObject(path)
    if not valid(class) then
        local system = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        class = system:LoadClassAsset_Blocking(system:Conv_SoftClassPathToSoftClassRef(system:MakeSoftClassPath(path)))
    end
    assert(valid(class), 'button_class_unavailable')
    local widget = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        :Create(session.Menu, class, session.Menu:GetOwningPlayer())
    assert(valid(widget), 'button_creation_failed')
    text(widget, label)
    widget:SetToolTipText(FText(''))
    widget.WBP_PalInvisibleButton:SetToolTipText(FText(''))
    widget.WBP_PalInvisibleButton:SetIsFocusable(true)
    widget.WBP_PalInvisibleButton:SetShouldUseFallbackDefaultInputAction(true)
    -- This layer handles input only. Its inherited disabled Slate brush draws
    -- an opaque white rectangle; the sibling frame/text provide the visuals.
    widget.WBP_PalInvisibleButton:SetRenderOpacity(0)
    return widget
end
local function place(parent, child, x, y, w, h)
    local slot = parent:AddChildToCanvas(child)
    slot:SetAutoSize(false)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetOffsets({ Left = x, Top = y, Right = w, Bottom = h })
    slot:SetZOrder(100)
    return slot
end
local function styleArrow(widget)
    local root, label = widget.WidgetTree.RootWidget, widget.Text_Main
    assert(valid(root) and valid(label), 'arrow_visuals_unavailable')
    -- Keep the native input/focus control and replace the common frame with
    -- a square matching the native +/- background.
    for i = 0, root:GetChildrenCount() - 1 do
        local child = root:GetChildAt(i)
        if key(child) ~= key(widget.WBP_PalInvisibleButton) then child:SetVisibility(1) end
    end
    local background = StaticConstructObject(StaticFindObject('/Script/UMG.Image'), widget.WidgetTree)
    assert(valid(background), 'arrow_background_unavailable')
    background:SetColorAndOpacity({ R = 0.06301, G = 0.093059, B = 0.102242, A = 1 })
    background:SetVisibility(4)
    place(root, background, 0, 0, 26, 26):SetZOrder(0)
    label:RemoveFromParent()
    place(root, label, 0, -3, 26, 32)
    label:SetVisibility(4) -- Visual only; input goes to the invisible button.
    local font = label.Font
    font.Size = 14
    label:SetFont(font)
    label:SetJustification(1)
    widget.WBP_PalInvisibleButton.Slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
end
local function restore(session)
    session.Signature = nil
    if valid(session.Confirm) then session.Confirm:SetVisibility(1) end
    if valid(session.Panel) then session.Panel.WBP_CommonButton:SetVisibility(0) end
    for _, entry in ipairs(session.Rows) do
        if valid(entry.Min) then entry.Min:SetVisibility(1) end
        if valid(entry.Max) then entry.Max:SetVisibility(1) end
        if valid(entry.Gauge) then entry.Gauge.Slot:SetOffsets(entry.Offsets) end
        if valid(entry.MinusVisual) then entry.MinusVisual:SetIsEnabled(true) end
        if valid(entry.PlusVisual) then entry.PlusVisual:SetIsEnabled(true) end
    end
end
local function signature(session, state)
    local parts = { state.HandleKey, tostring(service.disabled == true) }
    for i = 1, 4 do parts[#parts + 1] = tostring(state.Current[i]); parts[#parts + 1] = tostring(session.Targets[i]) end
    for _, id in ipairs(Plan.items) do parts[#parts + 1] = tostring(state.Stock[id]); parts[#parts + 1] = tostring(state.Limits[id]) end
    for _, row in ipairs(state.Schedule) do parts[#parts + 1] = row.Item; parts[#parts + 1] = tostring(row.Count) end
    for _, slot in ipairs(state.Slots) do parts[#parts + 1] = slot.Item; parts[#parts + 1] = tostring(slot.Count); parts[#parts + 1] = tostring(slot.Backpack) end
    return table.concat(parts, '|')
end
local function cleanOldSelector(row)
    -- Remove only the earlier version's private workbench selector. Its PAK
    -- is no longer referenced; original reinforcement widgets are retained.
    pcall(function()
        local canvas = row.CanvasPanel_0
        for i = canvas:GetChildrenCount() - 1, 0, -1 do
            local child = canvas:GetChildAt(i)
            if child:GetClass():GetFName():ToString() == 'ScaleBox' then
                local size = child:GetChildAt(0)
                local selector = valid(size) and size:GetChildAt(0) or nil
                if valid(selector) and selector:GetClass():GetFullName():find('/Game/Mods/BetterPalSouls/', 1, true) then
                    child:RemoveFromParent()
                end
            end
        end
    end)
end
local function cleanAddedButtons(canvas, original)
    -- Lua hot-reload removes callbacks but leaves attached widgets alive.
    -- Remove earlier injected buttons so old disabled backgrounds cannot
    -- remain underneath the replacement controls. Preserve the native button.
    for i = canvas:GetChildrenCount() - 1, 0, -1 do
        local child = canvas:GetChildAt(i)
        if valid(child) and child:GetClass():GetFName():ToString() == 'WBP_CommonButton_C'
            and (not original or key(child) ~= key(original)) then child:RemoveFromParent() end
    end
end
local function attach(menu)
    local id = key(menu)
    if sessions[id] then return sessions[id] end
    local panel = menu.WBP_Buildup_Pal_Status
    if not valid(panel) or not valid(menu.CurrentHandle) or panel['Is Upgrade'] ~= true then return end
    local session = { Menu = menu, Panel = panel, Rows = {}, Targets = {}, Updating = true }
    local ok, reason = pcall(function()
        local state = backend:read(session)
        local contents = { panel.WBP_Buildup_Pal_StatusContent, panel.WBP_Buildup_Pal_StatusContent_1,
            panel.WBP_Buildup_Pal_StatusContent_2, panel.WBP_Buildup_Pal_StatusContent_3 }
        for _, row in ipairs(contents) do
            assert(valid(row), 'row_unavailable')
            local stat = Plan.integer(row.Status, 1, 4)
            cleanAddedButtons(row.CanvasPanel_0)
            cleanOldSelector(row)
            row:Setup(stat) -- Restore the native stat title after the old selector.
            local gauge = row.HorizontalBox_Gauge:GetParent()
            local offsets = gauge.Slot:GetOffsets()
            -- Earlier versions narrowed this canvas, pulling native +/- inward.
            -- Normalize that exact footprint when attaching after a reload.
            if offsets.Left == 378 and offsets.Top == 12 and offsets.Right == 168 and offsets.Bottom == 48 then
                offsets = { Left = 352, Top = 12, Right = 220, Bottom = 48 }
            end
            local entry = { Row = row, Key = key(row), Stat = stat, Gauge = gauge,
                MinusVisual = row.WBP_PalInvisibleButton_Minus:GetParent(),
                PlusVisual = row.WBP_PalInvisibleButton_Plus:GetParent(),
                Offsets = { Left = offsets.Left, Top = offsets.Top, Right = offsets.Right, Bottom = offsets.Bottom } }
            entry.Min, entry.Max = create(session, '◀'), create(session, '▶')
            styleArrow(entry.Min); styleArrow(entry.Max)
            entry.MinKey, entry.MaxKey = key(entry.Min), key(entry.Max)
            place(row.CanvasPanel_0, entry.Min, offsets.Left + 28, offsets.Top + 5, 26, 26)
            place(row.CanvasPanel_0, entry.Max, offsets.Left + offsets.Right - 54, offsets.Top + 5, 26, 26)
            rows[entry.Key] = { Session = session, Entry = entry }
            buttons[entry.MinKey] = { Session = session, Stat = stat, Action = 'min' }
            buttons[entry.MaxKey] = { Session = session, Stat = stat, Action = 'max' }
            session.Rows[#session.Rows + 1] = entry
            session.Targets[stat] = state.Current[stat]
        end
        cleanAddedButtons(panel.CanvasPanel_Overall, panel.WBP_CommonButton)
        session.Confirm = create(session, I18n.text('confirm'))
        session.ConfirmKey = key(session.Confirm)
        local original = panel.WBP_CommonButton.Slot
        local slot = panel.CanvasPanel_Overall:AddChildToCanvas(session.Confirm)
        slot:SetAutoSize(false); slot:SetAnchors(original:GetAnchors())
        slot:SetOffsets(original:GetOffsets()); slot:SetAlignment(original:GetAlignment()); slot:SetZOrder(100)
        buttons[session.ConfirmKey] = { Session = session, Action = 'confirm' }
        installHooks()
        assert(hooks.click and hooks.plus and hooks.minus, 'ui_events_unavailable')
        sessions[id] = session
    end)
    session.Updating = false
    if not ok then
        restore(session)
        for _, entry in ipairs(session.Rows) do
            rows[entry.Key], buttons[entry.MinKey], buttons[entry.MaxKey] = nil, nil, nil
            if valid(entry.Min) then entry.Min:RemoveFromParent() end
            if valid(entry.Max) then entry.Max:RemoveFromParent() end
        end
        if session.ConfirmKey then buttons[session.ConfirmKey] = nil end
        if valid(session.Confirm) then session.Confirm:RemoveFromParent() end
        once(reason); return
    end
    once('native reinforcement rows with minimum/maximum arrows attached')
    return session
end
update = function(session)
    if session.Updating or not valid(session.Menu) or not valid(session.Panel) then return end
    if session.Panel['Is Upgrade'] ~= true then restore(session); return end
    session.Updating = true
    local ok, reason = pcall(function()
        local state = backend:read(session)
        local changedPal = session.HandleKey ~= state.HandleKey
        -- Script hooks run before the native Blueprint body. Read its final
        -- TargetRank on the next refresh/input, never inside the pre-hook.
        for _, entry in ipairs(session.Rows) do
            if entry.PendingNative and not changedPal then
                session.Targets[entry.Stat] = Plan.integer(entry.Row.TargetRank, 0, #state.Schedule)
            end
            entry.PendingNative = nil
        end
        for i = 1, 4 do
            if changedPal or (session.Current and session.Current[i] ~= state.Current[i]) then session.Targets[i] = state.Current[i] end
            session.Targets[i] = math.max(state.Current[i], math.min(#state.Schedule, session.Targets[i] or state.Current[i]))
        end
        session.HandleKey, session.Current = state.HandleKey, state.Current
        for i = 4, 1, -1 do session.Targets[i] = math.min(session.Targets[i], Plan.maximum(state.Stock, state.Current, session.Targets, state.Schedule, i)) end
        local nextSignature = signature(session, state)
        if nextSignature == session.Signature then return end
        local required, changed = Plan.cost(state.Current, session.Targets, state.Schedule)
        local plan, problem = Plan.prepare(state.Stock, required)
        local writes
        if plan then writes, problem = Slots.allocate(state.Slots, plan.Prepared, state.Limits) end
        local nativeCostOk = true
        if changed and plan and writes then
            local checked, error = pcall(function() backend:checkCost(state, session.Targets) end)
            nativeCostOk = checked
            if checked then once('native cost preflight passed') else once(error) end
        end
        local rankMap, mapChanged = session.Panel.TargetStatusRankMap, false
        for stat = 1, 4 do
            local wanted = session.Targets[stat] > state.Current[stat] and session.Targets[stat] or nil
            local actual = rankMap:Contains(stat) and unwrap(rankMap:Find(stat)) or nil
            if actual ~= wanted then
                mapChanged = true
                if wanted then rankMap:Add(stat, wanted) else rankMap:Remove(stat) end
            end
        end
        for _, entry in ipairs(session.Rows) do
            local row, stat = entry.Row, entry.Stat
            local maximum = Plan.maximum(state.Stock, state.Current, session.Targets, state.Schedule, stat)
            local canDecrease = session.Targets[stat] > state.Current[stat]
            local canIncrease = session.Targets[stat] < maximum
            if changedPal or row.TargetRank ~= session.Targets[stat] or row['Current Rank'] ~= state.Current[stat] then
                row:SetInfo(state.Parameter, session.Targets[stat])
            end
            row:SetEnable(true)
            entry.Gauge:SetVisibility(0)
            entry.Gauge.Slot:SetOffsets(entry.Offsets)
            entry.Min:SetVisibility(0); entry.Max:SetVisibility(0)
            entry.Min:SetIsEnabled(canDecrease)
            entry.Max:SetIsEnabled(canIncrease)
            row.WBP_PalInvisibleButton_Minus:SetRenderOpacity(0)
            row.WBP_PalInvisibleButton_Plus:SetRenderOpacity(0)
            row.WBP_PalInvisibleButton_Minus:SetIsEnabled(canDecrease)
            row.WBP_PalInvisibleButton_Plus:SetIsEnabled(canIncrease)
            -- Native icons are siblings of their click layers. Disable their
            -- containing canvases too so Slate dims both icon and background.
            entry.MinusVisual:SetIsEnabled(canDecrease)
            entry.PlusVisual:SetIsEnabled(canIncrease)
        end
        -- Native +/- has already refreshed its bill. Only programmatic target
        -- changes (min/max or reconciliation) require another native calculation.
        if mapChanged or changedPal then session.Panel:UpdateRequiredItemSufficiency() end
        session.Panel.WBP_CommonButton:SetVisibility(1)
        session.Confirm:SetVisibility(0)
        session.Confirm:SetIsEnabled(changed and plan ~= nil and writes ~= nil and nativeCostOk and not service.disabled)
        session.Signature = nextSignature
    end)
    session.Updating = false
    if not ok then restore(session); once(reason) end
end
function M.start(config)
    if not config.Enabled then return end
    I18n.configure(config.Language)
    backend = Runtime.new(); service = Service.new(backend)
    -- Blueprint hooks may share an engine callback entry with another mod.
    -- UE4SS's owner-based unload cleanup can leave this mod's registry refs
    -- alive in that entry after its Lua state closes. Remove our IDs explicitly.
    if ModRef then ModRef.OnUnload = M.stop end
    local function hook(path, callback)
        if not valid(StaticFindObject(path)) then return end
        local ok, a, b = pcall(RegisterHook, path, function(...)
            if stopped then return end
            local success, reason = pcall(callback, ...)
            if not success then once(reason) end
        end)
        if ok then return { a, b, Path = path } end
    end
    local function nativeSelection(context)
        local row = unwrap(context)
        local registered = rows[key(row)]
        if not registered or registered.Session.Updating then return end
        registered.Entry.PendingNative = true
    end
    installHooks = function()
        hooks.plus = hooks.plus or hook(ROOT .. 'WBP_Buildup_Pal_StatusContent.WBP_Buildup_Pal_StatusContent_C:StatusPlus', nativeSelection)
        hooks.minus = hooks.minus or hook(ROOT .. 'WBP_Buildup_Pal_StatusContent.WBP_Buildup_Pal_StatusContent_C:StatusMinus', nativeSelection)
        hooks.click = hooks.click or hook(BUTTON .. '.WBP_CommonButton_C:' .. CLICK, function(context)
            local registered = buttons[key(unwrap(context))]
            if not registered then return end
            local session = registered.Session
            if session.Updating or session.Panel['Is Upgrade'] ~= true then return end
            update(session) -- Reconcile any completed native +/- before another input.
            if registered.Action ~= 'confirm' then
                local state = backend:read(session)
                local stat = registered.Stat
                session.Targets[stat] = registered.Action == 'min' and state.Current[stat]
                    or Plan.maximum(state.Stock, state.Current, session.Targets, state.Schedule, stat)
                trace(registered.Action .. ' stat=' .. stat .. ' current=' .. ranks(state.Current)
                    .. ' targets=' .. ranks(session.Targets) .. ' budget=' .. Plan.value(state.Stock))
                update(session)
                trace('reconciled targets=' .. ranks(session.Targets))
                return
            end
            local targets, current = {}, {}
            for i = 1, 4 do targets[i], current[i] = session.Targets[i], session.Current[i] end
            trace('submit current=' .. ranks(current) .. ' targets=' .. ranks(targets))
            session.Updating = true
            local result, reason = service:submit(session, targets, session.HandleKey, current)
            session.Updating = false
            if not result then
                once(reason)
                pcall(function() StaticFindObject('/Script/Pal.Default__PalUtility')
                    :Alert(session.Menu:GetOwningPlayer(), FText(I18n.text('failed', I18n.reason(reason)))) end)
            else trace('upgrade committed; current=' .. ranks(current) .. ' targets=' .. ranks(targets)
                .. ' cost=' .. result.Cost .. ' remaining=' .. Plan.value(result.Remaining)) end
            update(session)
        end)
    end
    local queued = false
    LoopAsync(config.RefreshIntervalMs or 750, function()
        if stopped then return true end
        if queued then return false end
        queued = true
        ExecuteInGameThread(function()
            if stopped then queued = false; return end
            local ok, reason = pcall(function()
                for id, session in pairs(sessions) do
                    if not valid(session.Menu) then
                        for _, entry in ipairs(session.Rows) do rows[entry.Key], buttons[entry.MinKey], buttons[entry.MaxKey] = nil, nil, nil end
                        buttons[session.ConfirmKey] = nil; sessions[id] = nil
                    end
                end
                for i, menu in ipairs(FindAllOf('WBP_Buildup_Pal_C') or {}) do
                    if i > 8 then break end
                    if valid(menu) and menu:IsVisible() then local session = attach(menu); if session then update(session) end end
                end
            end)
            queued = false
            if not ok then once(reason) end
        end)
        return false
    end)
    once('0.2.6 loaded; native selection reconciled after Blueprint execution; max tracing enabled')
end
function M.stop()
    stopped = true
    for _, registration in pairs(hooks) do
        local ok, reason = pcall(UnregisterHook, registration.Path, registration[1], registration[2])
        if not ok then once('hook cleanup failed: ' .. tostring(reason)) end
    end
    hooks, sessions, rows, buttons = {}, {}, {}, {}
end
return M
