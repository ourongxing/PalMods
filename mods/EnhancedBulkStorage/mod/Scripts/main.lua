local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = source:match("^(.*)/Scripts/[^/]+$")
local loader, errorMessage
if directory then
    loader, errorMessage = package.loadlib(directory .. "/dlls/main.dll", "luaopen_EnhancedBulkStorage")
end
if not loader then
    print("[EnhancedBulkStorage] native bridge unavailable; original storage retained: " .. tostring(errorMessage) .. "\n")
    return
end
local ready, inStorageScope, inCandidateScope, acceptsItem = loader()
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
local function beforeHook() end
local queryingPhysicalBase = false
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
if inStorageScope then
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
        print("[EnhancedBulkStorage] largest base lookup failed: " .. tostring(result) .. "\n")
    end
    RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel", beforeHook,
        function(context, original)
            if queryingPhysicalBase or not ready() or not inStorageScope() or valid(unwrap(original)) then return end
            return selectedBase(context, false)
        end)
    RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID", beforeHook,
        function(context, original)
            if queryingPhysicalBase or not ready() or not inStorageScope() or nonzero(original) then return end
            return selectedBase(context, true)
        end)
    print("[EnhancedBulkStorage] outside-base selection: most buildings, nearest on ties\n")
end

-- The inventory's candidate-building function skips dynamic items before
-- CollectLocalPlayerQuickStackTargetItemInfos is called. Admit only Pal eggs
-- there; keep their real dynamic IDs for the official slot transfer afterwards.
-- MaterialPalEgg = 30 in the supported game's EPalItemTypeB.
if inCandidateScope then
    RegisterHook("/Script/Pal.PalStaticItemDataBase:HasDynamicItemClass", beforeHook,
        function(context, original)
            if not ready() or not inCandidateScope() or unwrap(original) ~= true then return end
            local ok, isEgg = pcall(function()
                local data = unwrap(context)
                return valid(data) and unwrap(data.TypeB) == 30
            end)
            if not ok then
                print("[EnhancedBulkStorage] egg candidate lookup failed: " .. tostring(isEgg) .. "\n")
                return
            end
            if isEgg then return false end
        end)
    print("[EnhancedBulkStorage] scoped Pal egg candidate hook registered\n")
else
    print("[EnhancedBulkStorage] egg candidate scope unavailable; update companion DLL\n")
end

-- Resolve only this operation's destination. No cross-base container cache.
local function destinationSlots(world)
    if not acceptsItem or not inStorageScope or not inStorageScope() then return end
    local pal = StaticFindObject("/Script/Pal.Default__PalUtility")
    if not valid(pal) then return end
    local player = pal:GetPalmi(world)
    if not valid(player) then return end
    local component = player.InsideBaseCampCheckComponent
    if not valid(component) then return end
    -- Read actual location without our scoped outside-base getter fallback.
    queryingPhysicalBase = true
    local ok, base = pcall(function() return component:GetInsideBaseCampModel() end)
    queryingPhysicalBase = false
    if not ok then error(base) end
    if not valid(base) then
        -- Remote chests need not be loaded on this client. Keep the established
        -- remote candidate behavior; the official server validates the transfer.
        if valid(largestOwnedBase(component)) then return nil, nil, false, true end
        return
    end
    if not valid(base) or not valid(base.MapObjectCollection) then return end
    local manager = pal:GetMapObjectManager(world)
    local controller = pal:GetLocalPalPlayerController(world)
    local items = pal:GetItemIDManager(world)
    if not valid(manager) or not valid(controller) or not valid(items) then return end
    local uid, baseId = guid(controller:GetPlayerUId()), guid(base:GetId())
    local slots, complete, seen = {}, true, {}
    each(base.MapObjectCollection.MapObjectInstanceIdRepInfoArray.Items, function(info)
        local model = manager:FindModel(guid(info.InstanceId))
        if not valid(model) then complete = false; return end
        local chest = model:GetConcreteModel(false)
        if not valid(chest) then complete = false; return end
        if not chest:IsA("/Script/Pal.PalMapObjectItemChestModel")
            or not sameGuid(chest:GetBaseCampIdBelongTo(), baseId)
            or chest:IsLockedPrivateByNot(uid) then return end
        local security = chest:GetGuildSecurityModule()
        if valid(security) and not security:CheckGuildSecurityAccess(uid) then return end
        local lock = chest:GetPasswordLockModule()
        if valid(lock) and unwrap(lock:GetLockState()) == 0 then
            local unlocked = false
            each(lock.PlayerInfos, function(entry)
                if sameGuid(entry.PlayerUId, uid) and unwrap(entry.TrySuccessCache) == true then unlocked = true end
            end)
            if not unlocked then return end
        end
        local module = chest:GetItemContainerModule()
        if not valid(module) then complete = false; return end
        local container = module:GetContainer()
        if not valid(container) then complete = false; return end
        local address = container:GetAddress()
        if seen[address] then return end
        seen[address] = true
        each(container.ItemSlotArray, function(slot)
            if not valid(slot) then complete = false; return end
            if slot:IsEmpty() then
                slots[#slots + 1] = {container = container, slot = slot}
            elseif not slot:IsMaxStack() and not nonzero(slot:GetItemId().DynamicId.LocalIdInCreatedWorld) then
                slots[#slots + 1] = {container = container, slot = slot,
                    id = slot:GetItemId().StaticId:ToString()}
            end
        end)
    end)
    return slots, items, complete
end

local function canStore(slots, data, id)
    if not valid(data) then return false end
    for _, entry in ipairs(slots) do
        if (not entry.id or entry.id == id)
            and acceptsItem(entry.container:GetAddress(), entry.slot:GetAddress(), data:GetAddress()) then return true end
    end
    return false
end

RegisterHook("/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos", beforeHook,
    function(context, worldContext, staticItemIds, outItemInfos)
        if not ready() then return end
        local world = unwrap(worldContext)
        if not valid(world) or not world:IsA(inventoryClass) or world.CurrentInBaseCamp ~= true then return end
        local ok, err = pcall(function()
            local utility = unwrap(context)
            local existing = unwrap(outItemInfos)
            local slots, items, complete, remote = destinationSlots(world)
            local result, seen = {}, {}
            local changed = false
            each(existing, function(info)
                local name = unwrap(info.StaticItemId)
                local id = name:ToString()
                if not seen[id] and (not complete or canStore(slots, items:GetStaticItemData(name), id)) then
                    result[#result + 1] = { StaticItemId = FName(id), Num = unwrap(info.Num) }
                    seen[id] = true
                else
                    changed = true
                end
            end)
            -- The native caller supplies the names. Keep its exclusion handling,
            -- slot selection and confirmation; never enumerate equipment.
            each(unwrap(staticItemIds), function(name)
                local id = name:ToString()
                if id ~= "None" and not seen[id]
                    and (remote or (slots and canStore(slots, items:GetStaticItemData(name), id))) then
                    local count = utility:CountLocalPlayerInventoryItemNum64(world, name)
                    if count > 0 then
                        result[#result + 1] = { StaticItemId = FName(id), Num = math.min(count, 2147483647) }
                        seen[id], changed = true, true
                    end
                end
            end)
            if not changed then return end
            -- Release the previous TArray before UE4SS table marshaling replaces it.
            existing:Empty()
            outItemInfos:set(result)
        end)
        if not ok then print("[EnhancedBulkStorage] candidate update failed: " .. tostring(err) .. "\n") end
    end)
print("[EnhancedBulkStorage] official inventory candidate hook registered\n")
