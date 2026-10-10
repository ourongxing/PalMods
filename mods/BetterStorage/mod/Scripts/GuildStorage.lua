local M = {}
function M.start(bridge, scripts)
    local slots = 180
    -- Load this mod's file directly; another mod may also require "config".
    local ok, config = pcall(function() return assert(loadfile(scripts .. "/config.lua"))() end)
    local value = ok and type(config) == "table" and config.GuildChestSlots
    if type(value) == "number" and value == math.floor(value) and value >= 54 and value <= 4096 then
        slots = value
    else
        print("[BetterStorage] invalid GuildChestSlots; using 180\n")
    end
    local queued, lastError = false, nil
    local function reportError(err)
        if err == lastError then return end
        lastError = err
        print("[BetterStorage] guild storage: " .. tostring(err) .. "\n")
    end
    local function valid(object) return object and object:IsValid() end
    local function reconcile()
        local world = FindFirstOf("PalGameState")
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if not valid(world) or not valid(utility) or not utility:IsServer(world) then return end
        local setting = utility:GetGameSetting(world)
        if valid(setting) and setting.GuildChestSlotNum ~= slots then setting.GuildChestSlotNum = slots end
        -- Guild inventories belong to the guild, not to individual chest actors.
        -- Re-resolve each pass to cover save loading, new guilds and world changes.
        for _, guild in ipairs(FindAllOf("PalGroupGuild") or {}) do
            if valid(guild) then
                local count, err = bridge.growGuildStorage(world:GetAddress(), guild:GetAddress(), slots)
                if not count then reportError(err) end
            end
        end
    end
    local function queue()
        if queued then return end
        queued = true
        ExecuteInGameThread(function()
            local success, err = pcall(reconcile)
            queued = false
            if not success then reportError(err) end
        end)
    end
    queue()
    LoopAsync(5000, function() queue(); return false end)
    print("[BetterStorage] guild chest capacity: " .. slots .. " (grow only, server authority)\n")
end
return M
