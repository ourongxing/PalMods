local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = source:match("^(.*)/Scripts/[^/]+$")
local loader, errorMessage
if directory then
    loader, errorMessage = package.loadlib(directory .. "/dlls/main.dll", "luaopen_BetterBulkStorage")
end
if not loader then
    print("[BetterBulkStorage] native bridge unavailable; original storage retained: " .. tostring(errorMessage) .. "\n")
    return
end
local bridge = loader()
if type(bridge) ~= "table" or not bridge.ready or not bridge.inStorageScope
    or not bridge.setPreview or not bridge.containerAllows or not bridge.slotAllows
    or not bridge.milliseconds or not ExecuteInGameThreadAfterFrames then
    print("[BetterBulkStorage] incremental preview requires the updated DLL and frame scheduler; original storage retained\n")
    return
end
local ready, inStorageScope = bridge.ready, bridge.inStorageScope
local queryingPhysicalBase = false
local inventoryClass = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C"
local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end
    return value
end
local function each(array, callback)
    array:ForEach(function(_, value) callback(unwrap(value)) end)
end

local function valid(object)
    return object and object:IsValid()
end
local function noop() end
local function guid(value)
    value = unwrap(value)
    return { A = unwrap(value.A), B = unwrap(value.B), C = unwrap(value.C), D = unwrap(value.D) }
end
local function sameGuid(a, b)
    a, b = guid(a), guid(b)
    return a.A == b.A and a.B == b.B and a.C == b.C and a.D == b.D
end
local function nonzero(id)
    id = guid(id)
    return id.A ~= 0 or id.B ~= 0 or id.C ~= 0 or id.D ~= 0
end
local function largestOwnedBase(component)
    local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
    local groups = StaticFindObject("/Script/Pal.Default__PalGroupUtility")
    if not valid(utility) or not valid(groups) then return end
    local player = utility:GetPalmi(component)
    local owner = component:GetOwner()
    -- UE4SS constructs distinct Lua userdata wrappers for each UObject result.
    -- Compare the underlying UObject, not the Lua wrapper identity.
    if not valid(player) or not valid(owner) or owner:GetAddress() ~= player:GetAddress() then return end
    local guild = groups:GetLocalPlayerGuild(player)
    local manager = utility:GetBaseCampManager(player)
    if not valid(guild) or not valid(manager) then return end
    local groupId = guid(guild:GetId())
    if not nonzero(groupId) then return end
    local position = player:K2_GetActorLocation()
    local x, y, z = position.X, position.Y, position.Z
    local selected, buildingCount, distance
    each(guild.BaseCampIds, function(id)
        if not nonzero(id) then return end
        local output = {}
        if not manager:TryGetModel(guid(id), output) then return end
        local model = output.OutModel
        if not valid(model) or not sameGuid(model:GetGroupIdBelongTo(), groupId) then return end
        -- Read the base model's maintained count instead of loaded actors.
        -- No actor enumeration or per-building work on inventory callbacks.
        local count = unwrap(model:GetBuildingNum())
        if type(count) ~= "number" or count < 0 or count ~= count then return end
        local location = model:GetTransform().Translation
        local dx, dy, dz = location.X - x, location.Y - y, location.Z - z
        local squared = dx * dx + dy * dy + dz * dz
        if squared == squared and (not buildingCount or count > buildingCount
            or (count == buildingCount and squared < distance)) then
            selected, buildingCount, distance = model, count, squared
        end
    end)
    return selected
end

-- Scope comes from native Blueprint pre/post callbacks, so it ends immediately
-- when inventory execution returns (including cancel and nested delegates).
local function selectedBase(component, returnId)
    local ok, result = pcall(function()
        local model = largestOwnedBase(unwrap(component))
        if returnId then
            if valid(model) then return guid(model:GetId()) end
            return
        end
        return model
    end)
    if ok then return result end
    print("[BetterBulkStorage] largest base lookup failed: " .. tostring(result) .. "\n")
end
RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel", noop,
    function(context, original)
        if queryingPhysicalBase or not ready() or not inStorageScope() or valid(unwrap(original)) then return end
        return selectedBase(context, false)
    end)
RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID", noop,
    function(context, original)
        if queryingPhysicalBase or not ready() or not inStorageScope() or nonzero(original) then return end
        return selectedBase(context, true)
    end)
print("[BetterBulkStorage] outside-base selection: most buildings, nearest on ties\n")

local function resolveTarget(world)
    local pal = StaticFindObject("/Script/Pal.Default__PalUtility")
    if not valid(pal) then return end
    local player = pal:GetPalmi(world)
    if not valid(player) or not valid(player.InsideBaseCampCheckComponent) then return end
    local component = player.InsideBaseCampCheckComponent
    queryingPhysicalBase = true
    local ok, base = pcall(function() return component:GetInsideBaseCampModel() end)
    queryingPhysicalBase = false
    if not ok then error(base) end
    if valid(base) then return base, false end
    return largestOwnedBase(component), true
end
local createPreview = dofile(directory .. "/Scripts/Preview.lua")
local preview = createPreview({
    valid = valid, unwrap = unwrap, guid = guid, sameGuid = sameGuid, nonzero = nonzero,
    resolveTarget = resolveTarget,
    activate = function(world)
        bridge.setPreview(world and world:GetAddress() or 0)
    end,
    containerAllows = bridge.containerAllows, slotAllows = bridge.slotAllows,
    now = bridge.milliseconds,
    defer = function(callback) ExecuteInGameThreadAfterFrames(1, callback) end,
})
local prefix = inventoryClass .. ":"
local hooksInstalled=false
local function installInventoryHooks()
    if hooksInstalled or not valid(StaticFindObject(prefix .. "ToggleQuickStackPanel")) then return end
    -- UE4SS script RegisterHook invokes only its first callback, after execution.
    -- The native Toggle pre-callback suppresses vanilla greyout before this runs.
    RegisterHook(prefix .. "ToggleQuickStackPanel", function(context)
        local world = unwrap(context)
        if ready() and valid(world) then
            if valid(world.Canvas_QuickStack) and world.Canvas_QuickStack:IsVisible() then
                preview:arm(world)
                preview:opened(world)
            else
                preview:stop(false)
            end
        end
    end)
    RegisterHook(prefix .. "BndEvt__WBP_InventoryEquipment_WBP_InventoryEquipment_TabList_K2Node_ComponentBoundEvent_1_OnClickedSortButton__DelegateSignature",
        function() preview:stop(true) end)
    RegisterHook(prefix .. "Destruct", function() preview:stop(false) end)
    hooksInstalled=true
    print("[BetterBulkStorage] key-triggered incremental greyout ready; inventory sorting does not start scans\n")
end
-- Inventory Blueprint functions may not exist during Lua startup. Register
-- after the class is created, without a perpetual world/inventory polling loop.
if NotifyOnNewObject then
    NotifyOnNewObject(inventoryClass,function()
        ExecuteInGameThreadAfterFrames(1,installInventoryHooks)
    end)
end
installInventoryHooks()
RegisterHook("/Script/CommonUI.CommonActivatableWidget:BP_OnDeactivated", function(context)
    local world=unwrap(context)
    if valid(world) and world:IsA(inventoryClass) then preview:stop(true) end
end)
RegisterHook("/Script/Pal.PalPlayerLocalRecordData:AddQuickStackExceptId", noop,
    function(context, name, result)
        if unwrap(result)==true then preview:excludeChanged(unwrap(context),unwrap(name),true) end
    end)
RegisterHook("/Script/Pal.PalPlayerLocalRecordData:RemoveQuickStackExceptId", noop,
    function(context, name) preview:excludeChanged(unwrap(context),unwrap(name),false) end)
RegisterHook("/Script/Pal.PalPlayerLocalRecordData:ResetQuickStackExceptList",
    function() preview:stop(true) end)
