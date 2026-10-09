-- All amounts are integers. One small soul is the conserved unit of value.
local M = {}
M.items = { "PalUpgradeStone", "PalUpgradeStone2", "PalUpgradeStone3", "PalUpgradeStone4" }
M.weights = { 1, 2, 4, 8 }
M.weight = {}
for i, id in ipairs(M.items) do M.weight[id] = M.weights[i] end

function M.integer(n, lo, hi)
    assert(type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi, "invalid_integer")
    return n
end
function M.copy(counts)
    local out = {}
    for _, id in ipairs(M.items) do out[id] = M.integer(counts[id] or 0, 0, 1000000000) end
    return out
end
function M.value(counts)
    local n = 0
    for _, id in ipairs(M.items) do n = n + M.integer(counts[id] or 0, 0, 1000000000) * M.weight[id] end
    return n
end
function M.cost(current, targets, schedule)
    local required, changed = M.copy({}), false
    assert(#schedule > 0 and #schedule <= 255, "invalid_schedule")
    for stat = 1, 4 do
        local from = M.integer(assert(current[stat]), 0, #schedule)
        local to = M.integer(targets[stat] or from, from, #schedule)
        changed = changed or to > from
        for rank = from + 1, to do
            local row = assert(schedule[rank], "missing_rank_cost")
            assert(M.weight[row.Item], "unsupported_upgrade_item")
            required[row.Item] = required[row.Item] + M.integer(row.Count, 0, 1000000000)
        end
    end
    return required, changed
end

-- Preserve exact-tier stock first; convert only the deficit, returning change.
-- Prepared is the inventory BEFORE vanilla deducts Required. Remaining is after.
function M.prepare(stock, required)
    stock, required = M.copy(stock), M.copy(required)
    if M.value(stock) < M.value(required) then return nil, "insufficient_souls" end
    local remaining, deficit = {}, 0
    for _, id in ipairs(M.items) do
        remaining[id] = math.max(stock[id] - required[id], 0)
        deficit = deficit + math.max(required[id] - stock[id], 0) * M.weight[id]
    end
    local change = 0
    for _, id in ipairs(M.items) do
        if deficit > 0 then
            local take = math.min(remaining[id], math.ceil(deficit / M.weight[id]))
            remaining[id] = remaining[id] - take
            deficit = deficit - take * M.weight[id]
            if deficit < 0 then change, deficit = -deficit, 0 end
        end
    end
    assert(deficit == 0, "conversion_invariant")
    for i = #M.items, 1, -1 do
        local id, weight = M.items[i], M.weights[i]
        local count = math.floor(change / weight)
        remaining[id], change = remaining[id] + count, change % weight
    end
    local prepared = {}
    for _, id in ipairs(M.items) do prepared[id] = remaining[id] + required[id] end
    assert(M.value(prepared) == M.value(stock), "conversion_created_value")
    return { Prepared = prepared, Remaining = remaining, Required = required,
        Cost = M.value(required), Stock = stock }
end

-- Other selected rows reserve their budget; increasing this row cannot steal it.
function M.maximum(stock, current, targets, schedule, stat)
    local trial = {}
    for i = 1, 4 do trial[i] = targets[i] or current[i] end
    trial[stat] = current[stat]
    local required = M.cost(current, trial, schedule)
    local budget, used = M.value(stock), M.value(required)
    if used > budget then return current[stat] end
    local maximum = current[stat]
    for rank = current[stat] + 1, #schedule do
        local row = schedule[rank]
        used = used + row.Count * assert(M.weight[row.Item], "unsupported_upgrade_item")
        if used > budget then break end
        maximum = rank
    end
    return maximum
end
return M
