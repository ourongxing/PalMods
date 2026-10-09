local Plan = require("BetterPalSouls.Plan")
local Slots = require("BetterPalSouls.Slots")
local M = {}
M.__index = M
function M.new(backend) return setmetatable({ backend = backend }, M) end
function M:preview(session, targets)
    local state = self.backend:read(session)
    local required, changed = Plan.cost(state.Current, targets, state.Schedule)
    local plan, reason = Plan.prepare(state.Stock, required)
    if not plan then return nil, reason end
    local writes, problem = Slots.allocate(state.Slots, plan.Prepared, state.Limits)
    if not writes then return nil, problem end
    plan.Changes, plan.Changed = writes, changed
    return plan, state
end
function M:submit(session, targets, expectedHandle, expectedCurrent)
    if self.disabled then return nil, "disabled_after_error" end
    if self.busy then return nil, "busy" end
    self.busy = true
    local state, attempted, success
    local ok, plan, reason = pcall(function()
        local result, readState = self:preview(session, targets)
        if not result then return nil, readState end
        state = readState
        assert(state.HandleKey == expectedHandle, "pal_changed")
        for i = 1, 4 do assert(state.Current[i] == expectedCurrent[i], "rank_changed") end
        if not result.Changed then return nil, "no_change" end
        -- The backend performs a last identity/count check before the first write.
        self.backend:check(state)
        self.backend:checkCost(state, targets)
        attempted = true
        self.backend:apply(state, result.Changes)
        self.backend:checkPrepared(state, result.Prepared)
        self.backend:upgrade(state, targets)
        self.backend:verify(state, targets, result.Remaining)
        success = true
        return result
    end)
    if attempted and not success then
        local restored, error = pcall(function() self.backend:restore(state) end)
        self.disabled = true
        if not restored then reason = "rollback_failed: " .. tostring(error) end
    end
    self.busy = false
    if not ok then return nil, reason or tostring(plan) end
    return plan, reason
end
return M
