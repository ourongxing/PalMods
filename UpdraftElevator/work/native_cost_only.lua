-- The PAK owns wind components; a native successful-jump hook activates lift.
-- No actor tracking, world scans, update loop, spawn calls or keyboard bindings.
local TECHNOLOGY = "CodexWindTechnology"
local WIND = {CodexWindNativeSmall=true, CodexWindNativeMedium=true, CodexWindNativeLarge=true}
local function Valid(object)
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end
local function Value(x)
    local ok, value = pcall(function() return x:get() end)
    return ok and value or x
end
local function Name(x)
    x = Value(x)
    if type(x) == "string" then return x end
    local ok, value = pcall(function() return x:ToString() end)
    return ok and value or ""
end
-- Generated from wind_variants.json by the packager (centimetres).
local HEIGHTS = {CodexWindNativeSmall=800, CodexWindNativeMedium=1600, CodexWindNativeLarge=3200}
local configOk, config = pcall(require, "config")
if configOk and type(config) == "table" then
    for _, size in ipairs({"Small", "Medium", "Large"}) do
        local meters = config[size]
        if type(meters) == "number" and meters == meters and meters >= 0.1 and meters <= 1000 then
            HEIGHTS["CodexWindNative" .. size] = meters * 100
        elseif meters ~= nil then
            print("[Updraft Elevator] Invalid config height for " .. size .. "; using default.\n")
        end
    end
else
    print("[Updraft Elevator] config.lua missing or invalid; using default heights.\n")
end
print(string.format("[Updraft Elevator] Height configuration (m): Small=%g Medium=%g Large=%g\n",
    HEIGHTS.CodexWindNativeSmall / 100, HEIGHTS.CodexWindNativeMedium / 100, HEIGHTS.CodexWindNativeLarge / 100))
local jumpErrors = 0
local function JumpLift(context, component)
    local ok, err = pcall(function()
        local player = Value(context)
        if not Valid(player) or not player:IsPlayerControlled() or not player:IsLocallyControlled() then return end
        local movement = Value(component)
        if not Valid(movement) then return end
        -- Only inspect the jumping player's existing overlap list, once per jump.
        local overlapping = {}
        player:GetOverlappingActors(overlapping, nil)
        local height = 0
        for _, wrapped in pairs(overlapping) do
            local wind = Value(wrapped)
            if Valid(wind) then
                -- Ordinary actors need not expose BuildObjectId.
                local isWind, id = pcall(function() return Name(wind.BuildObjectId) end)
                local candidate = isWind and HEIGHTS[id] or nil
                if candidate and wind:IsAvailable() and not wind:IsActorBeingDestroyed() then
                    height = math.max(height, candidate)
                end
            end
        end
        if height == 0 then return end
        local gravity = math.abs(movement:GetGravityZ())
        if gravity < 1 then return end
        -- Preserve horizontal movement, replace Z once; overlapping winds do not stack.
        player:LaunchCharacter({X=0, Y=0, Z=math.sqrt(2 * gravity * height)}, false, true)
    end)
    if not ok and jumpErrors < 3 then
        jumpErrors = jumpErrors + 1
        print("[Updraft Elevator] Jump lift error: " .. tostring(err) .. "\n")
    end
end
-- Pal movement broadcasts this only after a successful jump, unlike RequestJump.
local jumpHookOk, jumpHookError = pcall(function()
    RegisterHook("/Script/Pal.PalCharacter:OnJump", function() end, JumpLift)
end)
if not jumpHookOk then print("[Updraft Elevator] Jump hook unavailable: " .. tostring(jumpHookError) .. "\n") end
-- Require the new paid technology even in saves with old free unlock IDs.
-- Leave material checks and point spending entirely to the game.
RegisterHook("/Script/Pal.PalTechnologyData:IsUnlockBuildObject", function() end,
    function(context, id)
        local name = Name(id)
        if WIND[name] then
            local tech = Value(context)
            if not Valid(tech) then return false end
            return tech:IsUnlockRecipeTechnology(FName(TECHNOLOGY))
        end
    end)
print("[Updraft Elevator] Wind lift v8: configurable heights; level 9 ancient technology, cost 1.\n")
