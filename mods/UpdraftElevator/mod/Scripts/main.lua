-- The PAK owns collision-only native jump-spot children. The game owns
-- jump eligibility, the original prepare montage, animation notify and launch.
-- Lua selects a modifier on overlap changes; no polling or keyboard bindings.
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
-- Register before PalSchema loads BuildingData. Keep every vanilla category value.
local categoryOk, categoryError = pcall(function()
    local categories = StaticFindObject("/Script/Pal.EPalBuildObjectTypeForUIDisplay")
    assert(Valid(categories), "Build menu category enum unavailable")
    local customName = "EPalBuildObjectTypeForUIDisplay::CodexWindUpdraft"
    local categoryValue, maxValue, maxIndex
    local index = 0
    categories:ForEachName(function(name, value)
        local entry = Name(name)
        if entry == customName then categoryValue = value end
        if entry == "EPalBuildObjectTypeForUIDisplay::EPalBuildObjectTypeForUIDisplay_MAX" then
            maxValue, maxIndex = value, index
        end
        index = index + 1
    end)
    if categoryValue == nil then
        assert(maxValue and maxIndex and maxValue < 255, "No build category slot available")
        categoryValue = maxValue
        categories:InsertIntoNames(customName, categoryValue, maxIndex, true)
    end
    RegisterHook("/Script/Pal.PalUIUtility:GetBuildObjectUIDIsplayCategoryTextId", function() end,
        function(_, world, displayType, outText)
            if Value(displayType) ~= categoryValue then return end
            local tables = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
            -- Reuse the translated technology name instead of overriding vanilla "Other".
            outText:set(tables:GetLocalizedText(Value(world), 18, FName("NAME_RECIPE_" .. TECHNOLOGY)))
        end)
end)
if not categoryOk then print("[Updraft Elevator] Build category unavailable: " .. tostring(categoryError) .. "\n") end
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
local selecting = false
local PROXIES = {BP_WindJumpSmall_C=true, BP_WindJumpMedium_C=true, BP_WindJumpLarge_C=true}
local function IsProxy(actor)
    local ok, name = pcall(function() return Name(actor:GetClass():GetFName()) end)
    return ok and PROXIES[name] == true
end
local function SelectJumpSpot(context, _, other)
    if selecting then return end
    local changed = Value(context)
    local player = Value(other)
    if not Valid(changed) or not Valid(player) then return end
    local owned = IsProxy(changed)
    -- Preserve vanilla behavior for AI and remote characters on map spots.
    local isCharacter, localPlayer = pcall(function()
        return player:IsPlayerControlled() and player:IsLocallyControlled()
    end)
    if not isCharacter then return end
    if not localPlayer and not owned then return end
    local ok, err = pcall(function()
        local overlapping = {}
        player:GetOverlappingActors(overlapping, nil)
        local selected, height, original = nil, 0, nil
        local jumpSpotType = StaticFindObject("/Script/Pal.PalLevelGimmickJumpSpot")
        for _, wrapped in pairs(overlapping) do
            local spot = Value(wrapped)
            if Valid(spot) and not spot:IsActorBeingDestroyed() and spot:IsOverlappingActor(player) then
                if IsProxy(spot) then
                    local wind = spot:GetParentActor()
                    if localPlayer and Valid(wind) and not wind:IsActorBeingDestroyed() and wind:IsAvailable() then
                        local candidate = HEIGHTS[Name(wind.BuildObjectId)]
                        if candidate and candidate > height then selected, height = spot, candidate end
                    end
                elseif Valid(jumpSpotType) and spot:IsA(jumpSpotType) then
                    -- Do not replace a map spot's own height, direction or animations.
                    original = spot
                end
            end
        end
        if not owned and height == 0 then return end
        selected = original or selected
        if selected and not original then
            local movement = player.CharacterMovement
            local gravity = Valid(movement) and math.abs(movement:GetGravityZ()) or 0
            if gravity < 1 then
                selected = nil
            else
                selected.JumpZVelocity = math.sqrt(2 * gravity * height)
                selected.JumpFowardVelocity = 0
                selected.bPlayJumpPrepareMontage = true
            end
        end
        selecting = true
        if selected then
            selected:EventOnActorBeginOverlap(selected, player)
        elseif owned then
            changed:EventOnActorEndOverlap(changed, player)
        end
    end)
    selecting = false
    if not ok and jumpErrors < 3 then
        jumpErrors = jumpErrors + 1
        print("[Updraft Elevator] Jump modifier error: " .. tostring(err) .. "\n")
    end
end
local jumpHookOk, jumpHookError = pcall(function()
    RegisterHook("/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorBeginOverlap", function() end, SelectJumpSpot)
    RegisterHook("/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorEndOverlap", function() end, SelectJumpSpot)
end)
if not jumpHookOk then print("[Updraft Elevator] Jump hooks unavailable: " .. tostring(jumpHookError) .. "\n") end
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
print("[Updraft Elevator] Wind lift v10: original jump-spot action and prepare montage; configurable heights; level 9 ancient technology, cost 1.\n")
