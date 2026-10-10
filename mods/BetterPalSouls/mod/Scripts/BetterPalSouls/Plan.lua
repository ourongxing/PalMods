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

-- Pool every tier as small souls, then exchange only the native bill's tiers.
-- All unspent value remains small souls; no intermediate tiers are retained.
-- Prepared is the inventory before vanilla deducts the bill; Remaining is after.
function M.prepare(stock, required)
    local total, cost = M.value(stock), M.value(required)
    if total < cost then return nil, "insufficient_souls" end
    local remaining, prepared = M.copy({}), M.copy(required)
    remaining[M.items[1]] = total - cost
    prepared[M.items[1]] = prepared[M.items[1]] + remaining[M.items[1]]
    assert(M.value(prepared) == total, "conversion_created_value")
    return { Prepared = prepared, Remaining = remaining, Cost = cost }
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
