package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local calls={open=0,close=0,sound=0,removed=0}
local function object(t) t=t or {};t.IsValid=function() return true end;return t end
local function text() return object{SetText=function(self,v) self.text=v end} end
local function hidden() return object{SetVisibility=function(self,v) self.visibility=v end} end
local banner=object{Text_Title=text(),BP_PalRichTextBlock_C_99=text(),Icon=hidden(),SizeBox_AddTextTitle=hidden(),VerticalBox_Add=hidden(),Anm_Open='open',Anm_Close='close',
 AddToViewport=function(_,z) assert(z==100) end,StopAllAnimations=function() end,SetInfo=function() end,
 SetVisibility=function(self,v) self.visibility=v end,
 PlayAnimation=function(_,animation) calls[animation]=calls[animation]+1 end,
 RemoveFromParent=function() calls.removed=calls.removed+1 end}
local utility=object{GetHUDService=function() return {PlayAkSound=function() calls.sound=calls.sound+1 end} end}
StaticFindObject=function(path)
 if path:find('Internationalization') then return {GetCurrentCulture=function() return 'zh-CN' end} end
 if path:find('Default__PalUIUtility') then return {GetItemName=function(_,_,id,out) out.outName={ToString=function() return '道具'..id end} end} end
 if path:find('WidgetBlueprintLibrary') then return {Create=function() return banner end} end
 if path:find('Default__PalUtility') then return utility end
 return object()
end
FName=function(s) return s end;FText=function(s) return s end
local F=require('BetterArena.Feedback')
local session={menu={GetOwningPlayer=function() return object() end}}
local receipt={items={B=2,A=3},points=50,rank=7}
F.show(session,{receipt=receipt})
assert(banner.Text_Title.text=='扫荡完成 · 排名积分 +50 RP')
assert(banner.BP_PalRichTextBlock_C_99.text=='道具A × 3    道具B × 2')
assert(banner.visibility==4 and banner.Icon.visibility==1 and calls.sound==1 and calls.open==1)
local deadline=session.rewardClose
F.tick(session,deadline-1);assert(calls.close==0)
F.tick(session,deadline);assert(calls.close==1 and calls.removed==0)
-- Another successful sweep reopens the same banner with its own actual roll.
F.show(session,{receipt={items={B=1},points=2,rank=1}})
assert(calls.open==2 and not session.rewardRemove and banner.BP_PalRichTextBlock_C_99.text=='道具B × 1')
F.tick(session,session.rewardClose);F.tick(session,session.rewardRemove)
assert(calls.removed==1 and not session.rewardBanner)
assert(receipt.items.A==3 and receipt.items.B==2)
print('PASS: actual reward receipt, localized item names, native animations/audio, nonblocking overlay and cleanup')
