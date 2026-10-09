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
local ready, inStorageScope = loader()
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
local function nearestOwnedBase(component)
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
    local nearest, distance
    each(guild.BaseCampIds, function(id)
        if not nonzero(id) then return end
        local output = {}
        if not manager:TryGetModel(guid(id), output) then return end
        local model = output.OutModel
        if not valid(model) or not sameGuid(model:GetGroupIdBelongTo(), groupId) then return end
        local location = model:GetTransform().Translation
        local dx, dy, dz = location.X - x, location.Y - y, location.Z - z
        local squared = dx * dx + dy * dy + dz * dz
        if squared == squared and (not distance or squared < distance) then
            nearest, distance = model, squared
        end
    end)
    return nearest
end

-- Scope comes from native Blueprint pre/post callbacks, so it ends immediately
-- when inventory execution returns (including cancel and nested delegates).
if inStorageScope then
    RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel", function() end,
        function(context, original)
            if not ready() or not inStorageScope() or valid(unwrap(original)) then return end
            local ok, model = pcall(nearestOwnedBase, unwrap(context))
            if ok then return model end
            print("[EnhancedBulkStorage] nearest base lookup failed: " .. tostring(model) .. "\n")
        end)
    RegisterHook("/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID", function() end,
        function(context, original)
            if not ready() or not inStorageScope() or nonzero(original) then return end
            local ok, id = pcall(function()
                local model = nearestOwnedBase(unwrap(context))
                if valid(model) then return guid(model:GetId()) end
            end)
            if ok then return id end
            print("[EnhancedBulkStorage] nearest base ID lookup failed: " .. tostring(id) .. "\n")
        end)
end

RegisterHook("/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos", function() end,
    function(context, worldContext, staticItemIds, outItemInfos)
        if not ready() then return end
        local world = unwrap(worldContext)
        if not world or not world:IsValid() or not world:IsA(inventoryClass) or world.CurrentInBaseCamp ~= true then return end
        local ok, err = pcall(function()
            local utility = unwrap(context)
            local existing = unwrap(outItemInfos)
            local result, seen = {}, {}
            each(existing, function(info)
                local name = unwrap(info.StaticItemId)
                local id = name:ToString()
                if not seen[id] then
                    result[#result + 1] = { StaticItemId = FName(id), Num = unwrap(info.Num) }
                    seen[id] = true
                end
            end)
            local expanded = false
            -- The native caller supplies the names. Keep its exclusion handling,
            -- slot selection and confirmation; never enumerate equipment or chests.
            each(unwrap(staticItemIds), function(name)
                local id = name:ToString()
                if id ~= "None" and not seen[id] then
                    local count = utility:CountLocalPlayerInventoryItemNum64(world, name)
                    if count > 0 then
                        result[#result + 1] = { StaticItemId = FName(id), Num = math.min(count, 2147483647) }
                        seen[id], expanded = true, true
                    end
                end
            end)
            if not expanded then return end
            -- Release the previous TArray before UE4SS table marshaling replaces it.
            existing:Empty()
            outItemInfos:set(result)
        end)
        if not ok then print("[EnhancedBulkStorage] candidate update failed: " .. tostring(err) .. "\n") end
    end)
print("[EnhancedBulkStorage] official inventory candidate hook registered\n")
