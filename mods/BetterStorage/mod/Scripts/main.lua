local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = source:match("^(.*)/Scripts/[^/]+$")
local loader, errorMessage
if directory then
    loader, errorMessage = package.loadlib(directory .. "/dlls/main.dll", "luaopen_BetterStorage")
end
if not loader then
    print("[BetterStorage] native bridge unavailable; original storage retained: " .. tostring(errorMessage) .. "\n")
    return
end
local bridge = loader()
if type(bridge) == "table" and bridge.growGuildStorage and directory then
    local file = io.open(directory .. "/../PalSchema/mods/BetterStorage/blueprints/storage.json", "r")
    local data = file and file.read(file, "*a")
    if file then file.close(file) end
    local slots = data and tonumber(data:match('"GuildChestSlotNum"%s*:%s*([%d%.eE%+%-]+)'))
    if slots and slots % 1 == 0 and slots >= 54 and slots <= 4096 then
        assert(loadfile(directory .. "/Scripts/GuildStorage.lua"))().start(bridge, slots)
    else
        print("[BetterStorage] guild migration disabled: missing or invalid PalSchema GuildChestSlotNum\n")
    end
end
if type(bridge) ~= "table" or not bridge.ready or not bridge.inStorageScope then
    print("[BetterStorage] simple bridge unavailable; original storage retained\n")
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
local function largestOwnedBase(component, utility)
    utility = utility or StaticFindObject("/Script/Pal.Default__PalUtility")
    local groups = StaticFindObject("/Script/Pal.Default__PalGroupUtility")
    if not valid(utility) or not valid(groups) then return end
    local player = utility:GetPalmi(component)
    local owner = component:GetOwner()
    -- UObject wrappers have distinct Lua identities; compare their addresses.
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

local function physicalBase(component)
    queryingPhysicalBase = true
    local ok, base = pcall(function() return component:GetInsideBaseCampModel() end)
    queryingPhysicalBase = false
    if not ok then error(base) end
    return base
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
    print("[BetterStorage] largest base lookup failed: " .. tostring(result) .. "\n")
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
print("[BetterStorage] outside-base selection: most buildings, nearest on ties\n")

-- The local-player collector reads the physical base through native calls,
-- bypassing reflected getter hooks. Outside a base, call its exact underlying
-- collector with the selected base ID; keep vanilla eligibility and quantities.
RegisterHook("/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos", noop,
    function(context, worldContext, staticItemIds, outItemInfos)
        if not ready() or not inStorageScope() then return end
        local world = unwrap(worldContext)
        if not valid(world) or not world:IsA(inventoryClass) or world.CurrentInBaseCamp ~= true then return end
        local ok, err = pcall(function()
            local pal = StaticFindObject("/Script/Pal.Default__PalUtility")
            if not valid(pal) then return end
            local player = pal:GetPalmi(world)
            if not valid(player) or not valid(player.InsideBaseCampCheckComponent) then return end
            local component = player.InsideBaseCampCheckComponent
            if valid(physicalBase(component)) then return end
            local base = largestOwnedBase(component, pal)
            if not valid(base) then return end
            local baseUtility = StaticFindObject("/Script/Pal.Default__PalBaseCampUtility")
            local controller = pal:GetLocalPalPlayerController(world)
            if not valid(baseUtility) or not valid(controller) then return end
            local names = {}
            each(unwrap(staticItemIds), function(name) names[#names + 1] = name end)
            local collected = {}
            baseUtility:CollectQuickStackTargetItemInfos(world, guid(base:GetId()),
                guid(controller:GetPlayerUId()), names, collected)
            local result = {}
            for _, value in ipairs(collected) do
                local info = unwrap(value)
                result[#result + 1] = { StaticItemId = unwrap(info.StaticItemId), Num = unwrap(info.Num) }
            end
            local existing = unwrap(outItemInfos)
            existing:Empty()
            outItemInfos:set(result)
        end)
        if not ok then print("[BetterStorage] remote candidates failed: " .. tostring(err) .. "\n") end
    end)
