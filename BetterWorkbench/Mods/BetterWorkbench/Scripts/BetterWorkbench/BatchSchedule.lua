local Util = require("BetterWorkbench.Util")
local Inventory = require("BetterWorkbench.VirtualInventory")
local Schedule = {}

-- Pure preparation for the native adapter. No game mutations or cost formulas.
-- Every root execution asks the existing cost provider for that exact execution;
-- generated intermediates remain virtual, shared between units, never credited.
function Schedule.resolve(resolver, recipeId, batches, snapshot, context, options)
    options = options or {}
    local limit = Util.integer(options.MaxBatches or 256, 1, 4096, "schedule batch limit")
    Util.integer(batches, 1, resolver.maxCount, "batches")
    if batches > limit then
        return { Craftable = false, Issues = { { Reason = "schedule_batch_limit" } } }
    end
    local inventory = Inventory.new(snapshot, resolver.maxCount)
    local units, totals, steps = {}, {}, 0
    local totalOutput, totalWork = 0, 0
    for index = 1, batches do
        local unit = resolver:_resolve(recipeId, 1, inventory, context)
        if not unit.Craftable then
            return { Craftable = false, FailedBatch = index, Issues = Util.copy(unit.Issues) }
        end
        for item, amount in pairs(unit.Consumed) do
            totals[item] = Util.integer((totals[item] or 0) + amount, 0, resolver.maxCount, "schedule input total")
        end
        steps = steps + #unit.Steps
        if steps > resolver.maxNodes then
            return { Craftable = false, Issues = { { Reason = "schedule_step_limit" } } }
        end
        totalOutput = Util.integer(totalOutput + unit.OutputAmount, 1, resolver.maxCount, "schedule output")
        totalWork = totalWork + unit.WorkAmount
        assert(totalWork < math.huge, "schedule work limit exceeded")
        units[index] = { Inputs = unit.Consumed, Steps = unit.Steps,
            VirtualSurplus = unit.VirtualSurplus, WorkAmount = unit.WorkAmount,
            OutputItem = unit.OutputItem, OutputAmount = unit.OutputAmount }
    end
    local order = Util.keys(totals)
    if #order > 5 then
        return { Craftable = false, Issues = { { Reason = "native_input_slot_limit" } } }
    end
    return { Craftable = true, RecipeId = recipeId, Batches = batches,
        Units = units, SlotItems = order, ActualInputs = totals,
        OutputAmount = totalOutput, WorkAmount = totalWork,
        OutputItem = units[1].OutputItem,
        VirtualSurplus = Util.copy(inventory.generated) }
end

-- Reference prefix/suffix accounting for tests and adapter validation only.
-- Actual cancellation must still invoke the native input-slot refund path.
function Schedule.remaining(schedule, completed)
    assert(schedule.Craftable == true, "schedule is not craftable")
    Util.integer(completed, 0, schedule.Batches, "completed batches")
    local remaining = {}
    for index = completed + 1, schedule.Batches do
        for item, amount in pairs(schedule.Units[index].Inputs) do
            remaining[item] = (remaining[item] or 0) + amount
        end
    end
    return remaining
end

return Schedule
