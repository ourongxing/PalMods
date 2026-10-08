local Util = require("BetterWorkbench.Util")
local Inventory = require("BetterWorkbench.VirtualInventory")
local Book = require("BetterWorkbench.RecipeBook")
local Resolver = {}
Resolver.__index = Resolver

function Resolver.new(recipes, options)
    options = options or {}
    local maxCount = options.MaxCount or 1000000000
    Util.integer(maxCount, 1, 1000000000, "MaxCount")
    local self = setmetatable({
        maxCount = maxCount,
        maxDepth = Util.integer(options.MaxDepth or 32, 1, 256, "MaxDepth"),
        maxNodes = Util.integer(options.MaxNodes or 10000, 1, 1000000, "MaxNodes"),
        book = Book.new(recipes, maxCount, options.PreferredRecipes),
    }, Resolver)
    return self
end

-- batches is native recipe executions, NOT requested output item count.
-- Eligibility is supplied by the server adapter; core never assumes unlocks,
-- station availability, or permission to fabricate an intermediate.
function Resolver:resolve(recipeId, batches, snapshot, context)
    return self:_resolve(recipeId, batches, Inventory.new(snapshot, self.maxCount), context)
end

-- Internal owned inventory permits a batch schedule to share virtual surplus.
-- It is never a game inventory or a native pointer.
function Resolver:_resolve(recipeId, batches, inv, context)
    Util.integer(batches, 1, self.maxCount, "batches")
    context = context or {}
    assert(type(context.canCraft) == "function", "canCraft policy is required")
    local root = self.book:get(recipeId)
    assert(root, "unknown recipe: " .. tostring(recipeId))
    local consumedBefore = Util.copy(inv.consumed)
    local requirements, missing, issues, steps = {}, {}, {}, {}
    local active, nodes, work = {}, 0, 0

    local function add(map, item, amount)
        map[item] = Util.integer((map[item] or 0) + amount, 0, self.maxCount, "total demand")
    end
    local function product(a, b)
        -- Check BEFORE multiplication: compatible with integer Lua 5.4 too.
        assert(a <= math.floor(self.maxCount / b), "count limit exceeded")
        return a * b
    end
    local function issue(item, amount, reason)
        add(requirements, item, amount)
        add(missing, item, amount)
        issues[#issues + 1] = { Item = item, Amount = amount, Reason = reason }
    end
    local function permitted(id, row, isRoot)
        local allowed, reason = context.canCraft(id, Util.copy(row), isRoot)
        if allowed ~= true then return false, reason or "not_eligible" end
        -- Exact recipe IDs from THIS workbench, not a union of base facilities.
        -- No verified scope means no expansion, even when raw stock is enough.
        if type(context.StationRecipes) ~= "table" then return false, "station_scope_unverified" end
        if context.StationRecipes[id] ~= true then return false, "cross_station_recipe" end
        return true
    end
    local demand
    -- Provider returns TOTAL costs for this exact execution count, after native
    -- research modifiers and rounding. Never infer batch costs from a UI sample.
    local function costsFor(id, row, count, isRoot)
        if type(context.materialsForBatches) ~= "function" then
            if context.RequireEffectiveCosts then return nil, "effective_costs_unverified" end
            local costs = {}
            for item, amount in pairs(row.Materials) do costs[item] = product(amount, count) end
            return costs -- offline / already-effective linear recipe fixtures only
        end
        local source, reason = context.materialsForBatches(id, Util.copy(row), count, isRoot)
        if source == nil then return nil, reason or "effective_costs_unverified" end
        assert(type(source) == "table", "invalid effective materials")
        local costs = {}
        for item, amount in pairs(source) do
            -- Modifiers change quantities, not the recipe's material identities.
            assert(type(item) == "string" and row.Materials[item] ~= nil, "unexpected effective material")
            Util.integer(amount, 0, self.maxCount, "effective material amount")
            if amount > 0 then costs[item] = amount end
        end
        -- Explicit zeros are required: absent entries are an incomplete snapshot.
        for item in pairs(row.Materials) do
            assert(source[item] ~= nil, "incomplete effective materials")
        end
        return costs
    end
    local function expand(id, row, count, depth, costs)
        active[row.OutputItem] = true
        for _, item in ipairs(Util.keys(costs)) do
            demand(item, costs[item], depth + 1)
        end
        active[row.OutputItem] = nil
        work = work + row.WorkAmount * count
        assert(work < math.huge, "work limit exceeded")
        steps[#steps + 1] = { RecipeId = id, Batches = count, WorkAmount = row.WorkAmount * count }
    end
    demand = function(item, amount, depth)
        nodes = nodes + 1
        assert(nodes <= self.maxNodes, "node limit exceeded")
        local before = inv.consumed[item] or 0
        local remaining = inv:take(item, amount)
        add(requirements, item, (inv.consumed[item] or 0) - before)
        if remaining == 0 then return end
        if depth > self.maxDepth then issue(item, remaining, "depth_limit"); return end
        if active[item] then issue(item, remaining, "cycle"); return end
        local id, row, reason = self.book:forOutput(item, context.StationRecipes)
        if not row then issue(item, remaining, reason); return end
        if row.Expand == false or next(row.Materials) == nil then
            issue(item, remaining, "expansion_disabled"); return
        end
        local allowed, why = permitted(id, row, false)
        if not allowed then issue(item, remaining, why); return end
        local count = math.floor((remaining - 1) / row.OutputAmount) + 1
        local produced = product(row.OutputAmount, count)
        local costs, costReason = costsFor(id, row, count, false)
        if not costs then issue(item, remaining, costReason); return end
        expand(id, row, count, depth, costs)
        inv:addVirtual(item, produced - remaining, self.maxCount)
    end

    local allowed, why = permitted(recipeId, root, true)
    if not allowed then
        return { Craftable = false, RecipeId = recipeId, Batches = batches,
            Issues = { { Reason = why } }, Materials = {}, Consumed = {}, Missing = {} }
    end
    local costs, costReason = costsFor(recipeId, root, batches, true)
    if not costs then
        return { Craftable = false, RecipeId = recipeId, Batches = batches,
            Issues = { { Reason = costReason } }, Materials = {}, Consumed = {}, Missing = {} }
    end
    local output = product(root.OutputAmount, batches)
    expand(recipeId, root, batches, 0, costs)
    local consumed = {}
    for item, total in pairs(inv.consumed) do
        local amount = total - (consumedBefore[item] or 0)
        if amount > 0 then consumed[item] = amount end
    end
    return {
        Craftable = #issues == 0,
        RecipeId = recipeId, Batches = batches,
        OutputItem = root.OutputItem, OutputAmount = output,
        Materials = Util.rows(requirements), Consumed = consumed,
        Missing = Util.copy(missing), Issues = issues, Steps = steps,
        WorkAmount = work, VirtualSurplus = Util.copy(inv.generated),
    }
end

return Resolver
