local Util = require("BetterWorkbench.Util")
local Book = require("BetterWorkbench.RecipeBook")
local M = {}

-- Instant reverse of the selected recipe, using its original materials.
-- Does not recurse, apply research discounts, or write to game inventory.
-- batches means whole recipe executions: a recipe producing N items consumes
-- N finished items per reverse batch, avoiding fractional material refunds.
function M.resolve(recipeId, batches, state, options)
    options = options or {}
    local maxCount = Util.integer(options.MaxCount or 1000000000, 1, 1000000000, "MaxCount")
    Util.integer(batches, 1, 256, "disassembly batches")
    assert(type(state) == "table", "disassembly snapshot required")
    assert(type(state.Inventory) == "table", "disassembly inventory required")
    local row = Book.new(state.Recipes, maxCount):get(recipeId)
    assert(row, "unknown recipe: " .. tostring(recipeId))
    local context = state.Context or {}
    local count = Util.integer(state.Inventory[row.OutputItem] or 0, 0, maxCount, "owned count")
    local function multiply(amount)
        assert(amount <= math.floor(maxCount / batches), "disassembly count limit exceeded")
        return amount * batches
    end
    local consume = multiply(row.OutputAmount)
    local returns = {}
    for item, amount in pairs(row.Materials) do returns[item] = multiply(amount) end
    local reason
    if type(context.StationRecipes) ~= "table" then reason = "station_scope_unverified"
    elseif context.StationRecipes[recipeId] ~= true then reason = "cross_station_recipe"
    elseif type(context.canDisassemble) ~= "function" then reason = "disassembly_policy_unverified"
    else
        local allowed, denied = context.canDisassemble(recipeId, Util.copy(row))
        if allowed ~= true then reason = denied or "not_eligible" end
    end
    if not reason and next(returns) == nil then reason = "no_return_materials" end
    if not reason and count < consume then reason = "insufficient_products" end
    return {
        Mode = "Disassemble", RecipeId = recipeId, Batches = batches,
        ProductItem = row.OutputItem, OwnedAmount = count,
        MaxBatches = math.min(256, math.floor(count / row.OutputAmount)),
        Consumed = { [row.OutputItem] = consume }, Returns = returns,
        Materials = Util.rows(returns), WorkAmount = 0,
        CanDisassemble = reason == nil, Reason = reason,
    }
end

return M
