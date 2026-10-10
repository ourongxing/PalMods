local Runtime=require('BetterPalSouls.Runtime')
local Plan=require('BetterPalSouls.Plan')
local serial=0
local function object(t)
    serial=serial+1;local id='Object-'..serial;t=t or {}
    t.IsValid=function(self) return not self.Dead end;t.GetFullName=function() return id end
    t.SetVisibility=function(self,v) self.Visibility=v end;t.GetVisibility=function(self) return self.Visibility or 0 end
    t.SetIsEnabled=function(self,v) self.Enabled=v end;t.SetToolTipText=function(self,v) self.Tooltip=v end
    t.SetRenderOpacity=function(self,v) self.Opacity=v end
    t.RemoveFromParent=function(self) self.Removed=true end
    t.GetClass=function(self) return {GetFName=function() return {ToString=function() return self.ClassName or 'Other' end} end} end
    return t
end
local function label(v) return object({Value=v,SetText=function(self,s) self.Value=s end,
    GetText=function(self) return {ToString=function() return self.Value end} end}) end
local function focus()
    local parent=object()
    return object({SetIsFocusable=function() end,SetShouldUseFallbackDefaultInputAction=function() end,
        GetParent=function() return parent end})
end
local function slot()
    return object({Offsets={Left=352,Top=12,Right=220,Bottom=48},SetAutoSize=function() end,SetAnchors=function() end,
        SetOffsets=function(self,v) self.Offsets=v end,SetZOrder=function() end,SetAlignment=function() end,
        GetOffsets=function(self) return self.Offsets end,GetAnchors=function() return {} end,GetAlignment=function() return {} end})
end
local function canvas() return object({Children={},AddChildToCanvas=function(self,child)
    child.Slot=slot();self.Children[#self.Children+1]=child;return child.Slot end,
    GetChildrenCount=function(self) return #self.Children end,
    GetChildAt=function(self,i) return self.Children[i+1] end}) end
FText=function(v) return v end
LoadAsset=function() error('This version must not load a private selector') end
StaticConstructObject=function(class)
    assert(class.ClassName=='Image','Only arrow background images may be constructed')
    return object({SetColorAndOpacity=function(self,v) self.Color=v end})
end
local events,created={},{}
RegisterHook=function(path,callback) events[path]=callback;return 1,2 end
local unregistered={}
UnregisterHook=function(path,pre,post)
    assert(events[path] and pre==1 and post==2)
    unregistered[path]=true
end
ModRef={}
local loops,queue,observer={}, {},nil
LoopAsync=function(_,callback) loops[#loops+1]=callback end
ExecuteInGameThread=function(callback) queue[#queue+1]=callback end
local function flush()
    local count=0
    while #queue>0 do
        count=count+1;assert(count<20,'UI events must not create an endless refresh chain')
        table.remove(queue,1)()
    end
end
local function loop() local done=loops[#loops]();flush();return done end
local menuClassLoaded=false
NotifyOnNewObject=function(path,callback)
    assert(path:find('WBP_Buildup_Pal_C',1,true));observer=callback
end
local lib=object({Create=function()
    local o=label('');o.WBP_PalInvisibleButton=focus();o.WBP_PalInvisibleButton.Slot=slot()
    o.Text_Main=label('');o.Text_Main.Font={Size=24}
    o.Text_Main.SetFont=function(self,v) self.Font=v end
    o.Text_Main.SetJustification=function(self,v) self.Justification=v end
    local root=canvas();o.Decoration=object()
    root.Children={o.Decoration,o.Text_Main,o.WBP_PalInvisibleButton}
    o.WidgetTree={RootWidget=root};created[#created+1]=o;return o
end})
StaticFindObject=function(path)
    if path:find('WBP_Buildup_Pal_C:',1,true) then return menuClassLoaded and object() or nil end
    if path=='/Script/UMG.Image' then return object({ClassName='Image'}) end
    if path=='/Script/UMG.Default__WidgetBlueprintLibrary' then return lib end
    if path:find('WBP_CommonButton_C',1,true) or path:find(':StatusPlus',1,true) or path:find(':StatusMinus',1,true) then return object() end
    if path=='/Script/Engine.Default__KismetInternationalizationLibrary' then return object({GetCurrentCulture=function() return 'zh-Hans' end}) end
    if path=='/Script/Pal.Default__PalUtility' then return object({Alert=function() end}) end
    error('Unexpected interface: '..path)
end
local panel=object({['Is Upgrade']=true,CanvasPanel_Overall=canvas(),WBP_CommonButton=label('强化')})
panel.WBP_CommonButton.Slot=slot()
panel.WBP_CommonButton.ClassName='WBP_CommonButton_C'
local staleConfirm=object({ClassName='WBP_CommonButton_C'})
panel.CanvasPanel_Overall.Children={panel.WBP_CommonButton,staleConfirm}
panel.TargetStatusRankMap={Values={},Contains=function(self,k) return self.Values[k]~=nil end,
    Find=function(self,k) return self.Values[k] end,Add=function(self,k,v) self.Values[k]=v end,
    Remove=function(self,k) self.Values[k]=nil end}
local nativeWriting=false
for i=1,4 do panel['WBP_Buildup_Pal_Item'..(i==1 and '' or '_'..i-1)]=object({SetNum=function(self,n)
    assert(nativeWriting,'Only the native calculator may set costs');self.Amount=n end}) end
local nativeRows={}
local staleArrow=object({ClassName='WBP_CommonButton_C'})
for i=1,4 do
    local gauge=object({Slot=slot()})
    local row=object({Status=i,TargetRank=i==1 and 1 or 0,['Current Rank']=i==1 and 1 or 0,
        CanvasPanel_0=canvas(),HorizontalBox_Gauge=object({GetParent=function() return gauge end}),
        WBP_PalInvisibleButton_Plus=focus(),WBP_PalInvisibleButton_Minus=focus(),Setup=function() end,
        SetEnable=function() end,SetInfo=function(self,_,n) self.TargetRank=n end})
    nativeRows[i]=row;panel['WBP_Buildup_Pal_StatusContent'..(i==1 and '' or '_'..i-1)]=row
end
nativeRows[1].CanvasPanel_0.Children={staleArrow}
local menu=object({WBP_Buildup_Pal_Status=panel,CurrentHandle=object(),GetOwningPlayer=function() return object() end,
    IsVisible=function(self) return not self.Hidden end})
FindAllOf=function() error('Reinforcement UI must never scan the global UObject array') end
local state={Current={1,0,0,0},HandleKey='Pal-A',Parameter=object(),Stock=Plan.copy({PalUpgradeStone=5}),
    Limits=Plan.copy({PalUpgradeStone=99,PalUpgradeStone2=99,PalUpgradeStone3=99,PalUpgradeStone4=99}),
    Slots={{Item='PalUpgradeStone',Count=5,Backpack=true}},Schedule={
        {Item='PalUpgradeStone',Count=1},{Item='PalUpgradeStone',Count=2},{Item='PalUpgradeStone',Count=3}}}
local nativeRefreshes=0
function panel:UpdateRequiredItemSufficiency()
    nativeRefreshes=nativeRefreshes+1
    local required=Plan.cost(state.Current,self.TargetStatusRankMap.Values,state.Schedule)
    nativeWriting=true
    for i,id in ipairs(Plan.items) do self['WBP_Buildup_Pal_Item'..(i==1 and '' or '_'..i-1)]:SetNum(required[id]) end
    nativeWriting=false
end
local b={writes=0}
function b:read() return state end
function b:check() end
function b:checkCost() end
function b:apply() self.writes=self.writes+1 end
function b:checkPrepared() end
function b:upgrade(_,targets) state.Current=targets;state.Stock=Plan.copy({}) end
function b:verify() end
function b:restore() error('Unexpected rollback') end
Runtime.new=function() return b end
require('BetterPalSouls.UI').start({Enabled=true,Language='zh-Hans'})
assert(#loops==0 and #queue==0,'Starting in the world must schedule no refresh work')
menuClassLoaded=true;menu.Hidden=true;observer(menu);flush()
assert(#loops==0,'Constructing a hidden menu must not start polling')
menu.Hidden=false;observer(menu);flush()
assert(#loops==1 and #created==9 and b.writes==0,'Lazy construction must attach after setup')
assert(staleArrow.Removed and staleConfirm.Removed and not panel.WBP_CommonButton.Removed,
    'Reload must remove old injected controls and preserve the original button')
for _,widget in ipairs(created) do assert(widget.WBP_PalInvisibleButton.Opacity==0) end
assert(created[1].Slot.Offsets.Top==17 and created[1].Slot.Offsets.Bottom==26)
assert(nativeRows[1].WBP_PalInvisibleButton_Minus.Opacity==0)
assert(not created[1].Enabled, 'Minimum remains non-interactive at the current rank')
assert(not created[9].Enabled, 'Confirmation stays disabled for an empty selection')
local click,plus
for path,callback in pairs(events) do
    if path:find(':BndEvt',1,true) then click=callback end
    if path:find(':StatusPlus',1,true) then plus=callback end
end
local function press(widget) click({get=function() return widget end}) end
-- UE4SS invokes the script hook BEFORE the native +1 body updates its rank.
plus({get=function() return nativeRows[2] end})
nativeRows[2].TargetRank=1;panel.TargetStatusRankMap:Add(2,1);panel:UpdateRequiredItemSufficiency()
local refreshes=nativeRefreshes
loop()
assert(nativeRefreshes==refreshes)
press(created[2]) -- HP max reserves the attack row's one soul.
assert(nativeRows[1].TargetRank==2 and panel.WBP_Buildup_Pal_Item.Amount==3)
press(created[1]) -- HP min returns to rank one, not zero.
assert(nativeRows[1].TargetRank==1 and panel.TargetStatusRankMap.Values[1]==nil)
assert(panel.WBP_Buildup_Pal_Item.Amount==1)
press(created[2]);press(created[4]) -- HP rank 2 plus attack rank 2 consume five.
assert(nativeRows[2].TargetRank==2 and panel.WBP_Buildup_Pal_Item.Amount==5)
assert(not created[6].Enabled and not created[8].Enabled)
refreshes=nativeRefreshes
for i=1,20 do loop() end
assert(nativeRefreshes==refreshes,'Idle polling must not rerender costs')
for i=1,5 do panel:UpdateRequiredItemSufficiency() end
assert(panel.WBP_Buildup_Pal_Item.Amount==5 and b.writes==0)
press(created[9]);assert(b.writes==1 and state.Current[1]==2 and state.Current[2]==2)
state.HandleKey='Pal-B';state.Current={0,0,0,0}
state.Stock=Plan.copy({PalUpgradeStone=5});loop()
assert(nativeRows[1].TargetRank==0 and nativeRows[2].TargetRank==0,
    'Switching Pals must discard the previous selection')
panel['Is Upgrade']=false;loop()
assert(panel.WBP_CommonButton.Visibility==0 and created[1].Visibility==1)
assert(nativeRows[1].HorizontalBox_Gauge:GetParent().Slot.Offsets.Right==220)
local setup,close
for path,callback in pairs(events) do
    if path:find(':OnSetup',1,true) then setup=callback end
    if path:find(':CloseAction',1,true) then close=callback end
end
local context={get=function() return menu end}
local oldLoop=loops[#loops]
close(context)
assert(oldLoop()==true and #queue==0,'Closing must stop the refresh loop immediately')
local reads=0
local originalRead=b.read
b.read=function(self,...) reads=reads+1;return originalRead(self,...) end
for i=1,20 do assert(oldLoop()==true) end
assert(reads==0,'Closed menus must not read reinforcement state')
panel['Is Upgrade']=true
setup(context);setup(context)
assert(#queue==1,'Repeated setup events must share one queued refresh')
close(context) -- Close before the queued game-thread refresh executes.
flush();assert(reads==0,'A queued refresh from a closed menu must be inert')
setup(context);flush()
assert(reads>0 and #created==18,'A retained menu must work when reopened')
local reopenedLoop=loops[#loops]
assert(oldLoop()==true,'An earlier loop must not refresh the reopened session')
menu.Hidden=true;loop()
assert(reopenedLoop()==true,'Hidden retained menus must stop polling')
reads=0;assert(reopenedLoop()==true and reads==0)
menu.Hidden=false;setup(context);flush()
menu.Dead=true;loop()
assert(type(ModRef.OnUnload)=='function')
ModRef.OnUnload()
local removed=0
for _ in pairs(unregistered) do removed=removed+1 end
assert(removed==7,'Unload must explicitly remove every owned blueprint hook ID')
assert(loop()==true,'Polling must stop after unload')
local oldRefreshes=nativeRefreshes
plus({get=function() error('Unloaded callbacks must not access engine objects') end})
assert(nativeRefreshes==oldRefreshes)
local oldLoops=#loops
observer(menu);setup(context);flush()
assert(#loops==oldLoops,'Unloaded lifecycle callbacks must not restart polling')
print('Verified max/min arrows, nonzero minimum, shared budget, unchanged native +/- and costs, idle stability and reset layout.')
