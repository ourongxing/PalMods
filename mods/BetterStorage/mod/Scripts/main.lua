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

-- Vanilla's local-player subscription resolves physical location in native code.
-- Own only the extra remote subscription, through this player's RPC component.
local remoteSession
local replicatedBase, replicatedModule
local traceBudget = 30
local function trace(message)
    if traceBudget <= 0 then return end
    traceBudget = traceBudget - 1
    print("[BetterStorage] sync: " .. message .. "\n")
end
local function releaseRemote()
    local session = remoteSession
    remoteSession = nil
    if session and valid(session.network) then
        session.network:RequestReplicateBaseCampItemStackInfo_ToServer(session.id, false)
    end
end
RegisterHook("/Script/Pal.PalBaseCampUtility:RequestStartReplicateLocalPlayerBaseCampItemStackInfo", noop,
    function(_, worldContext)
        trace("prepare ready=" .. tostring(ready()) .. " scope=" .. tostring(inStorageScope()))
        if not ready() or not inStorageScope() then return end
        local world = unwrap(worldContext)
        if not valid(world) or not world:IsA(inventoryClass) then trace("not inventory context"); return end
        local ok, err = pcall(function()
            local pal = StaticFindObject("/Script/Pal.Default__PalUtility")
            if not valid(pal) then trace("utility unavailable"); return end
            local player = pal:GetPalmi(world)
            if not valid(player) or not valid(player.InsideBaseCampCheckComponent) then trace("player unavailable"); return end
            local component = player.InsideBaseCampCheckComponent
            if valid(physicalBase(component)) then trace("physical base: vanilla subscription"); return end
            local base = largestOwnedBase(component, pal)
            local controller = pal:GetLocalPalPlayerController(world)
            if not valid(base) then trace("selected base unavailable"); return end
            if not valid(controller) or not valid(controller.Transmitter) then trace("owned transmitter unavailable"); return end
            local network = controller.Transmitter:GetBaseCamp()
            if not valid(network) then trace("base network unavailable"); return end
            local id = guid(base:GetId())
            if remoteSession and valid(remoteSession.world)
                and remoteSession.world:GetAddress() == world:GetAddress()
                and sameGuid(remoteSession.id, id) then return end
            releaseRemote()
            remoteSession = {world = world, network = network, id = id, base = base}
            network:RequestReplicateBaseCampItemStackInfo_ToServer(id, true)
            trace("requested selected base " .. tostring(id.A) .. ":" .. tostring(id.B))
        end)
        if not ok then print("[BetterStorage] remote subscription failed: " .. tostring(err) .. "\n") end
    end)
RegisterHook("/Script/Pal.PalBaseCampUtility:RequestEndReplicateLocalPlayerBaseCampItemStackInfo", noop,
    function(_, worldContext)
        if remoteSession then trace("finish received") end
        local world = unwrap(worldContext)
        if not remoteSession or not valid(world) or not valid(remoteSession.world)
            or world:GetAddress() ~= remoteSession.world:GetAddress() then return end
        local ok, err = pcall(releaseRemote)
        if not ok then print("[BetterStorage] remote unsubscribe failed: " .. tostring(err) .. "\n") end
    end)
RegisterHook("/Script/Pal.PalBaseCampModuleItemStackInfo:OnRep_ItemStackRepInfoArray", noop,
    function(context)
        local session = remoteSession
        if session then trace("inventory replication received") end
        if not session or not ready() or not valid(session.world) then return end
        local ok, err = pcall(function()
            if not session.world:IsVisible() then releaseRemote(); return end
            local module = unwrap(context)
            if not valid(module) or not valid(session.base) then return end
            local owner = module:GetOuter()
            if not valid(owner) or owner:GetAddress() ~= session.base:GetAddress() then trace("replication belongs to another model"); return end
            replicatedBase, replicatedModule = session.base, module
            -- Use the normal ready/update route: it recollects the selected base's
            -- exact eligible items, then finishes this one-shot subscription.
            session.world:OnQuickStackItemStackInfoUpdate(module)
            trace("inventory refresh dispatched")
        end)
        if not ok then print("[BetterStorage] remote update failed: " .. tostring(err) .. "\n") end
    end)

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
            -- The vanilla explicit-base collector resolves concrete containers.
            -- Those may not exist on a remote client. Use the server's replicated
            -- chest summaries instead, with its private-lock and guild-role rules.
            if valid(replicatedBase) and valid(replicatedModule)
                and replicatedBase:GetAddress() == base:GetAddress() then
                local groups = StaticFindObject("/Script/Pal.Default__PalGroupUtility")
                local guild = valid(groups) and groups:GetLocalPlayerGuild(player)
                if not valid(guild) then return end
                local uid = guid(controller:GetPlayerUId())
                local role = unwrap(guild:GetPlayerRole(uid))
                local wanted, totals = {}, {}
                for _, name in ipairs(names) do wanted[name:ToString()] = name end
                each(replicatedModule.ItemStackRepInfoArray.Items, function(chest)
                    local available, privateCount = false, 0
                    each(chest.AvailablePlayerUIds, function(id)
                        privateCount = privateCount + 1
                        if sameGuid(id, uid) then available = true end
                    end)
                    if privateCount > 0 and not available then return end
                    if unwrap(chest.bHasGuildSecurityRestriction) and role ~= 1 then
                        local allowed = false
                        each(chest.AllowedRoles, function(value) if unwrap(value) == role then allowed = true end end)
                        if not allowed then return end
                    end
                    each(chest.ItemStackInfos, function(info)
                        local name = unwrap(info.ItemId.StaticId):ToString()
                        local count = unwrap(info.StackCount)
                        if wanted[name] and type(count) == "number" and count > 0 then
                            totals[name] = math.min(2147483647, (totals[name] or 0) + count)
                        end
                    end)
                end)
                collected = {}
                for _, name in ipairs(names) do
                    local count = totals[name:ToString()]
                    if count then collected[#collected + 1] = {StaticItemId = name, Num = count} end
                end
                trace("replicated candidates=" .. tostring(#collected))
            end
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
