package.path = SCRIPTS .. '/?.lua;' .. package.path
require('CustomPresets.I18n').configure('zh-Hans')
local Store = require('CustomPresets.Store')
local Schema = require('CustomPresets.Schema')
local schema = {{'text', 'string'}, {'flag', 'boolean'}, {'value', 'number'}}
local values = {text = '中文\n=%;return os.exit()', flag = false, value = 0.125}
local encoded = Store.encode(values, schema)
local decoded = Store.decode(encoded, schema)
assert(decoded.text == values.text and decoded.flag == false and decoded.value == 0.125)
for _, data in ipairs({'return os.exit()', 'MorePresets:2\n', encoded .. 'text=duplicate\n', encoded:gsub('flag=false', 'flag=bad'), encoded:gsub('value=0.125', 'value=nan')}) do
    assert(not pcall(Store.decode, data, schema))
end
assert(not pcall(Store.encode, {text='', flag=true, value=math.huge}, schema))
local path = PRESETS .. '/test.preset'
Store.write(path, values, schema)
values.value = 4
Store.write(path, values, schema)
assert(Store.read(path, schema).value == 4 and Store.read(path .. '.bak', schema).value == 0.125)

local function data()
    local result={}
    for _, field in ipairs(Schema.world) do
        if field[2]=='boolean' then result[field[1]]=false
        elseif field[2]=='number' then result[field[1]]=1
        else result[field[1]]='Test' end
    end
    return result
end
local Library=require('CustomPresets.Library')
local lib=Library.new(PRESETS..'/library/')
local built={Kind='builtin',Id=2}
local values=data(); values.ExpRate=2.5
assert(not pcall(lib.save,lib,built,values), 'Original presets are read-only')
assert(lib:load(built)==nil and #lib:list()==0)
assert(not pcall(lib.remove,lib,built), 'Original presets cannot be deleted')
local user=lib:add(values, "用户预设 1"); values.ExpRate=8
lib:save(user,values)
assert(lib:load(user).ExpRate==8 and lib:load(built)==nil)
local user2=lib:add(values, "  我的休闲世界  ")
assert(Library.new(PRESETS..'/library/'):name(user2)=='我的休闲世界', 'Names survive restart')
assert(lib:load(user2).ExpRate==8, 'Naming preserves saved settings')
for _, bad in ipairs({'', '   ', 'bad\nname', string.rep('中',31)}) do
    assert(not pcall(lib.add,lib,values,bad))
end
Store.write(PRESETS..'/library/user-'..user2.Id..'.preset.name.preset', {Name='FString: 000012345678'}, {{'Name','string'}})
assert(lib:name(user2)=='用户预设 '..user2.Id, 'Recover previously stored address labels')
assert(not pcall(lib.add,lib,values,'FString: 000012345678'))
Store.write(PRESETS..'/library/user-'..user2.Id..'.preset.name.preset', {Name='我的休闲世界'}, {{'Name','string'}})
lib:remove(user)
assert(#lib:list()==1 and lib:list()[1].Id==user2.Id)
assert(not pcall(lib.save,lib,user,values) and not pcall(lib.load,lib,user))
assert(Library.new(PRESETS..'/library/'):list()[1].Id==user2.Id, 'Catalogue survives restart')
local duplicateA=lib:add(values, '同名预设')
local duplicateB=lib:add(values, '同名预设')
assert(duplicateA.Id~=duplicateB.Id and lib:name(duplicateA)==lib:name(duplicateB), 'Allow duplicate names with independent identity')
lib:remove(duplicateA)
assert(lib:load(duplicateB).ExpRate==8, 'Deleting one duplicate preserves the other')
assert(not pcall(lib.add,lib,values,''), 'Require a name before creating a preset')

local serial, widgets, tasks=0,{},{}
local handlers,tick,onGameThread,insideClick={},nil,false,false
local function ref(v) return {get=function() return v end} end
local function object(kind)
    serial=serial+1
    local o={id=tostring(serial),Kind=kind,visible=true,valid=true,children={}}
    function o:IsValid() return self.valid end
    function o:IsVisible() return self.visible end
    function o:GetFullName() return self.id end
    function o:IsA(c)
        if c.Path:find('WBP_Title_WorldSettings_NameWindow_C',1,true) then return self.Kind=='OfficialNameWindow' end
        if c.Path:find('WBP_CharaCre_PresetButton_C',1,true) then return self.Kind=='NativeAppearanceCard' end
        if c.Path=='/Script/Pal.PalEditableTextBox' then return self.Kind=='PalEditableTextBox' end
        if c.Path=='/Script/UMG.PanelWidget' then return self.Kind=='CanvasPanel' end
        return c.Path=='/Script/UMG.'..self.Kind
    end
    function o:SetText(t) self.text=t end
    function o:GetText() return self.text end
    function o:SetKeyboardFocus() self.focused=true end
    function o:SetFont(v) self.Font={Size=v.Size} end
    function o:SetJustification(v) self.justification=v end
    function o:SetColorAndOpacity(v) self.color=v end
    function o:SetBrushFromTexture(v) self.texture=v end
    function o:SetStretch(v) self.stretch=v end
    function o:GetChildrenCount() return #self.children end
    function o:GetChildAt(i) return self.children[i+1] end
    function o:SetToolTipText(t) self.tooltip=t end
    function o:SetVisibility(v) self.visibility=v end
    function o:SetRenderOpacity(v) self.opacity=v end
    function o:SetRenderTranslation(v) self.translation=v end
    function o:SetWidthOverride(v) self.width=v end
    function o:SetHeightOverride(v) self.height=v end
    function o:ClearWidthOverride() self.width=nil end
    function o:GetParent() return self.parent end
    function o:RemoveFromParent() self.parent=nil end
    function o:GetCachedGeometry() error('Layout must not depend on unavailable Slate geometry') end
    function o:GetClass() return {Path='NativeTitleButton'} end
    function o:AddChild(child) child.parent=self; self.children[#self.children+1]=child end
    return o
end
local function slot()
    local o={anchors={Minimum={X=.5,Y=1},Maximum={X=.5,Y=1}},alignment={X=.5,Y=1},offsets={Left=0,Top=-30,Right=240,Bottom=56},auto=false,z=0}
    function o:GetAnchors() return self.anchors end
    function o:GetAlignment() return self.alignment end
    function o:GetOffsets() return self.offsets end
    function o:GetAutoSize() return self.auto end
    function o:GetZOrder() return self.z end
    function o:SetAnchors(v) self.anchors=v end
    function o:SetAlignment(v) self.alignment=v end
    function o:SetOffsets(v) self.offsets=v end
    function o:SetAutoSize(v) self.auto=v end
    function o:SetZOrder(v) self.z=v end
    function o:SetPadding(v) self.Padding=v end
    function o:SetNewLine(v) self.newLine=v end
    function o:SetFillEmptySpace(v) self.fillEmptySpace=v end
    return o
end
local function panel(kind)
    local o=object(kind)
    function o:AddChildToCanvas(child) self:AddChild(child); child.Slot=slot(); return child.Slot end
    function o:AddChildToHorizontalBox(child) self:AddChild(child); child.Slot=slot(); return child.Slot end
    function o:AddChildToVerticalBox(child) self:AddChild(child); child.Slot=slot(); return child.Slot end
    function o:AddChildToWrapBox(child) self:AddChild(child); child.Slot=slot(); return child.Slot end
    return o
end
function FText(s) return s end
local character
local menu=object('Menu')
local resetDuringRefresh=false
menu.WidgetTree={}; menu.IsCustomDifficultySetting=true
menu.EditedWorldSetting=data(); menu.EditedWorldSetting.Difficulty=2
menu.EditedWorldSetting.WorldName='Keep name'; menu.EditedWorldSetting.ServerPassword='private'
function menu:GetOwningPlayer() return self end
function menu:Push(class,param)
    assert(onGameThread and not insideClick)
    assert(class.Path:find('WBP_Title_WorldSettings_NameWindow_C',1,true))
    local window=object('OfficialNameWindow')
    local title=object('Text')
    function title:GetFullName() return menu.failTitle and 'UnavailableTitle' or 'TextBlock Window.WidgetTree.Text_Head' end
    local root=panel('CanvasPanel'); root:AddChildToCanvas(title)
    window.WidgetTree={RootWidget=root}
    window.TestTitle=title -- Text_Head is not an exposed Blueprint variable.
    function window:GetParam() return param end
    self.dialog=window; self.dialogParam=param
    return {A=1,B=2,C=3,D=4} -- Native Push returns a widget GUID, not the widget.
end
function menu:ApplyWorldSettingToUI() error('Do not pass the oversized struct through Lua UFunction dispatch') end
function CustomPresetsNativeRefresh(target)
    assert(target == menu)
    assert(onGameThread and not insideClick, 'Refresh must not re-enter the click stack')
    menu.refreshed=menu.EditedWorldSetting
    -- Native UI refresh may report Custom; this must retain user identity.
    handlers.Difficulty(ref(menu),ref(5))
    if resetDuringRefresh then
        -- Real SetupSelectString broadcasts selection changes during refresh.
        -- Built-in difficulty handlers can reset the editor while controls are
        -- being populated from the independent native parameter snapshot.
        menu.EditedWorldSetting.ExpRate=99
        menu.EditedWorldSetting.Difficulty=2
    end
    return true
end
local originalParent=panel('CanvasPanel')
local confirm=object('Confirm'); confirm.Text_Main=object('Text'); confirm.Text_Main.Font={Size=24}
confirm.Base=object('ConfirmArtwork')
originalParent:AddChildToCanvas(confirm)
menu.WBP_Title_SettingsButton_Confirm=confirm
function menu:ApplyDifficultyPreset(id) self.EditedWorldSetting.Difficulty=id; self.EditedWorldSetting.ExpRate=99; handlers.Difficulty(ref(self),ref(id)) end
menu.VerticalBox_BaseSetting=panel('VerticalBox')
menu.ScrollBox_DifficultySetting=panel('ScrollBox')
originalParent:AddChildToCanvas(menu.ScrollBox_DifficultySetting)
menu.ScrollBox_DifficultySetting.Slot.offsets.Bottom=600
local titleClassReady=true
local titleClassPath='/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_SettingsButton.WBP_Title_SettingsButton_C'
local loadedWidgetPath
function LoadAsset(path)
    assert(onGameThread, 'Load widgets on the game thread')
    assert(path==titleClassPath, 'Asset registry requires the full generated-class object path')
    loadedWidgetPath=path; titleClassReady=true
end
function StaticFindObject(pathname)
    local o=object('Class'); o.Path=pathname
    if pathname==titleClassPath and not titleClassReady then o.valid=false end
    function o:ImportFileAsTexture2D(_,path) local texture=object("Texture"); texture.path=path; return texture end
    function o:GetLocalSize(g) return {X=g.W,Y=g.H} end
    function o:LocalToAbsolute(g,p) return {X=g.X+p.X,Y=g.Y+p.Y} end
    function o:AbsoluteToLocal(g,p) return {X=p.X-g.X,Y=p.Y-g.Y} end
    function o:Create(_,class)
        if class.Path:find('WBP_Title_WorldSettings_NameWindow_C',1,true) then
            local window=object('OfficialNameWindow')
            local root=panel('CanvasPanel')
            root:AddChildToCanvas(object('PalEditableTextBox'))
            window.WidgetTree={RootWidget=root}
            return window
        end
        if class.Path:find('WBP_CharaCre_ListContent_C',1,true) then
            local section=object('NativePresetSection')
            section.Text_Title=object('Text')
            section.NamedSlot_InnnerVerticalBox=panel('NamedSlot')
            section.NamedSlot_InnnerVerticalBox.Slot=slot()
            section.NamedSlot_InnnerVerticalBox.Slot.Padding={Left=14,Top=0,Right=14,Bottom=0}
            function section.NamedSlot_InnnerVerticalBox:SetContent(child) self:AddChild(child) end
            return section
        end
        if class.Path:find('WBP_CharaCre_PresetButton_C',1,true) then
            local card=object('NativeAppearanceCard'); card.Text_Name=object('Text'); card.Text_Name.Font={Size=24}
            card.Text_Main=card.Text_Name -- Test lookup alias, not a production widget property.
            card.Image_PresetIcon=object('Image'); card.Frame=object('Image'); card.WidgetTree={RootWidget=object('NativeCardRoot')}
            widgets[#widgets+1]=card; return card
        end
        assert(class.Path=='NativeTitleButton' or class.Path:find('WBP_Title_SettingsButton_C',1,true), 'Use original settings button style')
        local w=object('Button'); w.Text_Main=object('Text'); w.Text_Main.Font={Size=24}; w.WBP_PalInvisibleButton=object('Input'); w.WidgetTree={RootWidget=panel('CanvasPanel')}; widgets[#widgets+1]=w
        return w
    end
    return o
end
function StaticConstructObject(class)
    local kind=class.Path:match('UMG%.(.+)$')
    local result=panel(kind)
    if kind=='WrapBox' then function result:SetInnerSlotPadding(v) self.InnerSlotPadding=v end end
    if kind=='EditableTextBox' then
        result.SetFont=function() error('EditableTextBox has no reflected SetFont') end
    end
    return result
end
function FindAllOf(class)
    if class=='WBP_Title_WorldSettings_NameWindow_C' then
        local result={}
        if menu.dialog then result[#result+1]=menu.dialog end
        if character and character.dialog then result[#result+1]=character.dialog end
        return result
    end
    if class=='WBP_Title_WorldSelect_CreateWorld_ListContent_C' then return {} end
    if class=='WBP_CharacterMake_C' then return character and {character} or {} end
    assert(class=='WBP_Title_WorldSettings_C'); return {menu}
end
function RegisterHook(pathname,fn,post)
    assert(not onGameThread)
    if pathname:find(':Update Local World List Content',1,true) then handlers.WorldListPre=fn; handlers.WorldListPost=post; return end
    if pathname=='/Script/Pal.PalUserWidgetStackableUI:Close' then handlers.Close=fn
    elseif pathname:find('WBP_CharaCre_PresetButton_C:',1,true) then handlers.CardClick=fn
    elseif pathname:find('WBP_CharacterMake_C:ApplyPreset',1,true) then handlers.CharacterPreset=fn
    elseif pathname:find(':ApplyDifficultyPreset',1,true) then handlers.Difficulty=fn
    else
        assert(pathname:find('WBP_Title_SettingsButton_C:',1,true))
        handlers.Click=fn
    end
end
function LoopAsync(_,fn) tick=fn end
function ExecuteInGameThread(fn) tasks[#tasks+1]=fn end
local function flush()
    while #tasks>0 do
        local fn=table.remove(tasks,1); onGameThread=true; fn(); onGameThread=false
    end
end
local function latest(text)
    for i=#widgets,1,-1 do if widgets[i].Text_Main.text==text then return widgets[i] end end
    error('Missing button '..text)
end
local function press(button)
    insideClick=true
    if button.Kind=='NativeAppearanceCard' then handlers.CardClick(ref(button)) else handlers.Click(ref(button)) end
    insideClick=false; flush()
end
assert(loadfile(UI_PATH))().start()
tick(); flush()
local save,add,delete=latest('保存当前预设'),latest('添加为新预设'),latest('删除预设')
assert(confirm.parent==originalParent, 'Do not reparent confirm')
assert(save.parent.parent~=confirm.parent and save.parent.parent.parent.parent==originalParent)
assert(save.parent.parent.parent.Slot:GetOffsets().Top==-106, 'Clear native footer boundary using canvas layout even without Slate geometry')
assert(save.parent.parent.parent.Slot:GetAlignment().Y==1, 'Anchor row bottom above native footer')
assert(save.parent.parent.parent.Slot:GetOffsets().Left==0, 'Preserve native centered canvas anchor')
assert(save.WBP_PalInvisibleButton.opacity==0, 'Input layer must not obscure native button visuals')
assert(menu.ScrollBox_DifficultySetting.Slot.offsets.Bottom==560, 'Reserve footer space in the settings viewport')
assert(#save.parent.parent.parent.children==1, 'Do not construct an unused preset title row')
assert(add.parent.height==32 and add.parent.width==128, 'Compact action button dimensions')
assert(add.Text_Main.Font.Size==14)
local selector=latest('‹').parent.parent
assert(selector.parent==save.parent.parent, 'Selector and preset actions must share the same footer row')
assert(menu.ScrollBox_DifficultySetting.Slot.offsets.Top==-70, 'Reclaim former top selector area and keep original viewport top')
assert(delete.parent.visibility==2, 'Hide delete while retaining its layout slot')
menu.EditedWorldSetting.ExpRate=3.5
assert(save.parent.visibility==2 and add.parent.visibility==0)
press(latest('›')); assert(menu.EditedWorldSetting.Difficulty==2, 'Empty selector preserves current settings')
local uiLib=Library.new(PRESETS..'/')
assert(uiLib:load(built)==nil and menu.EditedWorldSetting.Difficulty==2)
press(add)
assert(#uiLib:list()==0, 'Opening name dialog must not create a preset')
assert(menu.dialogParam.DefaultInputName=='Custom Preset', 'New presets default to Custom Preset without numbering')
assert(menu.dialog.TestTitle.text=='预设名称')
menu.dialogParam.OutString=setmetatable({ToString=function() return '' end}, {__tostring=function() return 'FString: 000012345678' end})
handlers.Close(ref(menu.dialog)); flush()
assert(#uiLib:list()==0, 'Cancel must not create a preset')
press(add)
menu.EditedWorldSetting.ExpRate=99
menu.dialogParam.OutString=setmetatable({ToString=function() return '休闲世界' end}, {__tostring=function() return 'FString: 000012345678' end})
handlers.Close(ref(menu.dialog)); flush()
assert(#uiLib:list()==1 and uiLib:name({Kind='user',Id=1})=='休闲世界')
assert(uiLib:load({Kind='user',Id=1}).ExpRate==3.5, 'Save settings captured when add was clicked')
menu.EditedWorldSetting.ExpRate=7
press(save)
assert(uiLib:load({Kind='user',Id=1}).ExpRate==7 and uiLib:load(built)==nil)
menu.failTitle=true
menu.EditedWorldSetting.ExpRate=9
press(add)
menu.dialogParam.OutString=setmetatable({ToString=function() return '休闲世界' end}, {__tostring=function() return 'FString: 000012345678' end})
handlers.Close(ref(menu.dialog)); flush()
assert(#uiLib:list()==2 and uiLib:name({Kind='user',Id=2})=='休闲世界', 'Title failure cannot block creation; duplicates allowed')
menu.failTitle=false
for _,widget in ipairs(widgets) do assert(widget.Text_Main.text~='重命名', 'Remove rename button') end
local nativeBridge = CustomPresetsNativeRefresh
CustomPresetsNativeRefresh = nil
menu.EditedWorldSetting.ExpRate=13
press(latest('‹'))
assert(menu.EditedWorldSetting.ExpRate==13, 'Missing bridge must stop before changing editor data')
CustomPresetsNativeRefresh = nativeBridge
resetDuringRefresh=true
press(latest('‹'))
resetDuringRefresh=false
assert(menu.EditedWorldSetting.ExpRate==7 and delete.parent.visibility==0)
press(delete)
assert(#uiLib:list()==1 and uiLib:list()[1].Id==2 and delete.parent.visibility==0)
assert(menu.EditedWorldSetting.ExpRate==9, 'Deleting the first preset applies the next preset')
menu.EditedWorldSetting.ExpRate=99
menu.EditedWorldSetting.Difficulty=2
resetDuringRefresh=true
handlers.Difficulty(ref(menu),ref(2)); flush()
assert(menu.EditedWorldSetting.ExpRate==99 and delete.parent.visibility==2 and save.parent.visibility==2)
assert(menu.EditedWorldSetting.Difficulty==2, 'Built-in selection must keep game defaults and must not load saved overrides')
resetDuringRefresh=false
assert(menu.EditedWorldSetting.WorldName=='Keep name' and menu.EditedWorldSetting.ServerPassword=='private')
menu.IsCustomDifficultySetting=false; tick(); flush()
assert(save.parent.visibility==1 and add.parent.visibility==1 and confirm.visible)
menu.IsCustomDifficultySetting=true; tick(); flush()
assert(save.parent.visibility==2 and add.parent.visibility==0)
assert(menu.EditedWorldSetting.ExpRate==99, 'Entering custom settings preserves manually chosen values')
press(latest('›')); assert(menu.EditedWorldSetting.ExpRate==9, 'Switcher selects saved user presets only')
press(latest('›')); assert(menu.EditedWorldSetting.ExpRate==9, 'Single saved preset wraps without selecting built-in difficulties')
assert(menu.VerticalBox_BaseSetting:GetChildrenCount()==0, 'No preset list on the main settings page')
assert(save.parent.visibility==0 and delete.parent.visibility==0)
local total=#widgets; tick(); flush(); assert(#widgets==total)
insideClick=true; handlers.Click(ref(add)); insideClick=false
menu.visible=false; flush(); assert(#uiLib:list()==1, 'Closing cancels deferred add')
tick(); flush()
assert(confirm.parent==originalParent and confirm.Slot:GetOffsets().Right==240, 'Restore original footer on close')
assert(menu.ScrollBox_DifficultySetting.Slot.offsets.Bottom==600, 'Restore content viewport on close')
-- Some native layouts already use a horizontal footer. Leave the existing
-- confirm in place rather than reparenting it or changing its slot/order.
local horizontal=panel('HorizontalBox')
confirm:RemoveFromParent(); originalParent:AddChildToCanvas(horizontal); horizontal:AddChildToHorizontalBox(confirm)
local originalSlot=confirm.Slot
menu.EditedWorldSetting.ExpRate=77
menu.visible=true; tick(); flush()
assert(menu.EditedWorldSetting.ExpRate==77, 'Reopening never overwrites existing custom settings')
assert(confirm.parent==horizontal and confirm.Slot==originalSlot)
menu.visible=false; tick(); flush()
assert(confirm.parent==horizontal and confirm.Slot==originalSlot)


-- Delete the last item: select its predecessor and apply distinct values.
menu.visible=true; tick(); flush()
menu.EditedWorldSetting.ExpRate=12
press(latest('添加为新预设'))
menu.dialogParam.OutString='Another'
handlers.Close(ref(menu.dialog)); flush()
press(latest('删除预设'))
assert(#uiLib:list()==1 and menu.EditedWorldSetting.ExpRate==9, 'Deleting last selects previous')
press(latest('删除预设'))
assert(#uiLib:list()==0 and menu.EditedWorldSetting.ExpRate==9, 'Deleting sole preset preserves current settings')
menu.IsCustomDifficultySetting=false; tick(); flush()
menu.IsCustomDifficultySetting=true; tick(); flush()
assert(menu.EditedWorldSetting.ExpRate==9, 'Empty library keeps current settings on entry')

local i18n=require('CustomPresets.I18n')
for _,case in ipairs({{'en-US','Save preset','Preset name'}, {'zh-CN','保存当前预设','预设名称'}, {'zh-TW','儲存目前預設','預設名稱'}, {'ja-JP','上書き保存','プリセット名'}, {'fr-FR','Save preset','Preset name'}}) do
    i18n.configure(case[1]); tick(); flush()
    assert(latest(case[2]) and i18n.text('title')==case[3])
    assert(lib:name(user2)=='我的休闲世界', 'Localization must not translate user names')
end
local originalFind=StaticFindObject
function StaticFindObject(path)
    if path=='/Script/Engine.Default__KismetInternationalizationLibrary' then
        return {GetCurrentCulture=function() return {ToString=function() return 'zh-Hant' end} end}
    end
    return originalFind(path)
end
i18n.configure('auto')
assert(i18n.text('save')=='儲存目前預設', 'Read game culture through FString contents')
StaticFindObject=originalFind
i18n.configure('zh-Hans')

-- Character appearance presets use the same management flow but a separate catalogue.
function FName(value) return {ToString=function() return value end} end
local function appearance()
    local value={}
    for _,field in ipairs(Schema.character) do
        local parent,leaf=field[1]:match('^(.*)%.([^.]*)$')
        local target=value
        if parent then value[parent]=value[parent] or {}; target=value[parent] else leaf=field[1] end
        target[leaf]=field[2]=='name' and FName('Default') or 0.5
    end
    value.VoiceID=2
    value.PlayerName='Never copy player name'
    value.EquipmentBodyMeshName=FName('Keep equipped armor')
    return value
end
menu.visible=false; tick(); flush()
i18n.configure('zh-Hans')
character=object('CharacterEditor'); character.WidgetTree={}
titleClassReady=false -- Enter character creation after the title assets unloaded.
character.MakeInfo=appearance(); character.SVMax=1
character.GetOwningPlayer=menu.GetOwningPlayer; character.Push=menu.Push
local wrap=panel('WrapBox')
function wrap:AddChildToWrapBox(child) self:AddChild(child); child.Slot=slot(); return child.Slot end
local originalPreset=object('NativeAppearanceCard'); wrap:AddChild(originalPreset)
originalPreset.Slot=slot(); originalPreset.Slot.Padding={Left=4,Top=3,Right=4,Bottom=3}
wrap.WrapSize=500; wrap.bExplicitWrapSize=false; wrap.InnerSlotPadding={X=12,Y=10}
function wrap:SetInnerSlotPadding(v) self.InnerSlotPadding=v end
character.WBP_CharaCre={Text_PlayerName={Font={Size=24}},ScrollBoxContentSet={WBP_CharaCre_ScrollBoxContent_Preset={WrapBox_Preset=wrap}}}
character['Request Display']=function(self,delay) assert(self==character and delay==false); self.preview=(self.preview or 0)+1 end
function CustomPresetsNativeCharacterRefresh(target)
    assert(target==character and onGameThread and not insideClick)
    target.MakeInfo.ArmVolume=999 -- Simulate synchronous UI notifications.
    return true
end
tick(); flush()
assert(wrap.children[1]==originalPreset and #wrap.children==2, 'Preserve original character presets')
assert(wrap.children[2].Kind=='NativePresetSection', 'Reuse the complete native title bar')
assert(wrap.children[2].Text_Title.text=='自定义预设', 'Localized native section title')
assert(loadedWidgetPath==titleClassPath, 'Character controls must load their button asset from a cold state')
local function appearanceCard(index)
    local active={}
    for _,widget in ipairs(widgets) do if widget.Kind=='NativeAppearanceCard' and widget:GetParent() then active[#active+1]=widget end end
    return assert(active[index], 'Appearance card missing')
end
local charSave,charAdd,charDelete=latest('保存当前预设'),latest('添加为新预设'),latest('删除预设')
local characters=Library.new(PRESETS..'/', 'character')
assert(#characters:list()==0 and #uiLib:list()==0)
local function addCharacter(name)
    press(charAdd)
    character.dialogParam.OutString={ToString=function() return name end}
    handlers.Close(ref(character.dialog)); flush()
end
character.MakeInfo.ArmVolume=0.25
character.MakeInfo.HairColor.B=0.15; character.MakeInfo.VoiceID=4; character.SVMax=0.85
addCharacter('造型')
assert(#characters:list()==1 and characters:name({Kind='user',Id=1})=='造型')
assert(#uiLib:list()==0, 'Do not mix world and character catalogues')
character.MakeInfo.ArmVolume=0.75; press(charSave)
character.MakeInfo.ArmVolume=0.5; character.MakeInfo.HairColor.B=0.9; character.MakeInfo.VoiceID=6; character.SVMax=0.65
addCharacter('造型')
character.MakeInfo.PlayerName='Keep current name'
press(appearanceCard(1))
assert(character.MakeInfo.ArmVolume==0.75 and character.preview==1, 'Restore appearance, refresh controls and preview')
assert(character.MakeInfo.HairColor.B==0.15 and character.MakeInfo.VoiceID==4 and character.SVMax==0.85, 'Restore colors, voice and HSV range')
assert(character.MakeInfo.PlayerName=='Keep current name' and character.MakeInfo.EquipmentBodyMeshName:ToString()=='Keep equipped armor')
local bridge=CustomPresetsNativeCharacterRefresh
CustomPresetsNativeCharacterRefresh=nil
press(appearanceCard(2)); assert(character.MakeInfo.ArmVolume==0.75, 'Missing native bridge must not mutate appearance')
CustomPresetsNativeCharacterRefresh=function() return false end
press(appearanceCard(2)); assert(character.MakeInfo.ArmVolume==0.75 and character.SVMax==0.85, 'Failed native refresh rolls back all appearance fields')
CustomPresetsNativeCharacterRefresh=bridge
press(charDelete)
assert(#characters:list()==1 and character.MakeInfo.ArmVolume==0.5, 'Deleting appearance applies adjacent appearance')
character.MakeInfo.ArmVolume=0.33
character.visible=false; tick(); flush()
character.visible=true; tick(); flush()
assert(character.MakeInfo.ArmVolume==0.33, 'Opening character presets preserves current customization')
assert(Library.new(PRESETS..'/', 'character'):load({Kind='user',Id=2}).ArmVolume==0.5, 'Appearance survives restart')

character.MakeInfo.ArmVolume=0.44
handlers.CharacterPreset(ref(character)); flush()
assert(character.MakeInfo.ArmVolume==0.44 and latest('保存当前预设').parent.visibility==2, 'Original appearance selection clears user identity without overwriting native choice')
assert(wrap.children[#wrap.children].Slot.newLine==true, 'Management block starts on its own line')

-- Preview creation is delayed and only captures the saved appearance.
local capturedPreviews=0
function CustomPresetsNativeCapturePreview(target,path)
    assert(target==character and onGameThread and not insideClick)
    capturedPreviews=capturedPreviews+1
    local file=assert(io.open(path,'wb')); file:write('\137PNG\13\10\26\10test'); file:close()
    return true
end
local selectedAppearance={Kind='user',Id=2}
press(latest('造型'))
tick(); flush(); assert(capturedPreviews==0, 'Wait for rendered appearance to settle')
tick(); flush(); assert(capturedPreviews==1 and characters:hasPreview(selectedAppearance), 'Generate a persistent PNG preview')
local card=latest('造型')
assert(card.Kind=='NativeAppearanceCard' and card.Image_PresetIcon.texture.path==characters:previewPath(selectedAppearance), 'Reuse original preset card and preserve native image dimensions')
assert(card.Slot.Padding.Left==4 and card.Slot.Padding.Bottom==3, 'Match original preset slot spacing')
tick(); flush(); assert(capturedPreviews==1, 'Do not read back the render target every tick')
character.MakeInfo.ArmVolume=0.6
tick(); flush()
local section=wrap.children[#wrap.children]
assert(section.Text_Title.text=='自定义预设 · 未保存修改', 'Show unsaved appearance edits')
assert(section.Slot.Padding.Left==-14, 'Extend native title line left of aligned text and cards')
assert(section.NamedSlot_InnnerVerticalBox.children[1].translation==nil, 'Keep native title and card insets identical')
press(latest('保存当前预设'))
assert(section.Text_Title.text=='自定义预设', 'Clear unsaved marker after saving')
assert(not characters:hasPreview(selectedAppearance), 'Invalidate outdated preview when settings change')
character.MakeInfo.ArmVolume=0.7
tick(); flush(); tick(); flush()
assert(capturedPreviews==1 and not characters:hasPreview(selectedAppearance), 'Never photograph unsaved edits as saved appearance')
press(latest('保存当前预设'))
character.visible=false; tick(); flush()
assert(capturedPreviews==1, 'Closing cancels pending image generation')
character.visible=true; tick(); flush()
press(latest('造型')); tick(); flush(); tick(); flush()
assert(capturedPreviews==2 and characters:hasPreview(selectedAppearance), 'Missing previews can be regenerated on selection')
press(latest('删除预设'))
assert(#characters:list()==0 and not characters:hasPreview(selectedAppearance), 'Delete archives associated preview')
assert(#uiLib:list()==0, 'Preview generation leaves world presets untouched')

-- Keep the original create-world button outside the scrolling list.
local originalFindAll=FindAllOf
local worldCanvas=panel('CanvasPanel')
local worldScroll=panel('ScrollBox')
worldScroll.overflow=0
worldScroll.fraction=0.7
function worldScroll:ForceLayoutPrepass() end
function worldScroll:GetScrollOffsetOfEnd() return self.overflow end
function worldScroll:GetViewFraction() return self.fraction end
worldCanvas:AddChildToCanvas(worldScroll)
worldScroll.Slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
worldScroll.Slot:SetOffsets({Left=12,Top=20,Right=8,Bottom=10})
local worldButton=object('CreateWorldButton')
worldScroll:AddChild(worldButton)
worldButton.nativeClick=function() return 'original create world' end
function FindAllOf(class)
    if class=='WBP_Title_WorldSelect_CreateWorld_ListContent_C' then return {worldButton} end
    return originalFindAll(class)
end
local worldSelect=require('CustomPresets.WorldSelect')
worldSelect.update()
assert(worldButton:GetParent()==worldCanvas, 'Move native create button outside scroll box')
assert(worldScroll.Slot.offsets.Bottom==82, 'Reserve footer space once')
assert(worldButton.Slot.offsets.Top==-10 and worldButton.Slot.offsets.Bottom==64, 'Keep button within original bottom bounds')
assert(worldButton.nativeClick()=='original create world', 'Preserve native click behavior')
worldSelect.update()
assert(worldScroll.Slot.offsets.Bottom==82, 'Repeated scans must not shrink the list again')
local previousButton=worldButton
handlers.WorldListPre()
assert(previousButton.visibility==1, 'Hide previous footer before rebuilding')
worldButton=object('CreateWorldButton'); worldScroll:AddChild(worldButton)
handlers.WorldListPost()
assert(worldButton.visibility==0, 'Show replacement immediately after native list rebuild')
assert(previousButton:GetParent()==nil and worldButton:GetParent()==worldCanvas, 'Replace footer after native list rebuild')
assert(worldScroll.Slot.offsets.Bottom==82, 'List rebuild preserves reserved space')
worldScroll.overflow=0; worldScroll.fraction=1
local fixed=worldButton
worldButton=object('CreateWorldButton'); worldScroll:AddChild(worldButton)
handlers.WorldListPre(); handlers.WorldListPost()
assert(worldButton:GetParent()==worldScroll and fixed:GetParent()==nil, 'No fixed footer when list fits')
assert(worldScroll.Slot.offsets.Bottom==10 and worldButton.visibility==0, 'Restore original list bounds and button')
worldSelect.update()
assert(worldButton:GetParent()==worldScroll, 'Keep native button in short lists')
FindAllOf=originalFindAll
