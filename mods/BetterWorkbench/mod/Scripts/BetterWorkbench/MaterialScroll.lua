local M = {}
local CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment_ItemInfo_Tecnology.WBP_InventoryEquipment_ItemInfo_Tecnology_C"
local hookIds
local messages = 0
local function valid(object)
    return object and pcall(function() assert(object:IsValid()) end)
end
local function log(text)
    if messages < 12 then
        messages = messages + 1
        print("[BetterWorkbench:UI] " .. text .. "\n")
    end
end
local function slotData(slot)
    local p, s = slot.Padding, slot.Size
    return {
        padding = { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom },
        size = { Value = s.Value, SizeRule = s.SizeRule },
        horizontal = slot.HorizontalAlignment, vertical = slot.VerticalAlignment,
    }
end
local function restoreSlot(slot, data)
    slot:SetPadding(data.padding)
    slot:SetHorizontalAlignment(data.horizontal)
    slot:SetVerticalAlignment(data.vertical)
    slot:SetSize(data.size)
end
local function viewportHeight(list, config)
    -- Desired sizes use UMG layout units, so DPI scaling is applied once by
    -- the game. Include each row's slot padding in the visible height.
    list:ForceLayoutPrepass()
    local count, height, totalHeight = 0, 0, 0
    for index = 0, list:GetChildrenCount() - 1 do
        local row = list:GetChildAt(index)
        -- Vanilla can keep unused rows as collapsed children between recipes.
        if row:GetVisibility() ~= 1 then -- Collapsed.
            local rowHeight = row:GetDesiredSize().Y
            if rowHeight <= 0 then rowHeight = config.RowHeight end
            local padding = row.Slot.Padding
            rowHeight = rowHeight + padding.Top + padding.Bottom
            count = count + 1
            totalHeight = totalHeight + rowHeight
            if count <= config.VisibleRows then height = height + rowHeight end
        end
    end
    totalHeight = math.max(totalHeight, list:GetDesiredSize().Y)
    if count <= config.VisibleRows then height = totalHeight end
    if count >= config.VisibleRows then
        height = height * config.HeightScale
    end
    -- Round upward so subpixel layout differences don't create tiny overflow.
    height = math.ceil(height) + 1
    return height, totalHeight > height
end
local function resizeViewport(viewport, scroll, list, config)
    local height, overflowing = viewportHeight(list, config)
    viewport:SetMaxDesiredHeight(height)
    viewport:SetHeightOverride(height)
    scroll:SetScrollBarVisibility(overflowing and 0 or 1) -- Visible / Collapsed.
    if not overflowing then scroll:ScrollToStart() end
    return height
end
local function apply(widget, config)
    if not valid(widget) then return end
    -- The same vanilla component also serves inventory tooltips. Limit the
    -- modification to the workbench's live recipe details.
    if not widget:GetFullName():find("WBP_IngameMenu_WorkSpace", 1, true) then return end
    local list = widget.VerticalBox_TechDetails
    if not valid(list) then return end
    local parent = list:GetParent()
    if not valid(parent) then return end
    if parent:GetFullName():find("BetterWorkbenchMaterialsScroll", 1, true) then
        local viewport = parent:GetParent()
        if valid(viewport) then
            local height = resizeViewport(viewport, parent, list, config)
            log("material viewport refreshed; height=" .. tostring(height))
        end
        return
    end
    local count = parent:GetChildrenCount()
    if count < 1 or count > 8 then return end
    local children, target = {}, nil
    for index = 0, count - 1 do
        local child = parent:GetChildAt(index)
        children[#children + 1] = { widget = child, layout = slotData(child.Slot) }
        if child:GetFullName() == list:GetFullName() then target = index + 1 end
    end
    if not target then return end
    local tree = widget.WidgetTree
    local sizeClass = StaticFindObject("/Script/UMG.SizeBox")
    local scrollClass = StaticFindObject("/Script/UMG.ScrollBox")
    if not valid(tree) or not valid(sizeClass) or not valid(scrollClass) then return end
    local viewport = StaticConstructObject(sizeClass, tree, FName("BetterWorkbenchMaterialsViewport"))
    local scroll = StaticConstructObject(scrollClass, tree, FName("BetterWorkbenchMaterialsScroll"))
    if not valid(viewport) or not valid(scroll) then return end
    scroll:SetOrientation(1) -- Vertical.
    scroll:SetConsumeMouseWheel(0) -- Consume only when scrolling is possible.
    scroll:SetAlwaysShowScrollbar(false)
    scroll:SetClipping(1) -- ClipToBounds.
    viewport:SetContent(scroll)
    local height = resizeViewport(viewport, scroll, list, config)
    local ok, reason = pcall(function()
        parent:ClearChildren()
        scroll:AddChild(list)
        for index, child in ipairs(children) do
            local slot = parent:AddChild(index == target and viewport or child.widget)
            assert(valid(slot), "viewport slot unavailable")
            restoreSlot(slot, child.layout)
        end
        -- Decorative vanilla ancestors may block pointer input to children.
        -- Enable children only; retain all existing visibility/collapse state.
        local ancestor = scroll
        for _ = 1, 10 do
            if not valid(ancestor) then break end
            if ancestor:GetVisibility() == 3 then ancestor:SetVisibility(4) end
            ancestor = ancestor:GetParent()
        end
    end)
    if not ok then
        list:RemoveFromParent()
        viewport:RemoveFromParent()
        parent:ClearChildren()
        for _, child in ipairs(children) do restoreSlot(parent:AddChild(child.widget), child.layout) end
        log("scroll layout reverted: " .. tostring(reason))
        return
    end
    log("vanilla material list scroll attached; rows=" .. tostring(list:GetChildrenCount()) .. "; height=" .. tostring(height))
end
function M.start(config)
    if not config or config.Enabled ~= true or type(StaticConstructObject) ~= "function" then return end
    config.VisibleRows = math.max(1, math.min(10, config.VisibleRows or 5))
    config.RowHeight = math.max(20, math.min(80, config.RowHeight or 38))
    config.HeightScale = math.max(1, math.min(2, config.HeightScale or 1))
    local function update(widget)
        local ok, reason = pcall(apply, widget, config)
        if not ok then log("scroll unavailable: " .. tostring(reason)) end
    end
    local function install()
        if hookIds then return end
        -- UE4SS Blueprint hooks use callback two as the post hook.
        local ok, pre, post = pcall(RegisterHook, CLASS .. ":SetDetails",
            function(context) update(context:get()) end)
        if ok then hookIds = { pre, post }; log("material refresh hook registered") end
    end
    install()
    if type(NotifyOnNewObject) == "function" then
        NotifyOnNewObject(CLASS, function()
            -- Notifications occur before widget initialization. The SetDetails
            -- post hook handles actual layout only after vanilla rows exist.
            if type(ExecuteInGameThread) == "function" then ExecuteInGameThread(install) end
        end)
    end
    -- One bounded class query handles an already open menu after Lua reload.
    -- No timer, tick hook, or world-wide object traversal is installed.
    if type(FindAllOf) == "function" and type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(function()
            local widgets = FindAllOf("WBP_InventoryEquipment_ItemInfo_Tecnology_C") or {}
            for index, widget in ipairs(widgets) do
                if index > 32 then break end
                update(widget)
            end
        end)
    end
end
return M
