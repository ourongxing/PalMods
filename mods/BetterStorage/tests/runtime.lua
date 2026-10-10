local function object(value)
    value.IsValid=function() return true end
    value.GetAddress=function() return value.address or 1 end
    return value
end
local function guid(n) return {A=n,B=0,C=0,D=0} end
local function param(value) return {get=function() return value end} end
local scoped=true
local player=object({address=10,K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end})
local component=object({GetOwner=function() return player end})
local models={}
for i, info in ipairs({{count=3,x=1},{count=10,x=20},{count=10,x=2},{count=100,x=1,guild=2}}) do
    models[i]=object({GetId=function() return guid(i) end,
        GetGroupIdBelongTo=function() return guid(info.guild or 1) end,
        GetBuildingNum=function() return info.count end,
        GetTransform=function() return {Translation={X=info.x,Y=0,Z=0}} end})
end
local ids={guid(1),guid(2),guid(3),guid(4)}
ids.ForEach=function(self, callback) for i, id in ipairs(self) do callback(i,id) end end
local guild=object({BaseCampIds=ids,GetId=function() return guid(1) end})
local manager=object({TryGetModel=function(_,id,out) out.OutModel=models[id.A]; return true end})
local utility=object({GetPalmi=function() return player end,GetBaseCampManager=function() return manager end,
    GetLocalPlayerGuild=function() return guild end})
StaticFindObject=function() return utility end
local hooks={}
RegisterHook=function(path,pre,post) hooks[path]=post end
-- These functions must never be used by the simple bootstrap.
ExecuteInGameThreadAfterFrames=function() error('unexpected scheduled scan') end
NotifyOnNewObject=function() error('unexpected inventory discovery') end
package.loadlib=function(_,symbol)
    assert(symbol=='luaopen_BetterStorage')
    return function() return {ready=function() return true end,inStorageScope=function() return scoped end} end
end
assert(loadfile(SCRIPTS..'/main.lua'))()
local count=0
for _ in pairs(hooks) do count=count+1 end
assert(count==3)
local getModel=hooks['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel']
local getId=hooks['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID']
assert(getModel(param(component),param(nil))==models[3])
assert(getId(param(component),param(guid(0))).A==3)
assert(getModel(param(component),param(models[1]))==nil)
assert(getId(param(component),param(guid(1)))==nil)
scoped=false
assert(getModel(param(component),param(nil))==nil)
scoped=true
component.GetOwner=function() return player end
local physical
component.GetInsideBaseCampModel=function()
    -- Test recursion guard against our own scoped getter.
    return physical or getModel(param(component),param(nil))
end
player.InsideBaseCampCheckComponent=component
local world=object({CurrentInBaseCamp=true,IsA=function() return true end})
local function name(value) return {ToString=function() return value end} end
local function array(values)
    values.ForEach=function(self,callback) for i,value in ipairs(self) do callback(i,value) end end
    values.Empty=function(self) for i=#self,1,-1 do self[i]=nil end end
    return values
end
local names=array({name('wood'),name('stone')})
local output=array({{StaticItemId=name('absent'),Num=999}})
local assigned
local out={get=function() return output end,set=function(_,value) assigned=value end}
local calls=0
local unreadable=false
utility.GetLocalPalPlayerController=function() return object({GetPlayerUId=function() return guid(9) end}) end
local baseUtility=object({CollectQuickStackTargetItemInfos=function(_,context,baseId,uid,requested,collected)
    calls=calls+1
    assert(context==world and baseId.A==3 and uid.A==9)
    assert(#requested==2 and requested[1]:ToString()=='wood' and requested[2]:ToString()=='stone')
    if not unreadable then collected[1]={StaticItemId=name('wood'),Num=27} end
end})
StaticFindObject=function(path)
    if path=='/Script/Pal.Default__PalBaseCampUtility' then return baseUtility end
    return utility
end
local collect=hooks['/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos']
collect(param(utility),param(world),param(names),out)
assert(assigned and #assigned==1 and assigned[1].StaticItemId:ToString()=='wood' and assigned[1].Num==27)
assert(calls==1 and #output==0)
-- Missing target data must never turn all bag items into accepted candidates.
unreadable=true; assigned=nil
collect(param(utility),param(world),param(names),out)
assert(assigned and #assigned==0 and calls==2)
assigned=nil; calls=0; physical=models[1]
collect(param(utility),param(world),param(names),out)
assert(not assigned and calls==0)
physical=nil; scoped=false
collect(param(utility),param(world),param(names),out)
assert(not assigned and calls==0)
scoped=true
component.GetOwner=function() return object({address=11}) end
assert(getModel(param(component),param(nil))==nil)
