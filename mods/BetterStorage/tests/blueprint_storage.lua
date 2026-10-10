local module = assert(loadfile(SCRIPTS .. '/BlueprintStorage.lua'))()
local function array(values)
    values.Empty = function(self) for i = #self, 1, -1 do self[i] = nil end end
    return values
end
local function object(value)
    value.IsValid = function() return true end
    value.GetAddress = function() return value.address end
    return value
end
local function permission()
    return {PermissionTypeA=array({5}), PermissionTypeB=array({26}), PermissionItemStaticIds=array({'Wood'})}
end
local function chest(id, capacity)
    local container = object({Permission=permission(),capacity=capacity,items={'Wood','Blueprint'}})
    local inventory = object({GetContainer=function() return container end})
    return object({address=id,TryGetMapObjectId=function() return {ToString=function() return id end} end,
        GetItemContainerModule=function() return inventory end}), container, inventory
end
local shelf, shelfContainer, shelfModule = chest('Shelf01_Stone',24)
local cabinet, cabinetContainer = chest('Shelf07_Stone',40)
local other, otherContainer = chest('Shelf05_Stone',20)
local models={shelf,cabinet,other}
local parameters={}
for _, id in ipairs({'Shelf01_Stone','Shelf07_Stone','Shelf05_Stone'}) do
    parameters[#parameters+1]=object({SlotNum=20,TargetTypesA=array({5}),TargetTypesB=array({26}),
        GetFullName=function() return 'PalMapObjectItemChestParameterComponent /Game/Pal/Blueprint/MapObject/BuildObject/Furniture/BP_BuildObject_'..id..'.BP_BuildObject_'..id..'_C:PalMapObjectItemChestParameter_GEN_VARIABLE' end})
end
local server, work, loop, calls = true, {}, nil, 0
local world=object({address=1})
FindFirstOf=function() return world end
StaticFindObject=function() return object({IsServer=function() return server end}) end
FindAllOf=function(name) if name=='PalMapObjectItemChestParameterComponent' then return parameters end return models end
ExecuteInGameThread=function(callback) work[#work+1]=callback end
LoopAsync=function(delay,callback) assert(delay==5000);loop=callback end
local function flush() local pending=work;work={};for _,callback in ipairs(pending) do callback() end end
local bridge={growBlueprintStorage=function(w,id,slots)
    assert(server and w==1);calls=calls+1
    assert(slots >= 1 and slots <= 4096 and slots == math.floor(slots))
    local container=id=='Shelf01_Stone' and shelfContainer or cabinetContainer
    container.capacity=math.max(container.capacity,slots)
    return container.capacity
end}
module.start(bridge,SCRIPTS);assert(calls==0);flush()
assert(calls==2 and shelfContainer.capacity==360 and cabinetContainer.capacity==360)
assert(shelfModule.DisplayContainerSlotNumDefault==360)
for _,container in ipairs({shelfContainer,cabinetContainer}) do
    assert(#container.Permission.PermissionTypeA==1 and container.Permission.PermissionTypeA[1]==12)
    assert(#container.Permission.PermissionTypeB==0 and #container.Permission.PermissionItemStaticIds==0)
    assert(container.items[1]=='Wood' and container.items[2]=='Blueprint')
end
assert(otherContainer.capacity==20 and otherContainer.Permission.PermissionTypeA[1]==5)
assert(parameters[1].SlotNum==360 and parameters[2].SlotNum==360 and parameters[3].SlotNum==20)
loop();loop();assert(#work==1);flush();assert(calls==4)
cabinetContainer.capacity=540;loop();flush();assert(cabinetContainer.capacity==540)
server=false;loop();flush();assert(calls==6)
server=true
local late,lateContainer=chest('Shelf07_Stone',40)
models={late};cabinetContainer=lateContainer
loop();flush();assert(lateContainer.capacity==360 and lateContainer.Permission.PermissionTypeA[1]==12)
local realLoadfile=loadfile
local function configure(value, expected)
    loadfile=function(path)
        assert(path==SCRIPTS..'/config.lua')
        return function() return {BlueprintChestSlots=value} end
    end
    shelf,shelfContainer,shelfModule=chest('Shelf01_Stone',24)
    cabinet,cabinetContainer=chest('Shelf07_Stone',40)
    models={shelf,cabinet};work={};calls=0
    module.start(bridge,SCRIPTS);flush()
    assert(calls==2 and shelfContainer.capacity==math.max(24,expected)
        and cabinetContainer.capacity==math.max(40,expected))
    assert(parameters[1].SlotNum==expected and parameters[2].SlotNum==expected)
    assert(shelfModule.DisplayContainerSlotNumDefault==expected)
end
for _,value in ipairs({1,180,540,4096}) do configure(value,value) end
for _,value in ipairs({0,-1,4097,360.5,'540',math.huge,0/0,false}) do configure(value,360) end
configure(nil,360)
loadfile=function() error('missing config') end
module.start(bridge,SCRIPTS);flush();assert(parameters[1].SlotNum==360 and parameters[2].SlotNum==360)
loadfile=realLoadfile
print('PASS: blueprint chest capacity default/config validation, shared furniture capacity, scope, permissions, item retention, authority, late loading and grow-only capacity')
