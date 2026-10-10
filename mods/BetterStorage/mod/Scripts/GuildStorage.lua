-- Upgrade an existing shared inventory when a guild chest is registered.
-- No world polling: retries belong only to the new chest and expire.
local M = {}
local function valid(value) return value and value:IsValid() end
local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end
    return value
end
local function sameGuid(a, b)
    return unwrap(a.A) == unwrap(b.A) and unwrap(a.B) == unwrap(b.B)
        and unwrap(a.C) == unwrap(b.C) and unwrap(a.D) == unwrap(b.D)
end
function M.start(bridge)
    local pending, lastError = {}, nil
    local function migrate(manager, chest)
        if not valid(manager) or not valid(chest) then return true end
        local world = FindFirstOf('PalGameState')
        local utility = StaticFindObject('/Script/Pal.Default__PalUtility')
        if not valid(world) or not valid(utility) then return false end
        if not utility:IsServer(world) then return true end
        local setting = utility:GetGameSetting(world)
        if not valid(setting) then return false end
        local slots = setting.GuildChestSlotNum
        if type(slots) ~= 'number' or slots % 1 ~= 0 or slots < 54 or slots > 4096 then
            error('invalid GuildChestSlotNum in game setting')
        end
        local output = {}
        if not manager:TryGetModel(chest:GetBaseCampIdBelongTo(), output)
            or not valid(output.OutModel) then return false end
        local groupId = output.OutModel:GetGroupIdBelongTo()
        if unwrap(groupId.A) == 0 and unwrap(groupId.B) == 0
            and unwrap(groupId.C) == 0 and unwrap(groupId.D) == 0 then return false end
        -- Resolve only the owner of this newly registered chest. Guild objects
        -- are enumerated at construction time, never on a repeating timer.
        for _, guild in ipairs(FindAllOf('PalGroupGuild') or {}) do
            if valid(guild) and sameGuid(guild:GetId(), groupId) then
                local count, err = bridge.growGuildStorage(world:GetAddress(), guild:GetAddress(), slots)
                if count then return true end
                error(err)
            end
        end
        return false
    end
    RegisterHook('/Script/Pal.PalBaseCampManager:OnCreateMapObjectModelInServer', function() end,
        function(context, createdModel)
            local chest, manager = unwrap(createdModel), unwrap(context)
            if not valid(chest) or not chest:IsA('/Script/Pal.PalMapObjectGuildChestModel') then return end
            local key = chest:GetAddress()
            if pending[key] then return end
            pending[key] = true
            local attempts = 0
            local attempt
            attempt = function()
                ExecuteInGameThread(function()
                    attempts = attempts + 1
                    local ok, done = pcall(migrate, manager, chest)
                    if not ok and done ~= lastError then
                        lastError = done
                        print('[BetterStorage] guild chest migration: ' .. tostring(done) .. '\n')
                    end
                    if (ok and done) or attempts >= 6 then
                        pending[key] = nil
                    else
                        ExecuteWithDelay(1000, attempt)
                    end
                end)
            end
            attempt()
        end)
    print('[BetterStorage] guild chest construction migration ready (grow only, no polling)\n')
end
return M
