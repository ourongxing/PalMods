local create = dofile(SCRIPTS.."/Preview.lua")
local function array(values)
    values.GetArrayNum=function(self) return #self end
    values.ForEach=function(self,callback) for i,value in ipairs(self) do callback(i,value) end end
    return values
end
local function object(value)
    value.IsValid=function()
        local _,main=coroutine.running()
        assert(main, 'UE4SS rejects UObject access from unregistered coroutine states')
        return not value.invalid
    end
    value.GetAddress=function() return value.address or 1 end
    return value
end
local function name(id) return {ToString=function() return id end} end
local function guid(n) return {A=n,B=0,C=0,D=0} end
local function fixture(remote)
    local f={queue={},clock=0,counts={},remote=remote,denied={},slotDenied={}}
    local function count(key)
        f.counts[key]=(f.counts[key] or 0)+1
        f.clock=f.clock+0.03
    end
    local function slot(id,address,empty,max,dynamic)
        return object({address=address,
            IsEmpty=function()
                count('slots')
                if address<100 then f.counts.chestSlots=(f.counts.chestSlots or 0)+1 end
                return empty
            end,
            IsMaxStack=function() return max end,
            GetItemId=function() return {StaticId=name(id),DynamicId={LocalIdInCreatedWorld=guid(dynamic and 1 or 0)}} end,
            GetSlotId=function() return address end})
    end
    f.bag={slot('wood',100),slot('wood',101),slot('stone',102),slot('egg',103),slot('weapon',104)}
    f.buttons={}
    for _,item in ipairs(f.bag) do
        f.buttons[#f.buttons+1]=object({GetTargetSlot=function(_,out) out.TargetSlot=item end,
            SetColorAndOpacity=function(self,c) self.alpha=c.A end})
    end
    local container=object({address=20,ItemSlotArray=array({slot('None',30,true)})})
    f.container=container
    local module=object({GetContainer=function() return container end})
    f.chest=object({IsA=function() return true end,GetBaseCampIdBelongTo=function() return guid(10) end,
        IsLockedPrivateByNot=function() return f.locked end,
        GetGuildSecurityModule=function() return f.security end,
        GetPasswordLockModule=function() return f.password end,
        GetItemContainerModule=function() return module end})
    local storage=object({IsA=function() return true end,
        ContainerInfos=array({{OwnerMapObjectConcreteModelInstanceId=guid(100)}}),
        GuildContainerInfo={OwnerMapObjectConcreteModelInstanceId=guid(0)}})
    f.storage=storage
f.base=object({GetId=function() return guid(f.baseId or 10) end,
        GetGroupIdBelongTo=function() return guid(1) end,ModuleArray=array({storage})})
    f.record=object({address=50,Local_ItemQuickMoveExceptionIDList=array({})})
    local items=object({GetStaticItemData=function(_,item)
        local id=item:ToString(); count('data_'..id)
        return object({address=id,TypeB=id=='egg' and 30 or 4,
            HasDynamicItemClass=function() return id=='egg' or id=='weapon' end})
    end})
    f.pal=object({GetItemIDManager=function() return items end,
        GetLocalPlayerState=function() return object({GetLocalRecordData=function() return f.record end}) end,
        GetMapObjectManager=function()
            assert(not f.remote, 'remote must not inspect chest models')
            return object({FindConcreteModel=function() count('models'); return f.chest end,
                FindModel=function() error('concrete ID must not be queried as a parent model ID') end})
        end,
        GetLocalPalPlayerController=function() return object({GetPlayerUId=function() return guid(1) end}) end})
    f.selection={}
    f.adds={}
    f.world=object({address=200,CurrentInBaseCamp=true,
        Canvas_QuickStack=object({IsVisible=function() return f.visible~=false end}),
        WBP_PalPlayerInventoryScrollList=object({GetItemSlotButtons=function(_,kind,out)
            assert(kind==0 and next(out)==nil)
            for i,button in ipairs(f.buttons) do
                -- UE4SS Array OutParm populates numeric RemoteUnrealParam
                -- entries in the supplied plain table, with no named field.
                out[i]={get=function() return button end}
            end
        end}),
        CurrentStackableSlotIds={Empty=function() f.selection={} end,
            Add=function(_,id,item) f.selection[id]=item; f.adds[id]=(f.adds[id] or 0)+1 end,
            Remove=function(_,id) f.selection[id]=nil end}})
    function StaticFindObject() return f.pal end
    f.dependencies={valid=function(o) return o and o:IsValid() end,
        unwrap=function(x)
            local ok,inner=pcall(function() return x:get() end)
            return ok and inner or x
        end,guid=function(x) return x end,
        sameGuid=function(a,b) return a.A==b.A end,nonzero=function(x) return x.A~=0 end,
        resolveTarget=function() return f.noBase and nil or f.base,f.remote end,
        activate=function(world) f.active=world end,
        containerAllows=function(_,id) count('container_'..id); return not f.denied[id] end,
        slotAllows=function(address,id) count('permission'); return not f.slotDenied[address] end,
        now=function() f.clock=f.clock+0.1; return f.clock end,
        defer=function(callback) f.queue[#f.queue+1]=callback end}
    f.preview=create(f.dependencies)
    function f:frame()
        local callback=table.remove(self.queue,1)
        assert(callback)
        local start=self.clock
        callback()
        assert(self.clock-start<3, 'frame budget exceeded')
    end
    function f:finish()
        for _=1,2000 do
            if #self.queue==0 then return end
            self:frame()
        end
        error('unbounded preview work')
    end
    function f:open() self.preview:arm(self.world); self.preview:opened(self.world) end
    return f
end
local f=fixture()
assert(#f.queue==0 and not f.counts.models) -- idle/opening/sorting do not scan
f:open()
assert(#f.queue>0 and not f.counts.models) -- the key only enqueues, never scans synchronously
f:frame()
assert(#f.queue==1) -- bounded work remains for another frame
f:finish()
assert(#f.queue==0 and f.counts.models==1)
assert(f.selection[100] and f.selection[101] and f.selection[102] and f.selection[103])
assert(not f.selection[104] and f.buttons[5].alpha==0.5)
assert(f.counts.data_wood==1 and f.counts.container_wood==1)
for _,adds in pairs(f.adds) do assert(adds==1) end
assert(#f.queue==0) -- completion has no polling timer
f.preview:excludeChanged(f.record,name('wood'),true)
assert(not f.selection[100] and not f.selection[101])
f.preview:excludeChanged(f.record,name('wood'),false)
assert(f.selection[100] and f.counts.models==1) -- exclusions only update the UI/map

-- Reproduce UE4SS's registered-state limitation instead of allowing the mock
-- to silently accept the broken coroutine implementation.
local rejected=coroutine.create(function() return f.world:IsValid() end)
local success,reason=coroutine.resume(rejected)
assert(not success and tostring(reason):find('unregistered coroutine',1,true))
-- Password authorization is also incremental, with the container cursor
-- preserved while scanning many password entries.
f=fixture()
local infos={}
for i=1,200 do infos[i]={PlayerUId=guid(i),TrySuccessCache=false} end
infos[200]={PlayerUId=guid(1),TrySuccessCache=true}
f.password=object({GetLockState=function() return 0 end,PlayerInfos=array(infos)})
f:open(); f:frame(); assert(#f.queue>0); f:finish()
assert(f.selection[100] and f.counts.models==1)
f=fixture(); f.password=object({GetLockState=function() return 0 end,PlayerInfos=array({})})
f:open(); f:finish(); assert(not next(f.selection))
f=fixture(); f.denied.stone=true; f.locked=true; f:open(); f:finish()
assert(not next(f.selection))
f=fixture(); f.denied.stone=true; f:open(); f:finish()
assert(not f.selection[102] and f.buttons[3].alpha==0.5 and f.selection[100])
f=fixture(); f.container.ItemSlotArray=array({}); f:open(); f:finish()
assert(not next(f.selection)) -- full chest
f=fixture(); f.record.Local_ItemQuickMoveExceptionIDList=array({name('wood')}); f:open(); f:finish()
assert(not f.selection[100] and f.selection[102])
f=fixture(); f:open(); f.preview:stop(true); f:finish()
assert(not f.counts.models and not f.active) -- sort/close cancels the already queued frame
f=fixture(); f:open(); f:frame()
local before=f.counts.models or 0
f.preview:stop(true); f:finish()
assert((f.counts.models or 0)==before and not f.active) -- sorting interrupts a running scan too
f=fixture(); f:open(); f:frame(); f.baseId=20; f:finish()
assert(not f.active and not next(f.selection)) -- moving bases cancels
f=fixture(true); f:open(); f:finish()
assert(f.selection[100] and f.selection[103] and not f.counts.models)
f=fixture(); f:open(); f.base.invalid=true; f:finish(); assert(not f.active)
f=fixture(); f:open(); f.visible=false; f:finish(); assert(not f.counts.models)
f=fixture(); f:open(); f.preview:arm(f.world); f.preview:opened(f.world); f:finish()
assert(f.counts.models==1) -- obsolete session callback never starts a duplicate scan
f=fixture(); f.world.CurrentInBaseCamp=false; f:open(); f:finish()
assert(not f.counts.models and not f.active)
-- 200 container records with 1000 slots each: no frame may execute an
-- unbounded pass. Category rejection must avoid reading those chest slots.
f=fixture()
local many={}
for i=1,200 do many[i]={OwnerMapObjectConcreteModelInstanceId=guid(i)} end
f.storage.ContainerInfos=array(many)
local slots={}
for i=1,1000 do slots[i]=f.container.ItemSlotArray[1] end
f.container.ItemSlotArray=array(slots)
f.pal.GetMapObjectManager=function()
    return object({FindConcreteModel=function(_,id)
        f.counts.models=(f.counts.models or 0)+1
        local container=object({address=1000+id.A,ItemSlotArray=f.container.ItemSlotArray})
        local chest=setmetatable({GetItemContainerModule=function()
            return object({GetContainer=function() return container end})
        end},{__index=f.chest})
        return chest
    end})
end
f.denied.wood=true; f.denied.stone=true; f.denied.egg=true
f:open(); f:finish()
assert(not next(f.selection) and f.counts.models==200)
assert(not f.counts.chestSlots and f.counts.container_wood==200)

-- Guild storage is a separate index/model and must work without an ordinary
-- chest. Its role permission, base ownership, filters and capacity still apply.
local function guildFixture()
    local g=fixture()
    g.storage.ContainerInfos=array({})
    g.storage.GuildContainerInfo={OwnerMapObjectConcreteModelInstanceId=guid(200)}
    g.bag[3].GetItemId=function()
        return {StaticId=name('food'),DynamicId={LocalIdInCreatedWorld=guid(0)}}
    end
    local guild=object({GetId=function() return guid(g.guildId or 1) end,
        ItemStorage=object({ItemContainer=g.container})})
    g.pal.GetPalmi=function() return object({}) end
    g.pal.GetLocalPlayerGuild=function() return guild end
    local chest=object({IsA=function(_,class) return class=='/Script/Pal.PalMapObjectGuildChestModel' end,
        GetBaseCampIdBelongTo=function() return guid(g.chestBaseId or 10) end,
        GetGuildSecurityModule=function() return object({CheckGuildSecurityAccess=function()
            return not g.guildDenied
        end}) end,
        IsLockedPrivateByNot=function() error('guild chest has no ordinary private lock') end,
        GetItemContainerModule=function() error('guild chest has no ordinary container module') end})
    g.pal.GetMapObjectManager=function() return object({FindConcreteModel=function(_,id)
        assert(id.A==200) -- resolved through the separate guild record
        return chest
    end}) end
    return g
end
f=guildFixture(); f:open(); f:finish()
assert(f.selection[102] and f.buttons[3].alpha==1)
f=guildFixture(); f.guildDenied=true; f:open(); f:finish(); assert(not next(f.selection))
f=guildFixture(); f.guildId=2; f:open(); f:finish(); assert(not next(f.selection))
f=guildFixture(); f.chestBaseId=20; f:open(); f:finish(); assert(not next(f.selection))
f=guildFixture(); f.denied.food=true; f:open(); f:finish(); assert(not f.selection[102])
f=guildFixture(); f.slotDenied[30]=true; f:open(); f:finish(); assert(not next(f.selection))
f=guildFixture(); f.container.ItemSlotArray=array({}); f:open(); f:finish(); assert(not next(f.selection))

-- Exercise the actual bootstrap: ordinary candidate/greyout notifications have
-- no Lua scan hook. Only the post-only ToggleQuickStackPanel callback starts a job; sorting cancels it.
f=fixture()
HOOKS={}
function RegisterHook(path,pre,post) HOOKS[path]={pre=pre,post=post} end
ExecuteInGameThreadAfterFrames=function(frames,callback) assert(frames==1); f.queue[#f.queue+1]=callback end
package.loadlib=function() return function()
    return {ready=function() return true end,inStorageScope=function() return true end,
        setPreview=function(address) f.active=address~=0 end,
        containerAllows=f.dependencies.containerAllows,slotAllows=f.dependencies.slotAllows,
        milliseconds=f.dependencies.now}
end end
assert(loadfile(SCRIPTS.."/main.lua"))()
assert(not HOOKS['/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos'])
assert(not HOOKS['/Script/Pal.PalStaticItemDataBase:HasDynamicItemClass'])
local prefix='/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C:'
local function param(x) return {get=function() return x end} end
HOOKS[prefix..'ToggleQuickStackPanel'].pre(param(f.world))
assert(not f.counts.models and #f.queue==1)
-- There is no script post callback: the first callback is already post-only.
assert(not HOOKS[prefix..'ToggleQuickStackPanel'].post)
HOOKS[prefix..'BndEvt__WBP_InventoryEquipment_WBP_InventoryEquipment_TabList_K2Node_ComponentBoundEvent_1_OnClickedSortButton__DelegateSignature'].pre()
assert(not f.active)
f:finish()
assert(not f.counts.models and #f.queue==0)
-- Remote entry needs the scoped fallback before any preview exists. The
-- native inventory scope is active, but opening the inventory must not scan.
local player=object({address=900,K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end})
local component=object({GetOwner=function() return player end})
local guild=object({BaseCampIds=array({guid(10)}),GetId=function() return guid(1) end})
f.base.GetGroupIdBelongTo=function() return guid(1) end
f.base.GetBuildingNum=function() return 10 end
f.base.GetTransform=function() return {Translation={X=1,Y=0,Z=0}} end
f.pal.GetPalmi=function() return player end
f.pal.GetLocalPlayerGuild=function() return guild end
f.pal.GetBaseCampManager=function() return object({TryGetModel=function(_,id,out) out.OutModel=f.base; return true end}) end
local getter='/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel'
assert(HOOKS[getter].post(param(component),param(nil))==f.base)
assert(not f.active and #f.queue==0 and not f.counts.models)
-- Closing the panel must preserve the collected map for native confirmation.
f:open(); f:finish()
f.visible=false
HOOKS[prefix..'ToggleQuickStackPanel'].pre(param(f.world))
assert(f.selection[100] and not f.active and #f.queue==0)
f=fixture()
-- Blueprint discovery is event-driven. Startup with an unloaded inventory
-- class neither registers missing functions nor creates a polling task.
HOOKS={}
local inventoryLoaded=false
function StaticFindObject(path)
    if path:find('ToggleQuickStackPanel',1,true) and not inventoryLoaded then return nil end
    return f.pal
end
local created
NotifyOnNewObject=function(_,callback) created=callback end
assert(loadfile(SCRIPTS.."/main.lua"))()
assert(created and not HOOKS[prefix..'ToggleQuickStackPanel'] and #f.queue==0)
inventoryLoaded=true
created(); created()
f:finish()
assert(HOOKS[prefix..'ToggleQuickStackPanel'] and not f.counts.models and #f.queue==0)
HOOKS={}
package.loadlib=function() return function() return function() return true end,function() return true end end end
assert(loadfile(SCRIPTS.."/main.lua"))()
assert(not next(HOOKS)) -- old bridge fails closed
