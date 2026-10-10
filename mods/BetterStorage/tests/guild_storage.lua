local module = assert(loadfile(SCRIPTS .. '/GuildStorage.lua'))()
local function guid(id) return {A=id,B=0,C=0,D=0} end
local function object(value)
    value.IsValid=function() return value.valid ~= false end
    value.GetAddress=function() return value.address end
    return value
end
local function param(value) return {get=function() return value end} end
local function chest(address, guildChest)
    return object({address=address,IsA=function() return guildChest ~= false end,
        GetBaseCampIdBelongTo=function() return guid(7) end})
end
local target=object({address=20,GetId=function() return guid(2) end,capacity=54,items={{id='Wood',count=99}}})
local unrelated=object({address=30,GetId=function() return guid(3) end,capacity=54})
local base=object({GetGroupIdBelongTo=function() return guid(2) end})
local ready,server,slots=true,true,360
local manager=object({TryGetModel=function(_,id,out)
    assert(id.A==7);if not ready then return false end;out.OutModel=base;return true
end})
local world=object({address=10})
local utility=object({IsServer=function() return server end,
    GetGameSetting=function() return object({GuildChestSlotNum=slots}) end})
FindFirstOf=function() return world end
StaticFindObject=function() return utility end
local scans,calls,growths=0,0,0
FindAllOf=function(name) assert(name=='PalGroupGuild');scans=scans+1;return {unrelated,target} end
local work,delays={},{}
ExecuteInGameThread=function(fn) work[#work+1]=fn end
ExecuteWithDelay=function(ms,fn) assert(ms==1000);delays[#delays+1]=fn end
LoopAsync=function() error('Migration must not poll') end
NotifyOnNewObject=function() error('Migration must not discover objects globally') end
local hook
RegisterHook=function(path,pre,post)
    assert(path=='/Script/Pal.PalBaseCampManager:OnCreateMapObjectModelInServer');hook=post
end
local unavailable=false
module.start({growGuildStorage=function(w,g,count)
    assert(server and w==10 and g==20);calls=calls+1
    if unavailable then return nil,'container not loaded' end
    if target.capacity<count then target.capacity=count;growths=growths+1 end
    return target.capacity
end})
local function flush()
    local pending=work;work={};for _,fn in ipairs(pending) do fn() end
end
local function retry()
    local pending=delays;delays={};for _,fn in ipairs(pending) do fn() end;flush()
end
local function created(value) hook(param(manager),param(value),param({})) end
created(nil);created(chest(100,false));assert(#work==0 and scans==0)
local first=chest(101)
created(first);created(first);assert(#work==1 and target.capacity==54)
local item=target.items[1]
flush();assert(target.capacity==360 and unrelated.capacity==54 and growths==1)
assert(target.items[1]==item and item.count==99 and #delays==0)
created(chest(102));flush();assert(growths==1,'Rebuilding never re-extends an already sufficient inventory')
slots=54;created(chest(103));flush();assert(target.capacity==360,'Never shrink saved slots')
server=false;local before=calls;created(chest(104));flush();assert(calls==before and #delays==0)
server=true;slots=540;ready=false
created(chest(105));flush();assert(#delays==1)
ready=true;unavailable=true;retry();assert(#delays==1 and target.capacity==360)
unavailable=false;retry();assert(target.capacity==540 and #delays==0 and target.items[1]==item)
ready=false;created(chest(106));flush()
for _=1,8 do retry() end
assert(#delays==0 and #work==0,'Initialization retries must expire')
local dead=chest(107);created(dead);dead.valid=false;flush();assert(#delays==0)
assert(calls>0 and growths==2)
print('PASS: old-save guild migration on chest construction, owner isolation, deferred growth, item retention, rebuild idempotence, grow-only, authority and finite loading retries')
