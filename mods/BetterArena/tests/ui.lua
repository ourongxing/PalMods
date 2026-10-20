package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local serial,hooks,queue=0,{},{}
local receipts={}
package.loaded['BetterArena.Feedback']={clear=function() end,tick=function() end,show=function(_,result) receipts[#receipts+1]=result.receipt end}
local function name(s) return {ToString=function() return s end} end
local function obj(fields)
 serial=serial+1;fields=fields or {};local id='object'..serial
 fields.IsValid=function() return true end;fields.GetFullName=function() return id end
 return fields
end
local function text(value) return obj{SetText=function(self,v) self.value=v end,GetText=function(self) return name(self.value or '') end,value=value} end
local function slot(x)
 return {position={X=x or 0,Y=0},SetPosition=function(self,v) self.position=v end,GetPosition=function(self) return self.position end,
 SetAnchors=function() end,SetAlignment=function() end,SetSize=function() end}
end
local function canvas()
 return obj{children={},AddChildToCanvas=function(self,widget) self.children[#self.children+1]=widget;widget.Slot=slot();return widget.Slot end}
end
local EVENT='BndEvt__WBP_Arena_TopMenuButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature'
local BASE='/Game/Pal/Blueprint/UI/UserInterface/Arena/'
local CLICK=BASE..'WBP_Arena_TopMenuButton.WBP_Arena_TopMenuButton_C:'..EVENT
local ENTRY=BASE..'WBP_Arena_SoloEntry.WBP_Arena_SoloEntry_C:Setup'
local CHALLENGE='BndEvt__WBP_Arena_TopMenu_WBP_Arena_TopMenuButton_Solo_K2Node_ComponentBoundEvent_0_OnArenaButtonClicked__DelegateSignature'
local function button()
 local b=obj{Text_ButtonName=text(),Setup=function() end,SetLock=function() end,SetRenderOpacity=function() end,SetVisibility=function() end,SetIsEnabled=function(self,v) self.enabled=v end,RemoveFromParent=function(self) self.removed=true end}
 b[EVENT]=function(self) hooks[CLICK]({get=function() return self end}) end
 return b
end
local function delegate(bindings)
 return {bindings=bindings,GetBindings=function(self) return self.bindings end,Clear=function(self) self.bindings={} end,
 Add=function(self,target,fn) self.bindings[#self.bindings+1]={Object=target,FunctionName=fn} end,
 Broadcast=function(self,input) for _,b in ipairs(self.bindings) do b.Object[b.FunctionName:ToString()](b.Object,input) end end}
end
local owner=obj();local battles,claims,left=0,{},3
local menuCanvas=canvas()
menuCanvas.GetFName=function() return name('Canvas_MenuButton') end
local root=canvas()
root.GetFName=function() return name('Root') end
root.IsA=function() return true end
root.GetChildrenCount=function() return 1 end
root.GetChildAt=function() return menuCanvas end
local top=obj{WidgetTree={RootWidget=root},Text_MenuGuide=text(),visible=true,GetOwningPlayer=function() return owner end,IsVisible=function(self) return self.visible end}
for _,spec in ipairs{{'Solo',-380},{'PvP',0},{'Spectate',380}} do top['WBP_Arena_TopMenuButton_'..spec[1]]=obj{Slot=slot(spec[2])} end
local child
local function openChallenge()
 local cards={}
 for rank=1,7 do
  local card=obj{ArenaRank=rank-1,BP_PalTextBlock_Reward=text('original reward'),enabled=true,opacity=1,SetIsEnabled=function(self,v) self.enabled=v end,GetIsEnabled=function(self) return self.enabled end,
   SetRenderOpacity=function(self,v) self.opacity=v end,GetRenderOpacity=function(self) return self.opacity end}
  card.normalClick=function() battles=battles+1 end
  card.WBP_PalInvisibleButton=obj{OnButtonBaseClicked=delegate{{Object=card,FunctionName=name('normalClick')}}}
  cards[#cards+1]=card
 end
 child=obj{WidgetTree={RootWidget=canvas()},cards=cards,visible=true,GetOwningPlayer=function() return owner end,IsVisible=function(self) return self.visible end,
 EntryButtons={GetArrayNum=function() return 7 end,ForEach=function(_,fn) for i,c in ipairs(cards) do fn(i,{get=function() return c end}) end end}}
 if hooks[ENTRY] then hooks[ENTRY]({get=function() return child end}) end
end
top[CHALLENGE]=openChallenge
local library=obj{Create=function() return button() end}
StaticFindObject=function(path)
 if path:find('WidgetBlueprintLibrary',1,true) then return library end
 if path:find('KismetInternationalizationLibrary',1,true) then return {GetCurrentCulture=function() return 'zh-CN' end} end
 return obj()
end
LoadAsset=function() end;FName=name;FText=function(s) return s end
RegisterHook=function(path,callback) hooks[path]=callback;return 1,2 end
UnregisterHook=function(path) hooks[path]=nil end
local notifications,scans={},0
NotifyOnNewObject=function(path,callback) notifications[path]=callback end
LoopAsync=function(_,callback) UI_TICK=callback end
ExecuteInGameThread=function(callback) queue[#queue+1]=callback end
FindAllOf=function(class) scans=scans+1;if class=='WBP_Arena_TopMenu_C' then return {top} end;return child and {child} or {} end
local service={preview=function() return {challengeRank=5,cleared={[1]=true,[5]=true},remaining=left,playerRank=3,pending=false} end,
 claim=function(_,menu,rank) assert(rank==1 or rank==5);assert(left>0);claims[#claims+1]=rank;left=left-1;return {receipt={rank=rank,items={BattleTicket=rank},points=50}} end}
local function drain() while #queue>0 do table.remove(queue,1)() end end
local function tick() UI_TICK();drain() end
require('BetterArena.UI').start({DailyLimits={1,2,3,4,5,6,7}},service)
tick()
local sweep=menuCanvas.children[1]
assert(sweep.Text_ButtonName.value=='扫荡 · 3/3')
assert(top.WBP_Arena_TopMenuButton_Solo.Slot.position.X==-570)
-- Ordinary Challenge still enters combat.
openChallenge();child.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();assert(battles==1)
child.visible=false;tick()
-- Sweep opens the same cards but replaces only their click route.
sweep[EVENT](sweep);drain();assert(child.cards[1].enabled and child.cards[5].enabled and child.cards[2].enabled)
assert(child.cards[2].opacity==0.45 and child.cards[2].BP_PalTextBlock_Reward.value=='尚未通关')
child.cards[2].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();drain();assert(#claims==0 and left==3 and battles==1)
local sweptPage=child
child.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();child.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();drain()
assert(#claims==1 and claims[1]==1 and battles==1 and left==2)
assert(#receipts==1 and receipts[1].rank==1 and receipts[1].items.BattleTicket==1)
child.cards[5].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();drain();assert(claims[2]==5 and left==1 and battles==1)
child.cards[5].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();drain();assert(left==0 and child.cards[1].enabled and child.cards[5].enabled)
assert(sweep.enabled)
for i=1,3 do child.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();drain() end
assert(left==0 and #claims==3 and battles==1)
assert(#receipts==3)
sweptPage.visible=false;tick()
assert(sweptPage.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked.bindings[1].Object==sweptPage.cards[1])
assert(sweptPage.cards[2].opacity==1 and sweptPage.cards[2].enabled)
openChallenge();child.cards[1].WBP_PalInvisibleButton.OnButtonBaseClicked:Broadcast();assert(battles==2 and #claims==3)
top.visible=false;tick();assert(top.WBP_Arena_TopMenuButton_Solo.Slot.position.X==-380 and sweep.removed)
-- Long idle periods never enumerate global objects again.
for _=1,100 do tick() end
assert(scans==2,'idle arena timer must not rescan global objects')
-- A new menu after startup is discovered through the creation notification.
local prior=top.GetFullName
top.GetFullName=function() return 'new-arena-menu' end
top.visible=true
notifications['/Game/Pal/Blueprint/UI/UserInterface/Arena/WBP_Arena_TopMenu.WBP_Arena_TopMenu_C'](top)
drain();tick()
assert(top.WBP_Arena_TopMenuButton_Solo.Slot.position.X==-570 and scans==2)
top.visible=false;tick();top.GetFullName=prior
-- Simulate server -> title -> single player while a click/timer is queued.
-- A destroyed wrapper throws even on IsValid; reset must never inspect it.
top.visible=true;tick()
local oldClick=hooks[CLICK]
local latest=menuCanvas.children[#menuCanvas.children]
latest[EVENT](latest)
UI_TICK()
require('BetterArena.Lifecycle').reset()
local check=top.IsValid
top.IsValid=function() error('old world object accessed') end
drain()
oldClick({get=function() error('old hook context accessed') end})
assert(not hooks[CLICK] and not hooks[ENTRY],'old blueprint hooks must be removed before travel')
top.IsValid=check
-- Reconcile the new world's menu and hooks instead of reusing old sessions.
top.GetFullName=function() return 'single-player-menu' end
tick()
assert(hooks[CLICK] and hooks[ENTRY] and scans==4)
print('PASS: top menu > sweep difficulties, selected rewards, shared limit, double click guard and ordinary Challenge isolation')
