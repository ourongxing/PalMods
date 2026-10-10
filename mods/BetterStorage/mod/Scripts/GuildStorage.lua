-- Upgrade shared inventory when a guild chest is constructed or enters play.
-- No world polling: retries belong only to this chest and expire.
local M = {}
local function valid(value) return value and value:IsValid() end
local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end
    return value
end
local function guid(value)
    value = unwrap(value)
    return {A=unwrap(value.A), B=unwrap(value.B), C=unwrap(value.C), D=unwrap(value.D)}
end
local function sameGuid(a, b)
    a, b = guid(a), guid(b)
    return a.A == b.A and a.B == b.B and a.C == b.C and a.D == b.D
end
function M.start(bridge, slots)
    assert(type(slots) == 'number' and slots % 1 == 0 and slots >= 54 and slots <= 4096)
    local pending, lastError = {}, nil
    local function migrate(manager, chest)
        if not valid(manager) or not valid(chest) then return true end
        local world = FindFirstOf('PalGameState')
        local utility = StaticFindObject('/Script/Pal.Default__PalUtility')
        if not valid(world) or not valid(utility) then return false, 'world not ready' end
        if not utility:IsServer(world) then return true end
        local output = {}
        if not manager:TryGetModel(guid(chest:GetBaseCampIdBelongTo()), output)
            or not valid(output.OutModel) then return false, 'owning base not ready' end
        local groupId = guid(output.OutModel:GetGroupIdBelongTo())
        if groupId.A == 0 and groupId.B == 0
            and groupId.C == 0 and groupId.D == 0 then return false, 'base guild not ready' end
        -- Resolve only the owner of this newly registered chest. Guild objects
        -- are enumerated for this lifecycle event, never on a repeating timer.
        for _, guild in ipairs(FindAllOf('PalGroupGuild') or {}) do
            if valid(guild) and sameGuid(guild:GetId(), groupId) then
                local count, err = bridge.growGuildStorage(world:GetAddress(), guild:GetAddress(), slots)
                if count then
                    print('[BetterStorage] guild chest migration completed: capacity=' .. tostring(count)
                        .. ', configured=' .. tostring(slots) .. '\n')
                    return true
                end
                error(err)
            end
        end
        return false, 'owning guild not ready'
    end
    local function enqueue(key, resolve)
        if pending[key] then return end
        pending[key] = true
        local attempts = 0
        local attempt
        attempt = function()
            ExecuteInGameThread(function()
                attempts = attempts + 1
                local ok, done, reason = pcall(function()
                    local manager, chest, finished = resolve()
                    if finished then return true end
                    if not valid(manager) or not valid(chest) then return false, 'chest model or manager not ready' end
                    return migrate(manager, chest)
                end)
                if not ok and done ~= lastError then
                    lastError = done
                    print('[BetterStorage] guild chest migration: ' .. tostring(done) .. '\n')
                end
                if (ok and done) or attempts >= 6 then
                    pending[key] = nil
                    if not (ok and done) then
                        print('[BetterStorage] guild chest migration expired after 6 attempts: '
                            .. tostring(ok and reason or done) .. '\n')
                    end
                else
                    ExecuteWithDelay(1000, attempt)
                end
            end)
        end
        attempt()
    end
    RegisterHook('/Script/Pal.PalBaseCampManager:OnCreateMapObjectModelInServer', function() end,
        function(context, createdModel)
            local chest, manager = unwrap(createdModel), unwrap(context)
            if not valid(chest) or not chest:IsA('/Script/Pal.PalMapObjectGuildChestModel') then return end
            print('[BetterStorage] guild chest construction observed\n')
            enqueue(chest:GetAddress(), function()
                return manager, chest, not valid(manager) or not valid(chest)
            end)
        end)
    -- AActor::BeginPlay is a native lifecycle hook, independent of whether the
    -- game's construction callback passes through a reflected UFunction thunk.
    RegisterBeginPlayPostHook(function(context)
        local actor = unwrap(context)
        if not valid(actor) or not actor:IsA('/Game/Pal/Blueprint/MapObject/BuildObject/BP_BuildObject_GuildChest.BP_BuildObject_GuildChest_C') then return end
        print('[BetterStorage] guild chest actor began play\n')
        enqueue(actor:GetAddress(), function()
            if not valid(actor) then return nil, nil, true end
            local world = FindFirstOf('PalGameState')
            local utility = StaticFindObject('/Script/Pal.Default__PalUtility')
            if not valid(world) or not valid(utility) then return end
            if not utility:IsServer(world) then return nil, nil, true end
            local chest = actor:GetModel()
            if not valid(chest) then return end
            if not chest:IsA('/Script/Pal.PalMapObjectGuildChestModel') then return nil, nil, true end
            return utility:GetBaseCampManager(world), chest
        end)
    end)
    print('[BetterStorage] guild chest migration ready: configured=' .. tostring(slots)
        .. ' (construction and actor BeginPlay, grow only, no polling)\n')
end
return M
