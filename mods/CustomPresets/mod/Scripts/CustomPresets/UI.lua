local I18n = require('CustomPresets.I18n')
local t = I18n.text
local Data = require('CustomPresets.Data')
local Library = require('CustomPresets.Library')
local M = {}
local source = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local directory = assert(source:match('^(.*)/Scripts/CustomPresets/UI.lua$')) .. '/presets/'
if type(CustomPresetsNativeDataDirectory)=='function' then directory=CustomPresetsNativeDataDirectory() end
local library = Library.new(directory)
local characterLibrary = Library.new(directory, 'character')
local WORLD = '/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSettings.WBP_Title_WorldSettings_C'
local BUTTON = '/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_SettingsButton.WBP_Title_SettingsButton_C'
local CHARACTER_CARD = '/Game/Pal/Blueprint/UI/UserInterface/CharacterCreation/WBP_CharaCre_PresetButton.WBP_CharaCre_PresetButton_C'
local CARD_CLICK = CHARACTER_CARD .. ':BndEvt__WBP_CharaCre_BodyTypeButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature'
local CLICK = BUTTON .. ':BndEvt__WBP_Title_SettingsButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature'
local sessions, actions, hooks, reported = {}, {}, {}, {}
local refresh, perform, buildCharacterCards
local function valid(o) return o and o:IsValid() end
local function key(o) return o:GetFullName() end
local function unwrap(o)
    local ok, value = pcall(function() return o:get() end)
    return ok and value or o
end
local function report(err)
    err = tostring(err)
    if not reported[err] then print('[CustomPresets] ' .. err .. '\n'); reported[err] = true end
end
local function label(button, text) button.Text_Main:SetText(FText(text)) end
local function construct(class, menu)
    local result = StaticConstructObject(StaticFindObject('/Script/UMG.' .. class), menu.WidgetTree)
    assert(valid(result), class .. ' creation failed')
    return result
end
local dialogs = {}
local NAME_WINDOW = '/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSettings_NameWindow'
local NAME_PARAM = '/Game/Pal/Blueprint/UI/UserInterface/Title/BP_HUDDispatchParameter_WorldNameInput'
local function assetClass(path)
    local name = path:match('/([^/]+)$')
    local full = path .. '.' .. name .. '_C'
    local class = StaticFindObject(full)
    if not valid(class) then
        -- LoadAsset queries the asset registry by object path, not package path.
        -- Cooked widget assets can be registered under their generated class.
        for _, candidate in ipairs({full, path .. '.' .. name, path}) do
            pcall(LoadAsset, candidate)
            class = StaticFindObject(full)
            if valid(class) then break end
        end
    end
    assert(valid(class), 'Widget class unavailable: ' .. full)
    return class
end
local function renameTitle(window)
    local panelClass = StaticFindObject('/Script/UMG.PanelWidget')
    local function visit(widget)
        if widget:GetFullName():match('[%.:]Text_Head$') then
            widget:SetText(FText(t('title')))
            return true
        end
        if widget:IsA(panelClass) then
            for i=0,widget:GetChildrenCount()-1 do
                if visit(widget:GetChildAt(i)) then return true end
            end
        end
        return false
    end
    assert(visit(window.WidgetTree.RootWidget), 'Rename title widget unavailable')
end
local function openNameDialog(s, values)
    local library = s.Library or library
    if s.DialogParam then return end
    assert(hooks.RenameClose, 'Official rename close handler unavailable')
    local class, paramClass = assetClass(NAME_WINDOW), assetClass(NAME_PARAM)
    local param = StaticConstructObject(paramClass, s.Menu)
    assert(valid(param), 'Rename parameter creation failed')
    param.DefaultInputName = 'Custom Preset'
    param.OutString = ''
    dialogs[key(param)] = {Session=s, Values=values, Param=param}
    s.DialogParam = param
    local ok, err = pcall(function() s.Menu:Push(class, param) end)
    if not ok then dialogs[key(param)] = nil; s.DialogParam = nil; error(err) end
    -- Cosmetic updates must never discard the active dialog's save handler.
    local styled, styleError = pcall(function()
        for _, window in ipairs(FindAllOf('WBP_Title_WorldSettings_NameWindow_C') or {}) do
            if valid(window) then
                local owned = window:GetParam()
                if valid(owned) and key(owned) == key(param) then
                    renameTitle(window)
                end
            end
        end
    end)
    if not styled then report(styleError) end
end
local function create(s, text, command, selection)
    local widget = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        :Create(s.Menu, (s.ButtonClass or s.Confirm:GetClass()), s.Menu:GetOwningPlayer())
    assert(valid(widget), 'Native settings button creation failed')
    label(widget, text)
    local font = widget.Text_Main.Font; font.Size = 14; widget.Text_Main:SetFont(font)
    local root = widget.WidgetTree.RootWidget
    assert(root:IsA(StaticFindObject('/Script/UMG.CanvasPanel')), 'Native button canvas unavailable')
    local text, input = widget.Text_Main, widget.WBP_PalInvisibleButton
    text:RemoveFromParent(); input:RemoveFromParent()
    for i = 0, root:GetChildrenCount()-1 do root:GetChildAt(i):SetVisibility(1) end
    local function fill(child, z)
        local slot = root:AddChildToCanvas(child)
        slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
        slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        slot:SetZOrder(z)
    end
    local background = construct('Image', s.Menu)
    background:SetColorAndOpacity({R=0.025,G=0.06,B=0.075,A=0.96})
    background:SetVisibility(4)
    fill(background, 0); fill(text, 1); fill(input, 2)
    text:SetJustification(1); text:SetVisibility(4)
    input:SetRenderOpacity(0)
    local id = key(widget)
    actions[id] = {Session=s, Command=command, Selection=selection}
    s.ActionIds[id] = true
    return widget
end
local function sized(s, widget, width)
    local box = construct('SizeBox', s.Menu)
    box:SetWidthOverride(width); box:SetHeightOverride(32)
    box:AddChild(widget)
    return box
end
local function placeCanvas(parent, widget, layout)
    local slot = parent:AddChildToCanvas(widget)
    slot:SetAnchors(layout.Anchors)
    slot:SetAlignment(layout.Alignment)
    slot:SetOffsets(layout.Offsets)
    slot:SetAutoSize(layout.AutoSize)
    slot:SetZOrder(layout.ZOrder)
    return slot
end
local function copyLayout(slot)
    local a, p, o = slot:GetAnchors(), slot:GetAlignment(), slot:GetOffsets()
    return {
        Anchors={Minimum={X=a.Minimum.X,Y=a.Minimum.Y},Maximum={X=a.Maximum.X,Y=a.Maximum.Y}},
        Alignment={X=p.X,Y=p.Y},
        Offsets={Left=o.Left,Top=o.Top,Right=o.Right,Bottom=o.Bottom},
        AutoSize=slot:GetAutoSize(), ZOrder=slot:GetZOrder(),
    }
end
local function appearance(s)
    -- SVMax is part of the editor's HSV color space, outside MakeInfo.
    return setmetatable({}, {
        __index=function(_, field) if field == 'SVMax' then return s.Menu.SVMax end; return s.Menu.MakeInfo[field] end,
        __newindex=function(_, field, value) if field == 'SVMax' then s.Menu.SVMax=value else s.Menu.MakeInfo[field]=value end end,
    })
end
local function capture(s)
    return Data.capture(s.Kind == 'character' and appearance(s) or s.Menu.EditedWorldSetting, s.Kind or 'world')
end
local function restore(s, values)
    if s.Kind == 'character' then
        assert(type(CustomPresetsNativeCharacterRefresh) == 'function', 'Character refresh bridge missing')
        local original = capture(s)
        s.Loading = true
        local ok, err = pcall(function()
            Data.apply(appearance(s), 'character', values)
            assert(CustomPresetsNativeCharacterRefresh(s.Menu), 'Character refresh failed')
            Data.apply(appearance(s), 'character', values)
            s.Menu['Request Display'](s.Menu, false)
        end)
        s.Loading = false
        if not ok then Data.apply(appearance(s), 'character', original); error(err) end
        return
    end
    assert(type(CustomPresetsNativeRefresh) == 'function', 'Native refresh bridge missing; preset loading is disabled')
    local settings = s.Menu.EditedWorldSetting
    local original = Data.capture(settings, 'world')
    s.Loading = true
    local ok, err = pcall(function()
        Data.apply(settings, 'world', values)
        assert(CustomPresetsNativeRefresh(s.Menu), 'Native world settings refresh failed')
        -- Native SetupSelectString broadcasts while rebuilding the controls.
        -- Its difficulty handlers can replace EditedWorldSetting with the
        -- original defaults, even though the controls read our independent
        -- native argument snapshot. Commit the selected values after all those
        -- synchronous callbacks have returned; scalar writes emit no UI events.
        Data.apply(settings, 'world', values)
        s.Menu.IsEditedSettingFlag = true
    end)
    s.Loading = false
    if not ok then Data.apply(settings, 'world', original); error(err) end
end
local function queuePreview(s, selection, values, changed)
    if s.Kind ~= 'character' then return end
    local library = s.Library
    if changed then
        local ok, err = pcall(library.invalidatePreview, library, selection)
        if not ok then report(err) end
        s.PreviewTextures[selection.Id] = nil
    elseif library:hasPreview(selection) then return end
    s.PendingPreview = {Selection={Kind='user',Id=selection.Id},Values=values,Delay=1}
end
local function processPreview(s)
    local pending = s.PendingPreview
    if not pending then return end
    if pending.Delay > 0 then pending.Delay = pending.Delay-1; return end
    s.PendingPreview = nil
    -- Never photograph edited settings as if they belonged to a saved preset.
    local current = capture(s)
    for field,value in pairs(pending.Values) do
        local actual = current[field]
        if type(value)=='number' and type(actual)=='number' then
            if math.abs(value-actual)>1e-6*math.max(1,math.abs(value)) then return end
        elseif value~=actual then return end
    end
    if type(CustomPresetsNativeCapturePreview)~='function' then return end
    assert(CustomPresetsNativeCapturePreview(s.Menu,s.Library:previewPath(pending.Selection)), 'Character preview capture failed')
    s.PreviewTextures[pending.Selection.Id] = nil
    refresh(s)
end
buildCharacterCards = function(s)
    for _, item in ipairs(s.UserRows) do
        actions[item.Id] = nil; s.ActionIds[item.Id] = nil
        if valid(item.Box) then item.Box:RemoveFromParent() end
    end
    s.UserRows = {}
    local library = s.Library
    for _, selection in ipairs(library:list()) do
        local name = library:name(selection)
        local length = utf8.len(name)
        if length and length>12 then name=name:sub(1,utf8.offset(name,12)-1)..'…' end
        local card = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
            :Create(s.Menu,s.CardClass,s.Menu:GetOwningPlayer())
        assert(valid(card), 'Native appearance preset card unavailable')
        card.Text_Name:SetText(FText(name))
        local id=key(card)
        actions[id]={Session=s,Command='select',Selection=selection}; s.ActionIds[id]=true
        local texture = s.PreviewTextures[selection.Id]
        if not valid(texture) and library:hasPreview(selection) then
            local ok, result = pcall(function()
                return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
                    :ImportFileAsTexture2D(s.Menu,library:previewPath(selection))
            end)
            if ok and valid(result) then texture=result; s.PreviewTextures[selection.Id]=result end
        end
        if valid(texture) then
            -- Keep the original brush's 206x307 layout and all native hover artwork.
            card.Image_PresetIcon:SetBrushFromTexture(texture,false)
        else
            -- The native card root is not a CanvasPanel. Keep its layout intact
            -- while the missing portrait is generated; the native name stays visible.
            card.Image_PresetIcon:SetVisibility(2)
        end
        if s.Selected.Kind=='user' and s.Selected.Id==selection.Id then card.Frame:SetRenderOpacity(1) end
        local slot=s.PreviewGrid:AddChildToWrapBox(card)
        slot:SetPadding(s.CardPadding)
        s.UserRows[#s.UserRows+1]={Id=id,Box=card}
    end
    s.CardLanguage=t('appearance_presets')
end
local function updateButtons(s)
    local library = s.Library or library
    local editing = s.Kind == 'character' or s.Menu.IsCustomDifficultySetting == true
    local entering = editing and not s.WasEditing
    s.WasEditing = editing
    if entering and s.Selected.Kind ~= 'user' then
        -- Identify matching settings without applying anything on entry.
        local current = capture(s)
        for _, item in ipairs(library:list()) do
            local saved, matches = library:load(item), true
            for field, value in pairs(current) do
                if field ~= 'Difficulty' and (not saved or saved[field] ~= value) then matches = false; break end
            end
            if matches then s.Selected = item; break end
        end
    end
    if entering and s.Kind=='character' and s.Selected.Kind=='user' then
        queuePreview(s,s.Selected,library:load(s.Selected),false)
    end
    local languageLabel = t('save')
    if s.LanguageLabel ~= languageLabel then label(s.Save, languageLabel); s.LanguageLabel = languageLabel end
    label(s.Add, t('add')); label(s.Delete, t('delete'))
    if s.Heading then
        local dirty=false
        if s.Selected.Kind=='user' then
            local saved=library:load(s.Selected)
            for field,value in pairs(capture(s)) do
                local previous=saved and saved[field]
                if type(value)=='number' and type(previous)=='number' then
                    if math.abs(value-previous)>1e-6*math.max(1,math.abs(value)) then dirty=true; break end
                elseif value~=previous then dirty=true; break end
            end
        end
        s.Heading:SetText(FText(t('appearance_presets') .. (dirty and (' · '..t('unsaved')) or '')))
        if s.CardLanguage~=t('appearance_presets') then buildCharacterCards(s) end
    end
    s.Footer:SetVisibility(editing and 0 or 1)
    if s.PresetSelector then s.PresetSelector:SetVisibility(editing and 0 or 1) end
    if s.PresetName then s.PresetName:SetText(FText(s.Selected.Kind == 'user' and library:name(s.Selected) or t('none'))) end
    s.AddBox:SetVisibility(editing and 0 or 1)
    -- Hidden (2) reserves each fixed-width slot; Collapsed (1) shifts the
    -- centered selector and Add button whenever selection changes.
    local actionVisibility = not editing and 1 or (s.Selected.Kind == 'user' and 0 or 2)
    s.SaveBox:SetVisibility(actionVisibility)
    s.DeleteBox:SetVisibility(actionVisibility)
end
local function queue(s, fn)
    s.Generation = s.Generation + 1
    local generation = s.Generation
    ExecuteInGameThread(function()
        if not valid(s.Menu) or sessions[key(s.Menu)] ~= s or not s.Menu:IsVisible() or s.Generation ~= generation then return end
        local ok, err = pcall(fn)
        if not ok then report(err) end
    end)
end
perform = function(s, command, selection)
    local library = s.Library or library
    if command == 'prev' or command == 'next' then
        local choices = library:list()
        if #choices == 0 then return end
        local index = command == 'next' and 0 or 1
        for i, item in ipairs(choices) do
            if item.Kind == s.Selected.Kind and item.Id == s.Selected.Id then index = i; break end
        end
        local target = (index - 1 + (command == 'next' and 1 or -1)) % #choices + 1
        return perform(s, 'select', choices[target])
    elseif command == 'select' then
        assert(selection.Kind == 'user', 'Only saved user presets can be selected here')
        local values = library:load(selection)
        assert(values, 'Preset data missing')
        restore(s, values)
        s.Selected = selection
        queuePreview(s,selection,values,false)
        label(s.Save, t('save'))
    else
        assert(s.Kind == 'character' or s.Menu.IsCustomDifficultySetting == true, 'Preset actions are only available in custom settings')
        local values = capture(s)
        if command == 'save' then
            library:save(s.Selected, values)
            queuePreview(s,s.Selected,values,true)
            label(s.Save, t('saved'))
        elseif command == 'add' then
            openNameDialog(s, values)
            return
        elseif command == 'delete' then
            local choices, position = library:list(), nil
            for i, item in ipairs(choices) do if item.Id == s.Selected.Id then position = i; break end end
            assert(position, 'Selected preset missing')
            local neighbor = choices[position-1] or choices[position+1]
            -- Apply first so a refresh failure cannot leave a deleted selection.
            if neighbor then restore(s, assert(library:load(neighbor), 'Preset data missing')) end
            library:remove(s.Selected)
            s.Selected = neighbor or {Kind='builtin', Id=5}
            s.PendingPreview=nil
            if neighbor then queuePreview(s,neighbor,library:load(neighbor),false) end
            label(s.Save, t('save'))
        end
    end
    refresh(s)
    print('[CustomPresets] ' .. command .. ': ' .. library:name(s.Selected) .. '\n')
end
refresh = function(s)
    if s.Kind=='character' then buildCharacterCards(s) end
    updateButtons(s)
end
local function release(id, s)
    if s.DialogParam then dialogs[key(s.DialogParam)] = nil; s.DialogParam = nil end
    for name in pairs(s.ActionIds) do actions[name] = nil end
    for _, item in ipairs(s.UserRows) do if valid(item.Box) then item.Box:RemoveFromParent() end end
    if s.ScrollSlot and valid(s.ScrollAnchor) then s.ScrollSlot:SetOffsets(s.ScrollOffsets) end
    for _, box in ipairs(s.Boxes) do if valid(box) then box:RemoveFromParent() end end
    sessions[id] = nil
end
local function attach(menu)
    if sessions[key(menu)] then updateButtons(sessions[key(menu)]); return end
    local confirm = menu.WBP_Title_SettingsButton_Confirm
    assert(valid(confirm), 'Original confirm button unavailable')
    local anchor, parent = confirm, confirm:GetParent()
    local canvasClass = StaticFindObject('/Script/UMG.CanvasPanel')
    local depth = 0
    while valid(parent) and not parent:IsA(canvasClass) and depth < 8 do
        anchor, parent = parent, parent:GetParent()
        depth = depth + 1
    end
    assert(valid(parent) and parent:IsA(canvasClass) and valid(menu.VerticalBox_BaseSetting), 'Native confirm canvas unavailable')
    local difficulty = tonumber(menu.EditedWorldSetting.Difficulty)
    local s = {Menu=menu,Confirm=confirm,Parent=parent,Boxes={},ActionIds={},UserRows={},Generation=0,
        Selected={Kind='builtin',Id=difficulty and difficulty >= 1 and difficulty <= 5 and difficulty or 5}}
    local ok, err = pcall(function()
        -- Add a sibling row above the native footer. Never reparent or resize
        -- the original confirm, its container, or its animation target.
        -- Cached Slate geometry is zero in this game/UE4SS build. Use the
        -- native canvas slot, leaving 20 units above its footer boundary.
        local scroll = menu.ScrollBox_DifficultySetting
        local scrollAnchor, scrollParent = scroll, scroll:GetParent()
        local depth = 0
        while valid(scrollParent) and not scrollParent:IsA(canvasClass) and depth < 8 do
            scrollAnchor, scrollParent = scrollParent, scrollParent:GetParent()
            depth = depth + 1
        end
        assert(valid(scrollParent) and scrollParent:IsA(canvasClass), 'Settings scroll canvas unavailable')
        local scrollLayout = copyLayout(scrollAnchor.Slot)
        s.ScrollAnchor, s.ScrollSlot, s.ScrollOffsets = scrollAnchor, scrollAnchor.Slot, scrollLayout.Offsets
        local offsets = {Left=scrollLayout.Offsets.Left,Top=scrollLayout.Offsets.Top,Right=scrollLayout.Offsets.Right,Bottom=scrollLayout.Offsets.Bottom}
        if scrollLayout.Anchors.Minimum.Y ~= scrollLayout.Anchors.Maximum.Y then offsets.Bottom = offsets.Bottom + 40
        else offsets.Bottom = math.max(80, offsets.Bottom - 40) end
        if scrollLayout.Anchors.Minimum.Y == scrollLayout.Anchors.Maximum.Y then
            offsets.Top = s.ScrollOffsets.Top - (s.ScrollOffsets.Bottom-offsets.Bottom) * scrollLayout.Alignment.Y
        end
        s.ScrollSlot:SetOffsets(offsets)
        local selector = construct('HorizontalBox', menu)
        s.PresetSelector = selector
        s.Boxes[#s.Boxes+1] = selector
        local previous = create(s, '‹', 'prev')
        selector:AddChildToHorizontalBox(sized(s, previous, 32)):SetPadding({Left=0,Top=0,Right=6,Bottom=0})
        local name = construct('TextBlock', menu)
        name:SetFont(confirm.Text_Main.Font)
        local nameFont = name.Font; nameFont.Size = 14; name:SetFont(nameFont)
        name:SetJustification(1)
        s.PresetName = name
        local nameBox = sized(s, name, 160)
        selector:AddChildToHorizontalBox(nameBox)
        local following = create(s, '›', 'next')
        selector:AddChildToHorizontalBox(sized(s, following, 32)):SetPadding({Left=6,Top=0,Right=0,Bottom=0})
        local footer = construct('VerticalBox', menu)
        s.Footer = footer
        s.Boxes[#s.Boxes+1] = footer
        local row = construct('HorizontalBox', menu)
        footer:AddChildToVerticalBox(row)
        row:AddChildToHorizontalBox(selector):SetPadding({Left=0,Top=0,Right=12,Bottom=0})
        local layout = copyLayout(anchor.Slot)
        local nativeHeight = layout.Offsets.Bottom > 0 and layout.Offsets.Bottom or 56
        layout.Offsets.Top = layout.Offsets.Top - nativeHeight * layout.Alignment.Y - 20
        layout.Alignment.Y = 1
        layout.AutoSize = true
        layout.Offsets.Right = 0; layout.Offsets.Bottom = 0
        s.FooterSlot = placeCanvas(parent, footer, layout)
        for _, spec in ipairs({{'Save','save',t('save')}, {'Add','add',t('add')}, {'Delete','delete',t('delete')}}) do
            local widget = create(s, spec[3], spec[2])
            local box = sized(s, widget, 128)
            s[spec[1]], s[spec[1] .. 'Box'] = widget, box
            s.Boxes[#s.Boxes+1] = box
            row:AddChildToHorizontalBox(box):SetPadding({Left=3,Top=0,Right=3,Bottom=0})
        end
        sessions[key(menu)] = s
        refresh(s)
        print('[CustomPresets] Preset action row attached above original confirm\n')
    end)
    if not ok then release(key(menu), s); error(err) end
end
local function attachCharacter(menu)
    local id = key(menu)
    if sessions[id] then
        local s = sessions[id]
        if valid(s.Footer) and valid(s.Wrap) then
            if not valid(s.Footer:GetParent()) then s.Wrap:AddChildToWrapBox(s.Footer):SetNewLine(true) end
            updateButtons(s)
            return
        end
        release(id,s)
    end
    local controls = menu.WBP_CharaCre
    local preset = controls.ScrollBoxContentSet.WBP_CharaCre_ScrollBoxContent_Preset
    local wrap = preset.WrapBox_Preset
    assert(valid(wrap), 'Character preset panel unavailable')
    local s = {Menu=menu,Kind='character',Library=characterLibrary,Wrap=wrap,
        Boxes={},ActionIds={},UserRows={},PreviewTextures={},Generation=0,Selected={Kind='builtin',Id=5},
        ButtonClass=assetClass('/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_SettingsButton'),
        CardClass=assetClass('/Game/Pal/Blueprint/UI/UserInterface/CharacterCreation/WBP_CharaCre_PresetButton'),
        CardPadding={Left=0,Top=0,Right=0,Bottom=0}}
    for i=0,wrap:GetChildrenCount()-1 do
        local original=wrap:GetChildAt(i)
        if original:IsA(s.CardClass) then
            local padding=original.Slot.Padding
            s.CardPadding={Left=padding.Left,Top=padding.Top,Right=padding.Right,Bottom=padding.Bottom}
            break
        end
    end
    local ok, err = pcall(function()
        local prototype = create(s,t('add'),'add')
        local sectionClass=assetClass('/Game/Pal/Blueprint/UI/UserInterface/CharacterCreation/WBP_CharaCre_ListContent')
        local footer=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
            :Create(menu,sectionClass,menu:GetOwningPlayer())
        assert(valid(footer), 'Native preset section unavailable')
        s.Footer = footer; s.Boxes[#s.Boxes+1] = footer
        s.Heading=footer.Text_Title
        local body=construct('VerticalBox',menu)
        footer.NamedSlot_InnnerVerticalBox:SetContent(body)
        -- Keep the native title/content inset intact. Extend the whole section
        -- leftward below, matching the built-in line's overhang without moving cards.
        local grid=construct('WrapBox',menu)
        grid.WrapSize=wrap.WrapSize; grid.bExplicitWrapSize=wrap.bExplicitWrapSize
        local spacing=wrap.InnerSlotPadding
        grid:SetInnerSlotPadding({X=spacing.X,Y=spacing.Y})
        s.PreviewGrid=grid
        body:AddChildToVerticalBox(grid):SetPadding({Left=0,Top=8,Right=0,Bottom=12})
        local row = construct('HorizontalBox', menu); body:AddChildToVerticalBox(row)
        for index, spec in ipairs({{'Save','save','save'},{'Add','add','add'},{'Delete','delete','delete'}}) do
            local widget = spec[1]=='Add' and prototype or create(s, t(spec[3]), spec[2])
            local buttonFont=widget.Text_Main.Font; buttonFont.Size=13; widget.Text_Main:SetFont(buttonFont)
            local box = sized(s, widget, spec[1]=='Delete' and 96 or 120)
            s[spec[1]], s[spec[1]..'Box'] = widget, box
            row:AddChildToHorizontalBox(box):SetPadding({Left=index==1 and s.CardPadding.Left or 8,Top=2,Right=0,Bottom=8})
        end
        local sectionSlot=wrap:AddChildToWrapBox(footer)
        sectionSlot:SetNewLine(true)
        sectionSlot:SetFillEmptySpace(true)
        sectionSlot:SetPadding({Left=-14,Top=16,Right=0,Bottom=8})
        sessions[id] = s; refresh(s)
        print('[CustomPresets] Character preset controls attached\n')
    end)
    if not ok then release(id,s); error(err) end
end
local function installHooks()
    local closePath = '/Script/Pal.PalUserWidgetStackableUI:Close'
    if not hooks.RenameClose and valid(StaticFindObject(closePath)) then
        RegisterHook(closePath, function(context)
            if not next(dialogs) then return end
            local window = unwrap(context)
            if not valid(window) or not window:IsA(StaticFindObject(NAME_WINDOW .. '.WBP_Title_WorldSettings_NameWindow_C')) then return end
            local param = window:GetParam()
            local entry = valid(param) and dialogs[key(param)]
            if not entry then return end
            dialogs[key(param)] = nil
            entry.Session.DialogParam = nil
            -- Native confirm writes OutString before Close; cancellation leaves it empty.
            local value = param.OutString
            local name = type(value) == 'string' and value or value:ToString()
            if name == '' then return end
            queue(entry.Session, function()
                local library = entry.Session.Library or library
                entry.Session.Selected = library:add(entry.Values, name)
                queuePreview(entry.Session,entry.Session.Selected,entry.Values,true)
                label(entry.Session.Save, t('save'))
                refresh(entry.Session)
            end)
        end)
        hooks.RenameClose = true
    end
    if not hooks.Click and valid(StaticFindObject(CLICK)) then
        RegisterHook(CLICK, function(context)
            local widget = unwrap(context)
            local entry = valid(widget) and actions[key(widget)]
            if entry then queue(entry.Session, function() perform(entry.Session, entry.Command, entry.Selection) end) end
        end)
        hooks.Click = true
    end
    local characterPreset = '/Game/Pal/Blueprint/UI/CharacterMake/WBP_CharacterMake.WBP_CharacterMake_C:ApplyPreset'
    if not hooks.CharacterPreset and valid(StaticFindObject(characterPreset)) then
        RegisterHook(characterPreset, function(context)
            local menu = unwrap(context)
            local s = valid(menu) and sessions[key(menu)]
            if not s or s.Loading then return end
            s.Selected = {Kind='builtin',Id=5}
            s.PendingPreview=nil
            queue(s, function() label(s.Save,t('save')); refresh(s) end)
        end)
        hooks.CharacterPreset = true
    end
    if not hooks.CardClick and valid(StaticFindObject(CARD_CLICK)) then
        RegisterHook(CARD_CLICK, function(context)
            local widget=unwrap(context)
            local entry=valid(widget) and actions[key(widget)]
            if entry then queue(entry.Session,function() perform(entry.Session,entry.Command,entry.Selection) end) end
        end)
        hooks.CardClick=true
    end
    local path = WORLD .. ':ApplyDifficultyPreset'
    if not hooks.Difficulty and valid(StaticFindObject(path)) then
        RegisterHook(path, function(context, difficulty)
            local menu = unwrap(context)
            if not valid(menu) then return end
            local s = sessions[key(menu)]
            local id = tonumber(unwrap(difficulty))
            -- Observe built-in selection only to leave the current user preset.
            -- Never load overrides or change the native difficulty parameters.
            if not s or s.Loading or not id or id < 1 or id > 4 then return end
            local selected = {Kind='builtin',Id=id}
            s.Selected = selected
            queue(s, function()
                label(s.Save, t('save'))
                refresh(s)
            end)
        end)
        hooks.Difficulty = true
    end
end
function M.start()
    local queued = false
    LoopAsync(750, function()
        local installed, failure = pcall(installHooks)
        if not installed then report(failure) end
        if queued then return end
        queued = true
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                for id, s in pairs(sessions) do
                    if not valid(s.Menu) or not s.Menu:IsVisible() then release(id, s) end
                end
                for _, menu in ipairs(FindAllOf('WBP_CharacterMake_C') or {}) do
                    if valid(menu) and menu:IsVisible() and not key(menu):find('Default__',1,true) then
                        local success, problem = pcall(attachCharacter, menu)
                        if not success then report(problem) end
                        local s=sessions[key(menu)]
                        if s then
                            local captured, failure=pcall(processPreview,s)
                            if not captured then report(failure) end
                        end
                    end
                end
                for _, menu in ipairs(FindAllOf('WBP_Title_WorldSettings_C') or {}) do
                    if valid(menu) and menu:IsVisible() and not key(menu):find('Default__',1,true) then
                        local success, problem = pcall(attach, menu)
                        if not success then report(problem) end
                    end
                end
            end)
            queued = false
            if not ok then report(err) end
        end)
    end)
end
return M
