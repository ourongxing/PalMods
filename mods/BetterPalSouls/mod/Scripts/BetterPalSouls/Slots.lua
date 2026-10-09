local Plan = require("BetterPalSouls.Plan")
local M = {}

-- Keep each existing tier in its slot, then use empty/released backpack slots.
-- Base slots are never retyped, and non-soul items are never displaced.
function M.allocate(slots, counts, limits)
    local remaining, changes, free = Plan.copy(counts), {}, {}
    local assigned = {}
    for i, slot in ipairs(slots) do
        if Plan.weight[slot.Item] and slot.Count > 0 then
            local keep = math.min(slot.Count, remaining[slot.Item])
            remaining[slot.Item] = remaining[slot.Item] - keep
            assigned[i] = { Item = slot.Item, Count = keep }
            if keep == 0 and slot.Backpack then free[#free + 1] = i end
        elseif slot.Count == 0 and slot.Backpack then
            free[#free + 1] = i
            assigned[i] = { Item = slot.Item, Count = 0 }
        end
    end
    -- Existing stacks can accept additional souls without spending an empty slot.
    for i, slot in ipairs(slots) do
        local target = assigned[i]
        if target and target.Count > 0 then
            local add = math.min(remaining[target.Item], math.max(0, limits[target.Item] - target.Count))
            target.Count = target.Count + add
            remaining[target.Item] = remaining[target.Item] - add
        end
    end
    local nextFree = 1
    for _, id in ipairs(Plan.items) do
        local limit = Plan.integer(assert(limits[id]), 1, 1000000000)
        while remaining[id] > 0 do
            local i = free[nextFree]
            if not i then return nil, "backpack_full" end
            local count = math.min(limit, remaining[id])
            assigned[i] = { Item = id, Count = count }
            remaining[id], nextFree = remaining[id] - count, nextFree + 1
        end
    end
    for i, target in pairs(assigned) do
        local slot = slots[i]
        if target.Count ~= slot.Count or target.Item ~= slot.Item then
            changes[#changes + 1] = { Index = i, BeforeItem = slot.Item, BeforeCount = slot.Count,
                Item = target.Item, Count = target.Count }
        end
    end
    table.sort(changes, function(a, b) return a.Index < b.Index end)
    return changes
end
return M
