local Util = require("BetterWorkbench.Util")
local Resolver = require("BetterWorkbench.RecipeResolver")
local Schedule = require("BetterWorkbench.BatchSchedule")
local Planner = {}
local focus = { Bio_Battery = true, CarbonFiber = true, CarbonFiber2 = true }

-- This consumes OWNED native data only. A result is a shadow plan, never
-- authorization to mutate a task: unlock/ownership/persistence are separate.
function Planner.check(packet, config)
    assert(type(packet) == "table" and packet.Schema == 1 and packet.ReadOnly == true
        and packet.NativeCosts == true and packet.ScopeComplete == true, "unverified native snapshot")
    assert(focus[packet.RecipeId] == true, "snapshot root outside focused validation")
    Util.integer(packet.Batches, 1, 256, "native request batches")
    assert(type(packet.Recipes) == "table" and type(packet.StationRecipes) == "table"
        and type(packet.Inventory) == "table" and type(packet.BatchDemand) == "table", "incomplete native snapshot")
    local rows, effective = {}, {}
    for id, row in pairs(packet.Recipes) do
        assert(type(row.EffectiveMaterials) == "table", "effective native materials unavailable")
        rows[id] = { OutputItem = row.OutputItem, OutputAmount = row.OutputAmount,
            WorkAmount = row.WorkAmount, Materials = Util.copy(row.Materials) }
        effective[id] = Util.copy(row.EffectiveMaterials)
        for item in pairs(row.Materials) do
            Util.integer(effective[id][item], 0, 1000000000, "native effective cost")
            Util.integer(packet.Inventory[item], 0, 1000000000, "native scope stock")
        end
        for item in pairs(effective[id]) do
            assert(row.Materials[item] ~= nil, "native cost identity differs from raw recipe")
        end
    end
    local root = assert(effective[packet.RecipeId], "root cost unavailable")
    assert(packet.StationRecipes[packet.RecipeId] == true, "root outside current workbench")
    -- This is a consistency check against the game's observed batch multiply,
    -- not a research formula or a source of costs. Reject stale/inconsistent
    -- owner context before doing any planning.
    for item, amount in pairs(root) do
        assert(packet.BatchDemand[item] == amount * packet.Batches, "native batch demand changed")
    end
    for item in pairs(packet.BatchDemand) do assert(root[item] ~= nil, "extra native batch material") end
    local context = { StationRecipes = Util.copy(packet.StationRecipes), RequireEffectiveCosts = true,
        canCraft = function() return true end, -- SHADOW eligibility, explicitly not a commit check
        materialsForBatches = function(id, _, batches)
            local costs = assert(effective[id], "native cost provider unavailable")
            -- Focused recipes produce one item and are resolved one execution
            -- at a time. Do not generalize this to arbitrary batch formulas.
            assert(batches == 1, "focused native provider requires one execution")
            return Util.copy(costs)
        end }
    local options = Util.copy(config or {})
    local function resolve(preference)
        local chosen = Util.copy(options)
        chosen.PreferredRecipes = Util.copy(chosen.PreferredRecipes or {})
        if preference then chosen.PreferredRecipes.CarbonFiber = preference end
        return Schedule.resolve(Resolver.new(rows, chosen), packet.RecipeId, packet.Batches,
            packet.Inventory, context)
    end
    local plan
    if packet.RecipeId == "Bio_Battery" and not (options.PreferredRecipes or {}).CarbonFiber then
        -- A deterministic focused validation policy. Try an entire plan using
        -- coal, then an entire plan using EXISTING charcoal. Never combine
        -- station scopes or fabricate charcoal through the furnace recipe.
        for _, variant in ipairs({ "CarbonFiber", "CarbonFiber2" }) do
            if packet.StationRecipes[variant] == true then
                plan = resolve(variant)
                if plan.Craftable then break end
            end
        end
    end
    plan = plan or resolve()
    plan.ReadOnly = true
    plan.EligibilityVerified = packet.EligibilityVerified == true
    plan.NativeBatchDemand = Util.copy(packet.BatchDemand)
    return plan
end

function Planner.start(config, api)
    api = api or _G
    local state = { stopped = false, packets = 0, errors = 0 }
    function state.drain()
        if state.stopped or type(api.BetterWorkbenchNativeTakeSnapshot) ~= "function" then return end
        -- Native queue holds at most eight independent, owned snapshots.
        for _ = 1, 8 do
            local packet = api.BetterWorkbenchNativeTakeSnapshot()
            if packet == nil then break end
            local ok, plan = pcall(Planner.check, packet, config)
            state.packets = state.packets + 1
            if ok then
                local amounts = {}
                for _, item in ipairs(Util.keys(plan.ActualInputs or {})) do
                    amounts[#amounts + 1] = item .. "=" .. plan.ActualInputs[item]
                end
                state.last = plan
                print("[BetterWorkbench:Plan] recipe=" .. packet.RecipeId .. " batches=" .. packet.Batches
                    .. " craftable=" .. tostring(plan.Craftable) .. " slots=" .. #(plan.SlotItems or {})
                    .. " actual_inputs=" .. table.concat(amounts, ",")
                    .. " eligibility_verified=" .. tostring(plan.EligibilityVerified) .. " read_only=true\n")
                if not plan.Craftable then
                    print("[BetterWorkbench:Plan] reason=" .. tostring((plan.Issues[1] or {}).Reason) .. "\n")
                end
            else
                state.errors = state.errors + 1
                print("[BetterWorkbench:Plan] snapshot rejected: " .. tostring(plan) .. "\n")
            end
        end
    end
    function state.stop() state.stopped = true end
    if type(api.LoopAsync) == "function" and type(api.ExecuteInGameThread) == "function" then
        api.LoopAsync(1000, function()
            if state.stopped then return true end
            api.ExecuteInGameThread(function() if not state.stopped then state.drain() end end)
            return false
        end)
    end
    return state
end

return Planner
