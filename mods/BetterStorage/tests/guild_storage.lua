local module = assert(loadfile(SCRIPTS .. '/GuildStorage.lua'))()
local function object(value)
    value.IsValid = function() return true end
    value.GetAddress = function() return value.address end
    return value
end
local realLoadfile = loadfile
local server, configured, loops, work, calls, capacity, setting
local world = object({address=10})
local guild = object({address=20})
local utility = object({
    IsServer=function(_, context) assert(context == world); return server end,
    GetGameSetting=function(_, context) assert(context == world); return setting end,
})
FindFirstOf = function(name) assert(name == 'PalGameState'); return world end
StaticFindObject = function() return utility end
FindAllOf = function(name) assert(name == 'PalGroupGuild'); return {guild} end
ExecuteInGameThread = function(callback) work[#work+1] = callback end
LoopAsync = function(delay, callback) assert(delay == 5000); loops[#loops+1] = callback end
loadfile = function(path)
    assert(path == SCRIPTS .. '/config.lua')
    return function() return {GuildChestSlots=configured} end
end
local bridge = {growGuildStorage=function(w, g, slots)
    assert(w == 10 and g == 20 and server)
    calls = calls + 1
    capacity = math.max(capacity, slots)
    return capacity
end}
local function start(value, authority, existing)
    configured, server, capacity = value, authority, existing or 54
    loops, work, calls, setting = {}, {}, 0, object({})
    module.start(bridge, SCRIPTS)
end
local function flush()
    local pending=work; work={}
    for _, callback in ipairs(pending) do callback() end
end
start(180, true)
assert(calls == 0) -- Mutation is deferred to the game thread.
flush(); assert(capacity == 180 and setting.GuildChestSlotNum == 180 and calls == 1)
loops[1](); loops[1](); assert(#work == 1) -- No growing task backlog.
flush(); assert(calls == 2 and capacity == 180)
start(540, true); flush(); assert(capacity == 540)
start(54, true, 180); flush(); assert(capacity == 180 and setting.GuildChestSlotNum == 54)
start(360, false); flush(); assert(calls == 0 and setting.GuildChestSlotNum == nil)
for _, value in ipairs({0, 53, 4097, 180.5, '360', math.huge, 0/0}) do
    start(value, true); flush(); assert(capacity == 180)
end
-- Missing or malformed files also retain the documented default.
loadfile = function() error('missing config') end
module.start(bridge, SCRIPTS); flush(); assert(setting.GuildChestSlotNum == 180)
loadfile = realLoadfile
print('PASS: guild capacity default/config validation, authority, scheduling and grow-only policy')
