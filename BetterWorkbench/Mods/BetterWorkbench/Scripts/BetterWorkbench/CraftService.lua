local Resolver = require("BetterWorkbench.RecipeResolver")
local Disassembly = require("BetterWorkbench.DisassemblyPlan")
local Service = {}
Service.__index = Service

function Service.new(backend, options)
    assert(type(backend) == "table", "backend is required")
    return setmetatable({ backend = backend, options = options }, Service)
end

function Service:plan(recipeId, batches, state)
    local resolver = Resolver.new(state.Recipes, self.options)
    return resolver:resolve(recipeId, batches, state.Inventory, state.Context)
end

function Service:preview(context, recipeId, batches)
    -- A fresh snapshot per UI refresh: player/base/station scope lives in backend.
    return self:plan(recipeId, batches, self.backend:snapshot(context))
end

function Service:commit(context, recipeId, batches)
    -- Do not accept a client-supplied Materials list or trust an earlier preview.
    -- backend:transaction must lock inventory, run this callback once on fresh
    -- authoritative data, then use native validation/debit/job creation.
    -- Never implement this contract with separate Lua debit/enqueue calls.
    return self.backend:transaction(context, function(state)
        local plan = self:plan(recipeId, batches, state)
        if not plan.Craftable then return nil, "materials_or_policy_changed", plan end
        return plan
    end)
end

function Service:cancel(context, jobId)
    assert(type(jobId) == "string" and jobId ~= "", "invalid job ID")
    -- Prefer the game's own cancellation and refund behavior. The backend must
    -- authenticate ownership and verify native refund data contains the actual
    -- expanded inputs before permitting a BetterWorkbench job. Never fall back to
    -- Lua item credits, current recipes, or CancellationPlan arithmetic here.
    -- cancelNative is our backend interface, not a claimed Palworld UFunction.
    assert(type(self.backend.cancelNative) == "function", "native cancellation backend unavailable")
    return self.backend:cancelNative(context, jobId)
end

function Service:previewDisassembly(context, recipeId, batches, snapshot)
    -- Inventory here must come from the same authorized source scope used by
    -- disassemblyTransaction, not the crafting snapshot's combined stock.
    if type(self.backend.disassemblySnapshot) ~= "function" then
        return nil, "native_disassembly_unavailable"
    end
    -- A caller may reuse this snapshot within one synchronous UI refresh only.
    -- disassemble always obtains fresh authoritative state in its transaction.
    snapshot = snapshot or self.backend:disassemblySnapshot(context)
    return Disassembly.resolve(recipeId, batches, snapshot, self.options), nil, snapshot
end

function Service:disassemble(context, recipeId, batches)
    if type(self.backend.disassemblyTransaction) ~= "function" then
        return nil, "native_disassembly_unavailable"
    end
    -- Adapter contract: authenticate the requesting player/workbench; execute
    -- this callback exactly once with fresh original recipes and authorized
    -- inventory; validate eligibility and backpack capacity. The runtime follows
    -- the working reference mod's native add / slot debit sequence, verifies
    -- actual counts, and disables itself on write errors. This is not a native
    -- atomic transaction or a claimed Palworld UFunction. No craft job is queued.
    return self.backend:disassemblyTransaction(context, function(state)
        local plan = Disassembly.resolve(recipeId, batches, state, self.options)
        if not plan.CanDisassemble then return nil, plan.Reason, plan end
        return plan
    end)
end

return Service
