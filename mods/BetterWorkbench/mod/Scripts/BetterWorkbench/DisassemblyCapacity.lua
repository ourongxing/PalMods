local Util = require("BetterWorkbench.Util")
local M = {}
-- Reserve capacity for every return together, before any inventory mutation.
-- Existing product slots are not counted as free: the native reference path
-- adds materials before reducing products, so it needs capacity at that point.
function M.check(slots, returns, targets, limits)
    local virtual = {}
    for index, slot in ipairs(slots) do
        virtual[index] = { Container = slot.Container, Item = slot.Item, Count = slot.Count }
    end
    for _, item in ipairs(Util.keys(returns)) do
        local remaining = Util.integer(returns[item], 1, 1000000000, "return quantity")
        local limit = Util.integer(limits[item], 1, 1000000000, "stack limit")
        assert(targets[item], "return container unavailable")
        for _, slot in ipairs(virtual) do
            if slot.Container == targets[item] and slot.Item == item and slot.Count > 0 then
                local add = math.min(remaining, math.max(0, limit - slot.Count))
                slot.Count, remaining = slot.Count + add, remaining - add
            end
        end
        for _, slot in ipairs(virtual) do
            if remaining > 0 and slot.Container == targets[item] and slot.Count == 0 then
                slot.Item, slot.Count = item, math.min(remaining, limit)
                remaining = remaining - slot.Count
            end
        end
        if remaining > 0 then return false, "backpack_full" end
    end
    return true
end
return M
