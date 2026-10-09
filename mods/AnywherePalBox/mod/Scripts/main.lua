local TAG = "[AnywherePalBox] "
local hotkey = "K"
local loaded, config = pcall(require, "config")
if loaded and type(config) == "table" and type(config.Hotkey) == "string" then
    local name = config.Hotkey:upper():match("^%s*(.-)%s*$")
    if type(Key[name]) == "number" then
        hotkey = name
    else
        print(TAG .. "invalid Hotkey; using K\n")
    end
else
    print(TAG .. "config missing or invalid; using K\n")
end

local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end
    return value
end
local function valid(object) return object and object:IsValid() end
local function guid(value)
    value = unwrap(value)
    return {A=unwrap(value.A), B=unwrap(value.B), C=unwrap(value.C), D=unwrap(value.D)}
end
local function nonzero(value)
    local id = guid(value)
    return id.A ~= 0 or id.B ~= 0 or id.C ~= 0 or id.D ~= 0
end
local function sameGuid(a, b)
    a, b = guid(a), guid(b)
    return a.A == b.A and a.B == b.B and a.C == b.C and a.D == b.D
end
-- Resolve the current base, or rank guild bases by building count and distance.
local function chooseBase(player, guild, manager)
    local groupId = guid(guild:GetId())
    if not nonzero(groupId) then return end
    local component = player.InsideBaseCampCheckComponent
    if not valid(component) then return end
    local inside = component:GetInsideBaseCampModel()
    if valid(inside) then
        if sameGuid(inside:GetGroupIdBelongTo(), groupId) then return inside end
        return -- Do not open another guild's terminal or redirect while inside it.
    end
    local position = player:K2_GetActorLocation()
    local selected, buildingCount, distance
    guild.BaseCampIds:ForEach(function(_, value)
        local id = unwrap(value)
        if not nonzero(id) then return end
        local output = {}
        if not manager:TryGetModel(guid(id), output) then return end
        local model = output.OutModel
        if not valid(model) or not sameGuid(model:GetGroupIdBelongTo(), groupId) then return end
        local count = unwrap(model:GetBuildingNum())
        if type(count) ~= "number" or count < 0 or count ~= count then return end
        local location = model:GetTransform().Translation
        local dx, dy, dz = location.X-position.X, location.Y-position.Y, location.Z-position.Z
        local squared = dx*dx + dy*dy + dz*dz
        if squared == squared and (not buildingCount or count > buildingCount
            or (count == buildingCount and squared < distance)) then
            selected, buildingCount, distance = model, count, squared
        end
    end)
    return selected
end

local function skip(reason) print(TAG .. "skipped: " .. reason .. "\n") end
local function openTerminal()
    local world = FindFirstOf("PalPlayerController")
    local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
    local groups = StaticFindObject("/Script/Pal.Default__PalGroupUtility")
    if not valid(world) or not valid(utility) or not valid(groups) then return skip("player controller or utilities unavailable") end
    local controller = utility:GetLocalPalPlayerController(world)
    if not valid(controller) then return skip("local controller unavailable") end
    local player = utility:GetPalmi(controller)
    local service = utility:GetHUDService(controller)
    if not valid(player) or not valid(service) then return skip("player or HUD service unavailable") end
    if service:IsAnyOverlayUIActive() or service:IsAnyFadeWidgetActive() then return skip("menu or fade active") end
    local guild = groups:GetLocalPlayerGuild(player)
    local manager = utility:GetBaseCampManager(player)
    if not valid(guild) or not valid(manager) then return skip("guild or base manager unavailable") end
    local base = chooseBase(player, guild, manager)
    if not valid(base) then return skip("no accessible base camp") end
    local baseId, ownerId = guid(base:GetId()), guid(base:GetOwnerMapObjectInstanceId())
    if not nonzero(baseId) or not nonzero(ownerId) then return skip("base or terminal ID unavailable") end
    local objects = utility:GetMapObjectManager(player)
    if not valid(objects) then return skip("map object manager unavailable") end
    local model = objects:FindModel(ownerId)
    if not valid(model) then return skip("selected terminal model unavailable") end
    local terminal = model:GetConcreteModel(true)
    if not valid(terminal) then return skip("selected terminal concrete model unavailable") end
    if not terminal:IsA("/Script/Pal.PalMapObjectBaseCampPoint")
        or not sameGuid(terminal.BaseCampId, baseId)
        or not terminal:IsSameGuildInLocalPlayer() then return skip("terminal ownership or base mismatch") end
    -- Let the terminal handle its menu and interaction lifecycle.
    terminal:OnTriggerInteract(player, 11) -- EPalInteractiveObjectIndicatorType::OpenPalBoxMenu
    print(TAG .. "requested terminal interaction; base=" .. tostring(baseId.A) .. ":" .. tostring(baseId.B)
        .. ":" .. tostring(baseId.C) .. ":" .. tostring(baseId.D) .. "\n")
end

local pending = false
RegisterKeyBind(Key[hotkey], function()
    if pending then return end
    pending = true
    local queued, queueError = pcall(ExecuteInGameThread, function()
        local ok, err = pcall(openTerminal)
        pending = false
        if not ok then print(TAG .. "open failed: " .. tostring(err) .. "\n") end
    end)
    if not queued then
        pending = false
        print(TAG .. "game-thread dispatch failed: " .. tostring(queueError) .. "\n")
    end
end)
print(TAG .. "1.0.0 loaded; hotkey=" .. hotkey .. ": current base inside; most buildings outside, nearest on ties\n")
