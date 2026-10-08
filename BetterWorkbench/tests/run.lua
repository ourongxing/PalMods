package.path = PROJECT_ROOT .. "/Mods/BetterWorkbench/Scripts/?.lua;"
    .. PROJECT_ROOT .. "/Mods/BetterWorkbench/Scripts/?/init.lua;" .. package.path
local Resolver = require("BetterWorkbench.RecipeResolver")
local Service = require("BetterWorkbench.CraftService")
local Util = require("BetterWorkbench.Util")
local Normalizer = require("BetterWorkbench.RecipeNormalizer")
local fixture = dofile(PROJECT_ROOT .. "/examples/recipes.lua")
local count = 0
-- Synthetic test workbench supports these exact fixture recipe IDs.
local policy = { canCraft = function() return true end, StationRecipes = {
    Gear = true, Ingot = true, Polymer = true, Target = true,
    A = true, B = true, Part = true, OtherIngot = true,
} }
local function equal(actual, expected)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        assert(actual == expected, tostring(actual) .. " != " .. tostring(expected))
        return
    end
    for key, value in pairs(expected) do equal(actual[key], value) end
    for key in pairs(actual) do assert(expected[key] ~= nil, "extra key: " .. tostring(key)) end
end
local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end
local function plan(inventory, batches)
    return Resolver.new(fixture):resolve("Gear", batches or 1, inventory, policy)
end
local function fails(run, fragment)
    local ok, err = pcall(run)
    assert(not ok and tostring(err):find(fragment, 1, true), tostring(err))
end

test("existing intermediates avoid expansion", function()
    local p = plan({ Ingot = 3, Polymer = 2 })
    assert(p.Craftable)
    equal(p.Materials, { { Item = "Ingot", Amount = 3 }, { Item = "Polymer", Amount = 2 } })
    equal(#p.Steps, 1)
    equal(p.WorkAmount, 10)
end)

test("only missing intermediates expand", function()
    local snapshot = { Ingot = 1, Ore = 4, Polymer = 2 }
    local before = Util.copy(snapshot)
    local p = plan(snapshot)
    assert(p.Craftable)
    equal(p.Materials, { { Item = "Ingot", Amount = 1 }, { Item = "Ore", Amount = 4 },
        { Item = "Polymer", Amount = 2 } })
    equal(p.WorkAmount, 14)
    equal(snapshot, before)
end)

test("batch counts include output amount rounding", function()
    local p = plan({ Ore = 12, Oil = 6 }, 2)
    assert(p.Craftable)
    equal(p.OutputAmount, 2)
    equal(p.Consumed.Ore, 12)
    equal(p.Consumed.Oil, 6)
    equal(p.WorkAmount, 40)
end)

test("missing raw materials are displayed", function()
    local p = plan({ Ore = 5, Oil = 3 })
    assert(not p.Craftable)
    equal(p.Missing, { Ore = 1 })
    equal(p.Materials, { { Item = "Oil", Amount = 3 }, { Item = "Ore", Amount = 6 } })
    equal(p.Issues[1].Reason, "no_recipe")
end)

local shared = {
    Target = { OutputItem = "Target", OutputAmount = 1, Materials = { A = 1, B = 1 } },
    A = { OutputItem = "A", OutputAmount = 1, Materials = { Ore = 2 } },
    B = { OutputItem = "B", OutputAmount = 1, Materials = { Ore = 2 } },
}
test("shared raw stock cannot be counted twice", function()
    local p = Resolver.new(shared):resolve("Target", 1, { Ore = 3 }, policy)
    assert(not p.Craftable)
    equal(p.Consumed.Ore, 3)
    equal(p.Missing.Ore, 1)
end)

test("virtual batch surplus is shared across branches", function()
    local recipes = Util.copy(shared)
    recipes.A.Materials = { Part = 1 }
    recipes.B.Materials = { Part = 1 }
    recipes.Part = { OutputItem = "Part", OutputAmount = 2, Materials = { Ore = 3 } }
    local p = Resolver.new(recipes):resolve("Target", 1, { Ore = 3 }, policy)
    assert(p.Craftable)
    equal(p.Consumed.Ore, 3)
    equal(p.VirtualSurplus.Part, 0)
end)

test("surplus is explicit and never added to real inventory", function()
    local snapshot = { Ore = 6, Oil = 3, Polymer = 1 }
    local p = plan(snapshot)
    assert(p.Craftable)
    equal(p.VirtualSurplus.Polymer, 1)
    equal(snapshot.Polymer, 1)
end)

test("root crafting does not substitute finished inventory", function()
    local p = plan({ Gear = 10, Ingot = 3, Polymer = 2 })
    assert(p.Craftable)
    equal(p.Consumed.Gear, nil)
    equal(p.OutputAmount, 1)
end)

test("cycles terminate and available stock can break dependency cycles", function()
    local recipes = {
        A = { OutputItem = "A", OutputAmount = 1, Materials = { B = 1 } },
        B = { OutputItem = "B", OutputAmount = 1, Materials = { A = 1 } },
    }
    local solver = Resolver.new(recipes)
    local p = solver:resolve("A", 1, {}, policy)
    assert(not p.Craftable)
    equal(p.Issues[1].Reason, "cycle")
    assert(solver:resolve("A", 1, { B = 1 }, policy).Craftable)
end)

test("recipe ambiguity needs explicit selection", function()
    local recipes = Util.copy(fixture)
    recipes.OtherIngot = { OutputItem = "Ingot", OutputAmount = 1, Materials = { Stone = 4 } }
    local p = Resolver.new(recipes):resolve("Gear", 1, { Ore = 6, Polymer = 2 }, policy)
    equal(p.Issues[1].Reason, "ambiguous_recipe")
    local selected = Resolver.new(recipes, { PreferredRecipes = { Ingot = "OtherIngot" } })
    assert(selected:resolve("Gear", 1, { Stone = 12, Polymer = 2 }, policy).Craftable)
end)

test("technology and station policy is authoritative", function()
    local denied = { canCraft = function(id) return id ~= "Ingot", "station_unavailable" end,
        StationRecipes = policy.StationRecipes }
    local p = Resolver.new(fixture):resolve("Gear", 1, { Ore = 6, Polymer = 2 }, denied)
    equal(p.Issues[1].Reason, "station_unavailable")
    assert(not p.Craftable)
    local root = { canCraft = function() return false, "locked" end }
    equal(Resolver.new(fixture):resolve("Gear", 1, {}, root).Issues[1].Reason, "locked")
    fails(function() Resolver.new(fixture):resolve("Gear", 1, {}, {}) end, "canCraft")
end)

test("recipe alternatives are filtered by the current station before ambiguity", function()
    local recipes = Util.copy(fixture)
    recipes.OtherIngot = { OutputItem = "Ingot", OutputAmount = 1, Materials = { Stone = 4 } }
    local station = { StationRecipes = { Gear = true, OtherIngot = true },
        canCraft = function() return true end }
    local p = Resolver.new(recipes):resolve("Gear", 1, { Stone = 12, Polymer = 2 }, station)
    assert(p.Craftable)
    equal(p.Consumed.Stone, 12)
    equal(p.Steps[1].RecipeId, "OtherIngot")
    local preferred = Resolver.new(recipes, { PreferredRecipes = { Ingot = "Ingot" } })
    local blocked = preferred:resolve("Gear", 1, { Ore = 6, Polymer = 2 }, station)
    equal(blocked.Issues[1].Reason, "cross_station_recipe")
    equal(blocked.Consumed.Ore, nil)
end)

test("only current workbench recipes expand and existing foreign materials remain usable", function()
    local station = { StationRecipes = { Gear = true, Polymer = true },
        canCraft = function() return true end }
    local solver = Resolver.new(fixture)
    local blocked = solver:resolve("Gear", 1, { Ore = 6, Polymer = 2 }, station)
    assert(not blocked.Craftable)
    equal(blocked.Missing.Ingot, 3)
    equal(blocked.Consumed.Ore, nil)
    equal(blocked.Issues[1].Reason, "cross_station_recipe")
    assert(solver:resolve("Gear", 1, { Ingot = 3, Polymer = 2 }, station).Craftable)
    local partial = solver:resolve("Gear", 1, { Ingot = 1, Ore = 4, Polymer = 2 }, station)
    equal(partial.Missing.Ingot, 2)
    equal(partial.Consumed.Ingot, 1)
    equal(partial.Consumed.Ore, nil)
    equal(solver:resolve("Ingot", 1, { Ore = 2 }, station).Issues[1].Reason, "cross_station_recipe")
    equal(solver:resolve("Gear", 1, {}, { canCraft = function() return true end }).Issues[1].Reason,
        "station_scope_unverified")
end)

test("non-expandable recipes still allow stored material", function()
    local recipes = Util.copy(fixture)
    recipes.Ingot.Expand = false
    local solver = Resolver.new(recipes)
    equal(solver:resolve("Gear", 1, { Polymer = 2 }, policy).Issues[1].Reason, "expansion_disabled")
    assert(solver:resolve("Gear", 1, { Ingot = 3, Polymer = 2 }, policy).Craftable)
end)

test("free intermediate recipes cannot be used to create resources", function()
    local recipes = Util.copy(fixture)
    recipes.Ingot.Materials = {}
    local p = Resolver.new(recipes):resolve("Gear", 1, { Polymer = 2 }, policy)
    assert(not p.Craftable)
    equal(p.Issues[1].Reason, "expansion_disabled")
end)

test("limits and invalid inputs reject unsafe arithmetic", function()
    fails(function() plan({}, 0) end, "batches")
    fails(function() plan({}, 1.5) end, "batches")
    fails(function() plan({ Ore = -1 }) end, "inventory count")
    fails(function() plan({}, 1000000000) end, "count limit")
    fails(function() Resolver.new(fixture, { MaxNodes = 1 }):resolve("Gear", 1, {}, policy) end, "node limit")
    local p = Resolver.new(fixture, { MaxDepth = 1 }):resolve("Gear", 1, {}, policy)
    equal(p.Issues[1].Reason, "depth_limit")
    local bad = Util.copy(fixture)
    bad.Ingot.OutputAmount = 0
    fails(function() Resolver.new(bad) end, "OutputAmount")
end)

test("caller mutation cannot change recipe book", function()
    local recipes = Util.copy(fixture)
    local solver = Resolver.new(recipes)
    recipes.Gear.Materials.Ingot = 999
    local row = solver.book:get("Gear")
    row.Materials.Ingot = 888
    assert(solver:resolve("Gear", 1, { Ingot = 3, Polymer = 2 }, policy).Craftable)
end)

test("observed flat schema converts strictly and merges repeated slots", function()
    local row = { Product_Count = 2 }
    for index = 1, 5 do
        row["Material" .. index .. "_Id"] = "None"
        row["Material" .. index .. "_Count"] = 0
    end
    row.Material1_Id, row.Material1_Count = "Ore", 2
    row.Material2_Id, row.Material2_Count = "Ore", 3
    row.Material3_Count = 7 -- native rows may retain a count in an unused None slot
    local metadata = { OutputItem = "Ingot", WorkAmount = 4 }
    local normalized = Normalizer.fromFlat(row, metadata)
    equal(normalized.Materials, { Ore = 5 })
    equal(normalized.OutputAmount, 2)
    local p = Resolver.new({ Ingot = normalized }):resolve("Ingot", 2, { Ore = 10 }, policy)
    assert(p.Craftable)
    equal(p.OutputAmount, 4)
    row.Material5_Count = nil
    fails(function() Normalizer.fromFlat(row, metadata) end, "flat material amount")
    fails(function() Normalizer.fromFlat(row, { OutputItem = "Ingot" }) end, "WorkAmount")
end)

test("server recomputes after stale preview and commits once", function()
    -- Simulation of the CONTRACT, not a Palworld transaction implementation.
    local backend = { inventory = { Ingot = 3, Polymer = 2 }, jobs = {} }
    function backend:snapshot(_context)
        return { Inventory = Util.copy(self.inventory), Recipes = fixture, Context = policy }
    end
    function backend:transaction(context, build)
        local p, err, rejected = build(self:snapshot(context))
        if not p then return nil, err, rejected end
        for item, amount in pairs(p.Consumed) do
            assert((self.inventory[item] or 0) >= amount)
        end
        for item, amount in pairs(p.Consumed) do self.inventory[item] = (self.inventory[item] or 0) - amount end
        self.jobs[#self.jobs + 1] = p
        return p
    end
    local service = Service.new(backend)
    assert(service:preview({}, "Gear", 1).Craftable)
    backend.inventory.Ingot = 0
    local result, err = service:commit({}, "Gear", 1)
    equal(result, nil)
    equal(err, "materials_or_policy_changed")
    equal(#backend.jobs, 0)
    equal(backend.inventory.Polymer, 2)
    backend.inventory.Ore = 6
    assert(service:commit({}, "Gear", 1).Craftable)
    equal(#backend.jobs, 1)
    equal(backend.inventory.Ore, 0)
    equal(backend.inventory.Polymer, 0)
    equal(service:commit({}, "Gear", 1), nil)
    equal(#backend.jobs, 1)
end)

test("material conservation across 200 seeded inventory scenarios", function()
    math.randomseed(20261006)
    for _ = 1, 200 do
        local snapshot = { Ore = 100, Oil = 100, Ingot = math.random(0, 9), Polymer = math.random(0, 9) }
        local p = plan(snapshot, math.random(1, 5))
        assert(p.Craftable)
        local balance = Util.copy(p.Consumed)
        for _, step in ipairs(p.Steps) do
            local row = fixture[step.RecipeId]
            for item, amount in pairs(row.Materials) do
                balance[item] = (balance[item] or 0) - amount * step.Batches
            end
            balance[row.OutputItem] = (balance[row.OutputItem] or 0) + row.OutputAmount * step.Batches
        end
        for item, amount in pairs(balance) do
            local expected = p.VirtualSurplus[item] or 0
            if item == p.OutputItem then expected = expected + p.OutputAmount end
            equal(amount, expected)
        end
        for item, amount in pairs(p.Consumed) do assert(amount <= (snapshot[item] or 0)) end
    end
end)

test("UE4SS entry loads without registering speculative hooks", function()
    dofile(PROJECT_ROOT .. "/Mods/BetterWorkbench/Scripts/main.lua")
    assert(not require("BetterWorkbench.PalworldAdapter").status().Ready)
end)

test("diagnostic hooks preserve native values and exclude delegates", function()
    local Diagnostics = require("BetterWorkbench.Diagnostics")
    local logs, hooks, posts = {}, {}, {}
    local function prop(name)
        return { GetFName = function() return { ToString = function() return name end } end,
            GetFullName = function() return "NameProperty " .. name end }
    end
    local function func(name, flags)
        return { GetFName = prop(name).GetFName, GetFunctionFlags = function() return flags end,
            ForEachProperty = function(_, each) each(prop("RecipeId")) end }
    end
    local parent = {
        IsValid = function() return true end,
        GetFullName = function() return "Class /Script/Pal.PalTestUIBase" end,
        ForEachProperty = function(_, each) each(prop("SelectedProductNum")) end,
        ForEachFunction = function(_, each) each(func("GetRecipe", 0)) end,
    }
    local class = {
        IsValid = function() return true end,
        GetSuperStruct = function() return parent end,
        ForEachProperty = function(_, each) each(prop("SelectedRecipeId")) end,
        ForEachFunction = function(_, each)
            each(func("SelectRecipe", 0))
            each(func("RequestStart", 0x00100000))
            each(func("Initialize", 0x00010000))
        end,
    }
    local unregistered = 0
    local api = {
        StaticFindObject = function(path)
            if path == "/Script/Pal.PalUIConvertItemModel" then return class end
            if path == "/Script/Pal.PalTestUIBase" then return parent end
        end,
        RegisterHook = function(path, pre, post)
            hooks[path], posts[path] = pre, post
            assert(type(post) == "function"); return 1, 2
        end,
        ExecuteInGameThread = function(fn) fn() end,
        print = function(line) logs[#logs + 1] = line end,
        UnregisterHook = function(_, pre, post) equal(pre, 1); equal(post, 2); unregistered = unregistered + 1 end,
    }
    local state = assert(Diagnostics.start({ MaxHitsPerHook = 2 }, api))
    local path = "/Script/Pal.PalUIConvertItemModel:SelectRecipe"
    assert(hooks[path] and not hooks["/Script/Pal.PalUIConvertItemModel:RequestStart"])
    assert(not hooks["/Script/Pal.PalUIConvertItemModel:Initialize"])
    assert(hooks["/Script/Pal.PalTestUIBase:GetRecipe"], "inherited methods must be discovered")
    local object = { SelectedRecipeId = "Gear", IsValid = function() return true end }
    local context = { get = function() return object end }
    equal(hooks[path](context, "Gear"), nil)
    equal(object.SelectedRecipeId, "Gear")
    equal(hooks[path](context, "Gear"), nil)
    equal(hooks[path](context, "Gear"), nil)
    equal(state.total, 2)
    object.SelectedRecipeId = "ChangedByNativeFunction"
    equal(posts[path](context, "Gear"), nil)
    equal(object.SelectedRecipeId, "ChangedByNativeFunction")
    equal(state.total, 3)
    state.stop()
    equal(unregistered, 2)
    hooks[path](context, "Gear")
    equal(state.total, 3)
end)

test("diagnostics tolerate missing runtime and scheduling failures", function()
    local Diagnostics = require("BetterWorkbench.Diagnostics")
    equal(Diagnostics.start({}, {}), nil)
    equal(Diagnostics.start({ Enabled = false }, {}), nil)
    local state = Diagnostics.start({}, {
        StaticFindObject = function() error("unavailable") end,
        RegisterHook = function() error("must not be called") end,
        ExecuteInGameThread = function() error("not running") end,
        LoopAsync = function() error("not supported") end,
        print = function() end,
    })
    assert(state)
    state.stop()
end)

test("native post return is labelled first and capped callbacks do not access native values", function()
    local posts = {}
    local function prop(label)
        return { GetFName = function() return { ToString = function() return label end } end }
    end
    local fn = { GetFName = prop("BP_FindRow").GetFName, GetFunctionFlags = function() return 0 end,
        ForEachProperty = function(_, each)
            each(prop("RowName")); each(prop("bResult")); each(prop("ReturnValue"))
        end }
    local class = { IsValid = function() return true end, ForEachProperty = function() end,
        ForEachFunction = function(_, each) each(fn) end }
    local pre, messages = nil, {}
    local state = require("BetterWorkbench.Diagnostics").start({ MaxTotalHits = 1, MaterialAudit = {} }, {
        StaticFindObject = function(path)
            if path == "/Script/Pal.PalMasterDataTableAccess_ItemRecipe" then return class end
        end,
        RegisterHook = function(path, before, after) pre = before; posts[path] = after; return 1, 2 end,
        ExecuteInGameThread = function(fn) fn() end, print = function(message) messages[#messages + 1] = message end,
        FindAllOf = function() error("quarantined inventory scan must never run") end,
    })
    local post = posts["/Script/Pal.PalMasterDataTableAccess_ItemRecipe:BP_FindRow"]
    equal(post(nil, 7, "Ingot", true), nil)
    assert(messages[#messages]:find("ReturnValue=7 RowName=Ingot bResult=true", 1, true))
    local unsafe = { get = function() error("capped callbacks must not unwrap values") end }
    equal(post(unsafe, unsafe, unsafe, unsafe), nil)
    equal(pre(unsafe, unsafe, unsafe), nil)
    equal(state.total, 1)
    equal(state.audit, nil)
    local disabled = require("BetterWorkbench.Diagnostics").start({ MaterialAudit = false }, {
        StaticFindObject = function() end, RegisterHook = function() end,
        ExecuteInGameThread = function(fn) fn() end, print = function() end,
    })
    equal(disabled.audit, nil)
end)

local function auditOwner(id)
    return { IsValid = function() return true end, GetAddress = function() return id end,
        GetFullName = function() return "PalItemContainer TestContainer" .. id end }
end
local function auditSlot(id, owner, item, amount)
    return { IsValid = function() return true end, GetAddress = function() return id end,
        GetOuter = function() return owner end, ItemId = { StaticId = item }, StackCount = amount }
end

test("slot audit deduplicates and does not treat missing slots as spent materials", function()
    local Audit = require("BetterWorkbench.MaterialAudit")
    local owner = auditOwner(10)
    local slot = auditSlot(20, owner, "Coal", 10)
    local slots = { slot, slot }
    local audit = Audit.new({ FindAllOf = function() return slots end }, function() end)
    local before = audit:snapshot()
    equal(before.Count, 1)
    equal(slot.StackCount, 10)
    slot.StackCount = 8
    local changed = Audit.diff(before, audit:snapshot())
    equal(changed.Totals.Coal, -2)
    assert(changed.Complete)
    slots = {}
    local missing = Audit.diff(before, audit:snapshot())
    assert(not missing.Complete and missing.UncertainSlots == 1)
    equal(missing.Totals, {})
    slots = { auditSlot(20, auditOwner(11), "Coal", 8) }
    local reused = Audit.diff(before, audit:snapshot())
    assert(not reused.Complete)
    equal(reused.Totals, {})
    slots = { auditSlot(20, owner, "Coal", -1) }
    local failed = audit:snapshot()
    assert(not failed.Complete and failed.Failures == 1)
end)

test("audit records real before and after changes without modifying inventory", function()
    local Audit = require("BetterWorkbench.MaterialAudit")
    local logs = {}
    local owner = auditOwner(10)
    local coal, organ = auditSlot(20, owner, "Coal", 100), auditSlot(21, owner, "FireOrgan", 50)
    local reads = 0
    local audit = Audit.new({ FindAllOf = function()
        reads = reads + 1; return { coal, organ }
    end }, function(line) logs[#logs + 1] = line end)
    local model = { IsValid = function() return true end, GetAddress = function() return 42 end,
        CurrentRecipeId = "None", RequestedProductNum = 0, RemainProductNum = 0 }
    audit:observe("OnFinishWorkInServer", "CALL", model, {})
    equal(reads, 0)
    audit:observe("ChangeRecipe_ServerInternal", "CALL", model, {})
    equal(coal.StackCount, 100)
    -- Simulated native action. The audit never performs these writes.
    coal.StackCount, organ.StackCount = 98, 49
    model.CurrentRecipeId, model.RequestedProductNum, model.RemainProductNum = "CarbonFiber", 1, 1
    audit:observe("ChangeRecipe_ServerInternal", "POST", model, {})
    equal(coal.StackCount, 98)
    assert(table.concat(logs, "\n"):find("NET=Coal=-2,FireOrgan=-1", 1, true))
    for _ = 1, 4 do
        audit:observe("OnFinishWorkInServer", "CALL", model, {})
        audit:observe("OnFinishWorkInServer", "POST", model, {})
    end
    equal(reads, 6) -- two snapshots at create and two completed units only
    audit:observe("Cancel_ServerInternal", "CALL", model, {})
    coal.StackCount, organ.StackCount = 100, 50
    model.CurrentRecipeId, model.RequestedProductNum, model.RemainProductNum = "None", 0, 0
    audit:observe("Cancel_ServerInternal", "POST", model, {})
    assert(table.concat(logs, "\n"):find("NET=Coal=2,FireOrgan=1", 1, true))
    assert(not audit.tracked["42"])
end)

test("UI material arrays are copied and combined without edits", function()
    local entries = { { StaticItemId = "Ore", Num = 2 }, { StaticItemId = "Ore", Num = 3 } }
    local array = { ForEach = function(_, each)
        for index, entry in ipairs(entries) do each(index, { get = function() return entry end }) end
    end }
    local audit = require("BetterWorkbench.MaterialAudit").new({}, function() end)
    audit:observe("Setup", "CALL", nil, { RecipeID = "Ingot", MatInfo = array })
    equal(audit.uiCosts.Ingot, { Ore = 5 })
    equal(entries[1].Num, 2)
    entries[1].Num = 99
    equal(audit.uiCosts.Ingot.Ore, 5)
end)

local function nameArray(ids, capacity)
    local values = {}
    for _, id in ipairs(ids) do
        values[#values + 1] = { type = function() return "FName" end,
            ToString = function() return id end }
    end
    return setmetatable({
        type = function() return "TArray" end,
        GetArrayNum = function() return #values end,
        GetArrayMax = function() return capacity or #values end,
        ForEach = function() error("unsafe native ForEach must not run") end,
    }, { __index = function(_, index)
        assert(type(index) == "number" and index >= 1 and index <= #values, "out of bounds")
        return values[index]
    end, __newindex = function() error("native array must not be modified") end })
end

test("station name arrays are bounded, copied and never enumerated by native ForEach", function()
    local scope = require("BetterWorkbench.StationScope")
    local ids, n = scope.copyNames(nameArray({ "CarbonFiber", "CarbonFiber2", "CarbonFiber" }))
    equal(ids, { CarbonFiber = true, CarbonFiber2 = true })
    equal(n, 3)
    equal(ids.Charcoal, nil)
    equal(scope.copyNames(nameArray({})), {})
    fails(function() scope.copyNames(nameArray({ "A", "B" }), 1) end, "count")
    fails(function() scope.copyNames(nameArray({ "A", "B" }, 1)) end, "capacity")
    fails(function() scope.copyNames(nameArray({ "None" })) end, "recipe ID")
end)

test("station capture runs only for a reflected FName array return", function()
    local function run(innerType)
        local logs, post = {}, nil
        local property = {
            GetFName = function() return { ToString = function() return "ReturnValue" end } end,
            GetFullName = function() return "ArrayProperty GetRecipes:ReturnValue" end,
            GetInner = function() return { GetFullName = function() return innerType .. " element" end } end,
        }
        local fn = { GetFName = function() return { ToString = function() return "GetRecipes" end } end,
            GetFunctionFlags = function() return 0 end,
            ForEachProperty = function(_, each) each(property) end }
        local class = { IsValid = function() return true end, ForEachProperty = function() end,
            ForEachFunction = function(_, each) each(fn) end }
        require("BetterWorkbench.Diagnostics").start({}, {
            StaticFindObject = function(path)
                if path == "/Script/Pal.PalMapObjectConvertItemModel" then return class end
            end,
            RegisterHook = function(_, _, after) post = after; return 1, 2 end,
            ExecuteInGameThread = function(f) f() end,
            print = function(line) logs[#logs + 1] = line end,
        })
        local array = nameArray({ "CarbonFiber2" })
        if innerType ~= "NameProperty" then
            array.GetArrayNum = function() error("unverified return must not be read") end
        end
        equal(post(nil, { get = function() return array end }), nil)
        local text = table.concat(logs)
        return text:find("STATION_RECIPES", 1, true) ~= nil, text
    end
    local captured, lines = run("NameProperty")
    assert(captured and lines:find("ids=CarbonFiber2", 1, true))
    assert(not run("StructProperty"))
end)

local function materialArray(entries)
    return setmetatable({ type = function() return "TArray" end,
        GetArrayNum = function() return #entries end,
        GetArrayMax = function() return #entries end,
        ForEach = function() error("unsafe native ForEach must not run") end,
    }, { __index = function(_, index)
        assert(type(index) == "number" and index >= 1 and index <= #entries)
        return entries[index]
    end, __newindex = function() error("native writes are forbidden") end })
end

local function materialEntry(item, amount, mapped)
    return { type = function() return "UScriptStruct" end,
        GetFullName = function() return "ScriptStruct /Script/Pal.PalStaticItemIdAndNum" end,
        IsMappedToObject = function() return mapped ~= false end,
        IsMappedToProperty = function() return mapped ~= false end,
        GetStructAddress = function() return 100 end,
        GetPropertyAddress = function() return 200 end,
        StaticItemId = { type = function() return "FName" end, ToString = function() return item end },
        Num = amount }
end

test("native UI material copies validate mappings and never retain native structs", function()
    local view = require("BetterWorkbench.NativeMaterialView")
    local entries = { materialEntry("Charcoal", 3), materialEntry("Charcoal", 2),
        materialEntry("FireOrgan", 1), materialEntry("None", 7) }
    local costs = view.copy(materialArray(entries))
    equal(costs, { Charcoal = 5, FireOrgan = 1 })
    entries[1].Num = 99
    equal(costs.Charcoal, 5)
    local unmapped = materialEntry("Coal", 1, false)
    unmapped.StaticItemId, unmapped.Num = nil, nil
    fails(function() view.copy(materialArray({ unmapped })) end, "unmapped")
    fails(function() view.copy(materialArray({ materialEntry("Coal", -1) })) end, "material amount")
    equal(view.copy(materialArray({})), {})
end)

test("material capture requires exact reflected structure and field types", function()
    local messages, callback = {}, nil
    local function property(name, kind)
        return { GetFName = function() return { ToString = function() return name end } end,
            GetFullName = function() return kind .. " " .. name end }
    end
    local struct = { GetFullName = function() return "ScriptStruct /Script/Pal.PalStaticItemIdAndNum" end,
        ForEachProperty = function(_, each)
            each(property("StaticItemId", "NameProperty")); each(property("Num", "IntProperty"))
        end }
    local mat = property("MatInfo", "ArrayProperty")
    mat.GetInner = function()
        return { GetFullName = function() return "StructProperty MatInfo" end,
            GetStruct = function() return struct end }
    end
    local fn = { GetFName = function() return { ToString = function() return "Setup" end } end,
        GetFunctionFlags = function() return 0 end,
        ForEachProperty = function(_, each) each(property("RecipeID", "NameProperty")); each(mat) end }
    local class = { IsValid = function() return true end, ForEachProperty = function() end,
        ForEachFunction = function(_, each) each(fn) end }
    local path = "/Game/Pal/Blueprint/UI/CovertItemMenu/WBP_PalConvertItemMenu_RecipeSlotButton.WBP_PalConvertItemMenu_RecipeSlotButton_C"
    require("BetterWorkbench.Diagnostics").start({}, {
        StaticFindObject = function(p) if p == path then return class end end,
        RegisterHook = function(_, f) callback = f; return 1, 1 end,
        ExecuteInGameThread = function(f) f() end,
        print = function(line) messages[#messages + 1] = line end,
    })
    local recipe = { type = function() return "FName" end, ToString = function() return "CarbonFiber2" end }
    local array = materialArray({ materialEntry("Charcoal", 5), materialEntry("FireOrgan", 1) })
    equal(callback(nil, { get = function() return recipe end }, { get = function() return array end }), nil)
    assert(table.concat(messages):find("UI_MATERIALS recipe=CarbonFiber2 costs=Charcoal=5,FireOrgan=1", 1, true))
end)

local function countClass(utility, returnType)
    local function field(name, kind)
        return { GetFName = function() return { ToString = function() return name end } end,
            GetFullName = function() return kind .. " " .. name end }
    end
    return { GetCDO = function() return utility end, ForEachFunction = function(_, each)
        for _, name in ipairs({ "CountLocalPlayerInventoryItemNum64", "CountLocalPlayerInsideBaseCampItemNum64" }) do
            each({ GetFName = function() return { ToString = function() return name end } end,
                GetFunctionFlags = function() return 0x10002000 end,
                ForEachProperty = function(_, visit)
                    visit(field("WorldContextObject", "ObjectProperty"))
                    visit(field("StaticItemId", "NameProperty"))
                    visit(field("ReturnValue", returnType or "Int64Property"))
                end })
        end
    end }
end

test("local count diagnostics keep scopes separate and re-read live scalar values", function()
    local Counts = require("BetterWorkbench.NativeCounts")
    local player, base, calls = 2, 5, 0
    local context = { IsValid = function() return true end }
    local utility = { IsValid = function() return true end,
        CountLocalPlayerInventoryItemNum64 = function(_, world, name)
            assert(world == context and name == "Wood"); calls = calls + 1; return player
        end,
        CountLocalPlayerInsideBaseCampItemNum64 = function(_, world, name)
            assert(world == context and name == "Wood"); calls = calls + 1; return base
        end }
    local factory = setmetatable({}, { __call = function(_, id) return id end })
    local reader = Counts.new(countClass(utility), factory)
    local first = reader:read(context, { "Wood" })
    equal(first, { PlayerInventory = { Wood = 2 }, InsideBase = { Wood = 5 } })
    player, base = 1, 4
    local second = reader:read(context, { "Wood" })
    equal(second.PlayerInventory.Wood, 1)
    equal(first.PlayerInventory.Wood, 2)
    for _ = 1, 4 do assert(reader:read(context, { "Wood" })) end
    equal(reader:read(context, { "Wood" }), nil)
    equal(calls, 12)
end)

test("unverified count schema and failed native reads never become zero inventory", function()
    local Counts = require("BetterWorkbench.NativeCounts")
    local utility = { IsValid = function() return true end,
        CountLocalPlayerInventoryItemNum64 = function() return 3 end,
        CountLocalPlayerInsideBaseCampItemNum64 = function() error("native query failed") end }
    fails(function() Counts.new(countClass(utility, "FloatProperty"), function(id) return id end) end, "unverified")
    local reader = Counts.new(countClass(utility), function(id) return id end)
    local result, reason = reader:read({ IsValid = function() return true end }, { "Wood" })
    equal(result, nil)
    assert(reason:find("native query failed", 1, true) and reader.disabled and not reader.busy)
    equal(reader:read({}, { "Wood" }), nil)
end)

test("effective batch costs apply separately to root and same-station intermediates", function()
    local recipes = {
        Target = { OutputItem = "Target", OutputAmount = 1, Materials = { Part = 5 } },
        Part = { OutputItem = "Part", OutputAmount = 2, Materials = { Ore = 5 } },
    }
    local calls, costs = {}, { Target = { Part = 7 }, Part = { Ore = 13 } }
    local context = Util.copy(policy)
    context.RequireEffectiveCosts = true
    context.materialsForBatches = function(id, row, batches, root)
        calls[#calls + 1] = { id, batches, root }
        row.Materials = {} -- provider gets a copy
        return costs[id]
    end
    local p = Resolver.new(recipes):resolve("Target", 2, { Part = 1, Ore = 13 }, context)
    assert(p.Craftable)
    equal(calls, { { "Target", 2, true }, { "Part", 3, false } })
    equal(p.Consumed, { Part = 1, Ore = 13 })
    equal(recipes.Target.Materials.Part, 5)
    equal(costs.Part.Ore, 13)
end)

test("missing effective root or intermediate costs fail closed", function()
    local context = Util.copy(policy)
    context.RequireEffectiveCosts = true
    local resolver = Resolver.new(fixture)
    local p = resolver:resolve("Gear", 1, { Ingot = 3, Polymer = 2 }, context)
    assert(not p.Craftable)
    equal(p.Issues[1].Reason, "effective_costs_unverified")
    equal(p.Consumed, {})
    context.materialsForBatches = function(id)
        if id == "Gear" then return { Ingot = 2, Polymer = 1 } end
        return nil, "research_state_unavailable"
    end
    p = resolver:resolve("Gear", 1, { Ore = 100, Polymer = 1 }, context)
    assert(not p.Craftable)
    equal(p.Missing.Ingot, 2)
    equal(p.Issues[1].Reason, "research_state_unavailable")
    equal(p.Consumed.Ore, nil)
end)

test("effective cost provider never runs for other workstations or stored intermediates", function()
    local context, calls = Util.copy(policy), {}
    context.StationRecipes.Ingot = nil
    context.materialsForBatches = function(id)
        calls[#calls + 1] = id
        assert(id == "Gear", "must not query furnace")
        return { Ingot = 2, Polymer = 1 }
    end
    local resolver = Resolver.new(fixture)
    local p = resolver:resolve("Gear", 1, { Ingot = 1, Ore = 100, Polymer = 1 }, context)
    assert(not p.Craftable)
    equal(p.Issues[1].Reason, "cross_station_recipe")
    equal(calls, { "Gear" })
    calls = {}
    assert(resolver:resolve("Gear", 1, { Ingot = 2, Polymer = 1 }, context).Craftable)
    equal(calls, { "Gear" })
end)

test("malformed effective costs cannot become free materials", function()
    local context = Util.copy(policy)
    for _, value in ipairs({ { Ingot = 1 }, { Ingot = 1, Polymer = -1 },
        { Ingot = 1, Polymer = 0.5 }, { Ingot = 1, Polymer = 1, Wood = 1 } }) do
        context.materialsForBatches = function() return value end
        fails(function() Resolver.new(fixture):resolve("Gear", 1, {}, context) end, "effective")
    end
    context.materialsForBatches = function() return { Ingot = 0, Polymer = 0 } end
    local p = Resolver.new(fixture):resolve("Gear", 1, {}, context)
    assert(p.Craftable)
    equal(p.Consumed, {})
end)

test("commit re-queries research batch costs instead of trusting preview", function()
    local amount, queries, enqueued = 2, 0, false
    local recipes = { Target = { OutputItem = "Target", OutputAmount = 1, Materials = { Ore = 3 } } }
    local function snapshot()
        return { Recipes = recipes, Inventory = { Ore = 2 }, Context = {
            canCraft = function() return true end, StationRecipes = { Target = true },
            RequireEffectiveCosts = true,
            materialsForBatches = function(id, _, batches)
                assert(id == "Target" and batches == 1)
                queries = queries + 1
                return { Ore = amount }
            end,
        } }
    end
    local service = Service.new({ snapshot = snapshot, transaction = function(_, _, run)
        local plan, reason = run(snapshot())
        if plan then enqueued = true end
        return plan, reason
    end })
    assert(service:preview({}, "Target", 1).Craftable)
    amount = 3
    local result, reason = service:commit({}, "Target", 1)
    equal(result, nil)
    equal(reason, "materials_or_policy_changed")
    assert(not enqueued and queries == 2)
end)

test("focused material sampling skips unrelated native arrays within a bounded filter", function()
    local callback, messages = nil, {}
    local struct = { GetFullName = function() return "ScriptStruct /Script/Pal.PalStaticItemIdAndNum" end,
        ForEachProperty = function(_, visit)
            for name, kind in pairs({ StaticItemId = "NameProperty", Num = "IntProperty" }) do
                visit({ GetFName = function() return { ToString = function() return name end } end,
                    GetFullName = function() return kind .. " " .. name end })
            end
        end }
    local fn = { GetFName = function() return { ToString = function() return "Setup" end } end,
        GetFunctionFlags = function() return 0 end,
        ForEachProperty = function(_, visit)
            visit({ GetFName = function() return { ToString = function() return "RecipeID" end } end })
            visit({ GetFName = function() return { ToString = function() return "MatInfo" end } end,
                GetFullName = function() return "ArrayProperty MatInfo" end,
                GetInner = function() return { GetFullName = function() return "StructProperty MatInfo" end,
                    GetStruct = function() return struct end } end })
        end }
    local class = { IsValid = function() return true end, ForEachProperty = function() end,
        ForEachFunction = function(_, visit) visit(fn) end }
    local state = require("BetterWorkbench.Diagnostics").start({ FocusRecipes = { Bio_Battery = true }, MaxSetupVisits = 4 }, {
        StaticFindObject = function(path) if path:find("RecipeSlotButton", 1, true) then return class end end,
        RegisterHook = function(_, call) callback = call; return 1, 2 end,
        ExecuteInGameThread = function(f) f() end, print = function(line) messages[#messages + 1] = line end,
    })
    local function name(id) return { type = function() return "FName" end, ToString = function() return id end } end
    local quantityReads = 0
    state.inventory = { read = function(_, _, items)
        equal(items, { "CarbonFiber" })
        quantityReads = quantityReads + 1
        return { PlayerInventory = { CarbonFiber = 2 }, InsideBase = { CarbonFiber = 3 } }
    end }
    local unreadable = { get = function() error("unrelated array must not be read") end }
    callback(nil, name("Arrow"), unreadable)
    callback(nil, name("Bat"), unreadable)
    equal(state.total, 0)
    callback(nil, name("Bio_Battery"), materialArray({ materialEntry("CarbonFiber", 1) }))
    equal(state.total, 1)
    assert(table.concat(messages):find("UI_MATERIALS recipe=Bio_Battery costs=CarbonFiber=1", 1, true))
    callback(nil, name("Bio_Battery"), materialArray({ materialEntry("CarbonFiber", 2) }))
    equal(quantityReads, 1) -- repeated UI costs do not spend event inventory budget
    assert(table.concat(messages):find("UI_MATERIALS recipe=Bio_Battery costs=CarbonFiber=2", 1, true))
    callback(nil, unreadable, unreadable) -- visit cap rejects before parameter reads
    equal(state.total, 2)
end)

test("focused event snapshots call only scalar inventory reader before and after native events", function()
    local before, after, messages, calls = nil, nil, {}, {}
    local fn = { GetFName = function() return { ToString = function() return "Cancel_ServerInternal" end } end,
        GetFunctionFlags = function() return 0 end, ForEachProperty = function() end }
    local class = { IsValid = function() return true end, ForEachProperty = function() end,
        ForEachFunction = function(_, each) each(fn) end }
    local state = require("BetterWorkbench.Diagnostics").start({ FocusItems = { "CarbonFiber", "Bio_Battery" } }, {
        StaticFindObject = function(path) if path == "/Script/Pal.PalMapObjectConvertItemModel" then return class end end,
        RegisterHook = function(_, pre, post) before, after = pre, post; return 1, 2 end,
        ExecuteInGameThread = function(f) f() end, print = function(line) messages[#messages + 1] = line end,
    })
    local context = { IsValid = function() return true end, GetFullName = function() return "Model Test" end }
    state.inventory = { read = function(_, object, ids)
        assert(object == context)
        equal(ids, { "CarbonFiber", "Bio_Battery" })
        calls[#calls + 1] = true
        return { PlayerInventory = { CarbonFiber = 2, Bio_Battery = 1 },
            InsideBase = { CarbonFiber = 3, Bio_Battery = 4 } }
    end }
    equal(before(context), nil)
    equal(after(context), nil)
    equal(#calls, 2)
    local logs = table.concat(messages)
    assert(logs:find("FOCUS_COUNTS phase=CALL event=Cancel_ServerInternal", 1, true))
    assert(logs:find("FOCUS_COUNTS phase=POST event=Cancel_ServerInternal", 1, true))
    assert(logs:find("CarbonFiber:player=2:base_query=3", 1, true))
    state.stop()
    before(context)
    equal(#calls, 2)
end)

test("inventory sample budget accepts bounded diagnostic overrides only", function()
    local Counts = require("BetterWorkbench.NativeCounts")
    local utility = { IsValid = function() return true end }
    for _, budget in ipairs({ 0, 49, 1.5 }) do
        fails(function() Counts.new(countClass(utility), function(id) return id end, budget) end, "sample limit")
    end
    equal(Counts.new(countClass(utility), function(id) return id end, 24).maxReads, 24)
end)

test("unstarted cancellation uses copied actual inputs instead of fabricating intermediates", function()
    local Cancellation = require("BetterWorkbench.CancellationPlan")
    local job = { JobId = "battery", Status = "active", TotalBatches = 3, CompletedBatches = 0,
        ActualDebits = { CarbonFiber = 1, Coal = 4, FireOrgan = 2, ElectricOrgan = 3, IronIngot = 3 } }
    local plan = Cancellation.forUnstarted(job)
    equal(plan.Refund, job.ActualDebits)
    equal(plan.Refund.CarbonFiber, 1)
    plan.Refund.Coal = 100
    equal(job.ActualDebits.Coal, 4)
    equal(job.Status, "active") -- planning cannot settle / change a job
end)

test("unknown and partially completed refunds never infer quantities", function()
    local Cancellation = require("BetterWorkbench.CancellationPlan")
    local job = { JobId = "test", Status = "active", TotalBatches = 3, CompletedBatches = 1,
        ActualDebits = { Ore = 5 } }
    local result, reason = Cancellation.forUnstarted(job)
    equal(result, nil); equal(reason, "partial_refund_unverified")
    job.CompletedBatches, job.ActualDebits = 0, nil
    result, reason = Cancellation.forUnstarted(job)
    equal(result, nil); equal(reason, "debit_receipt_unavailable")
    job.ActualDebits = { Ore = -1 }
    fails(function() Cancellation.forUnstarted(job) end, "debit amount")
    job.Status = "cancelled"
    result, reason = Cancellation.forUnstarted(job)
    equal(result, nil); equal(reason, "job_not_active")
end)

test("cancellation transaction retries safely and settles a recorded job only once", function()
    local job = { JobId = "target", Status = "active", TotalBatches = 3, CompletedBatches = 0,
        ActualDebits = { Ore = 5 } }
    local stock, failCredit, runs = 0, true, 0
    local service = Service.new({ cancelNative = function(_, caller, id)
        assert(id == "target")
        if caller ~= "owner" then return nil, "not_authorized" end
        runs = runs + 1
        -- Mock native backend only: the service does not calculate a refund.
        local plan, reason = require("BetterWorkbench.CancellationPlan").forUnstarted(Util.copy(job))
        if not plan then return nil, reason end
        if failCredit then return nil, "destination_unavailable" end
        -- Mock atomic settlement contract. Actual Palworld backend is absent.
        stock = stock + plan.Refund.Ore
        job.Status = "cancelled"
        return plan
    end })
    local p, reason = service:cancel("stranger", "target")
    equal(p, nil); equal(reason, "not_authorized"); equal(runs, 0)
    p, reason = service:cancel("owner", "target")
    equal(p, nil); equal(reason, "destination_unavailable")
    equal(stock, 0); equal(job.Status, "active")
    failCredit = false
    assert(service:cancel("owner", "target"))
    equal(stock, 5); equal(job.Status, "cancelled")
    p, reason = service:cancel("owner", "target")
    equal(p, nil); equal(reason, "job_not_active"); equal(stock, 5)
end)

test("service cancellation delegates unchanged and has no custom refund fallback", function()
    local context = { Caller = "test" }
    local called, sentinel = 0, {}
    local service = Service.new({ cancelNative = function(_, received, id)
        equal(received, context); equal(id, "native-job")
        called = called + 1
        return sentinel, "native_result"
    end })
    local result, reason = service:cancel(context, "native-job")
    assert(result == sentinel)
    equal(reason, "native_result"); equal(called, 1)
    fails(function() Service.new({}):cancel(context, "native-job") end, "native cancellation backend unavailable")
end)

local BatchSchedule = require("BetterWorkbench.BatchSchedule")
test("native batch schedule preserves mixed existing and expanded inputs", function()
    local recipes = {
        Bio_Battery = { OutputItem = "Bio_Battery", OutputAmount = 1, WorkAmount = 10,
            Materials = { CarbonFiber = 1, IronIngot = 2, ElectricOrgan = 2 } },
        CarbonFiber = { OutputItem = "CarbonFiber", OutputAmount = 1, WorkAmount = 2,
            Materials = { Coal = 2, FireOrgan = 3 } },
    }
    local nativeCosts = {
        Bio_Battery = { CarbonFiber = 1, IronIngot = 1, ElectricOrgan = 1 },
        CarbonFiber = { Coal = 2, FireOrgan = 1 },
    }
    local rootQueries, intermediateQueries = 0, 0
    local context = { canCraft = function() return true end, RequireEffectiveCosts = true,
        StationRecipes = { Bio_Battery = true, CarbonFiber = true },
        materialsForBatches = function(id, _, batches, isRoot)
            equal(batches, 1)
            if isRoot then rootQueries = rootQueries + 1 else intermediateQueries = intermediateQueries + 1 end
            return Util.copy(nativeCosts[id])
        end }
    local stock = { CarbonFiber = 1, Coal = 4, FireOrgan = 2, IronIngot = 3, ElectricOrgan = 3 }
    local before = Util.copy(stock)
    local s = BatchSchedule.resolve(Resolver.new(recipes), "Bio_Battery", 3, stock, context)
    assert(s.Craftable); equal(rootQueries, 3); equal(intermediateQueries, 2)
    equal(s.Units[1].Inputs, { CarbonFiber = 1, IronIngot = 1, ElectricOrgan = 1 })
    equal(s.Units[2].Inputs, { Coal = 2, FireOrgan = 1, IronIngot = 1, ElectricOrgan = 1 })
    equal(s.Units[3].Inputs, s.Units[2].Inputs)
    equal(s.ActualInputs, stock); equal(#s.SlotItems, 5); equal(s.OutputAmount, 3)
    equal(BatchSchedule.remaining(s, 1), { Coal = 4, FireOrgan = 2, IronIngot = 2, ElectricOrgan = 2 })
    equal(BatchSchedule.remaining(s, 3), {}); equal(stock, before)
    s.Units[2].Inputs.Coal = 100
    equal(s.Units[3].Inputs.Coal, 2); equal(s.ActualInputs.Coal, 4)
end)

test("batch schedule shares generated surplus without debiting imaginary items", function()
    local recipes = {
        Target = { OutputItem = "Target", OutputAmount = 1, WorkAmount = 1, Materials = { Part = 1, Glue = 1 } },
        Part = { OutputItem = "Part", OutputAmount = 2, WorkAmount = 1, Materials = { Ore = 3 } },
    }
    local context = { canCraft = function() return true end, StationRecipes = { Target = true, Part = true } }
    local s = BatchSchedule.resolve(Resolver.new(recipes), "Target", 2, { Ore = 3, Glue = 2 }, context)
    assert(s.Craftable)
    equal(s.ActualInputs, { Ore = 3, Glue = 2 })
    equal(s.Units[1].Inputs, { Ore = 3, Glue = 1 })
    equal(s.Units[2].Inputs, { Glue = 1 })
    equal(s.Units[1].VirtualSurplus.Part, 1); equal(s.VirtualSurplus.Part, 0)
end)

test("batch schedule refuses unverified costs slot overflow and excessive size", function()
    local recipes = { Target = { OutputItem = "Target", OutputAmount = 1, WorkAmount = 1,
        Materials = { A = 1, B = 1, C = 1, D = 1, E = 1, F = 1 } } }
    local resolver = Resolver.new(recipes)
    local context = { canCraft = function() return true end, StationRecipes = { Target = true }, RequireEffectiveCosts = true }
    local s = BatchSchedule.resolve(resolver, "Target", 1, {}, context)
    assert(not s.Craftable); equal(s.Issues[1].Reason, "effective_costs_unverified")
    context.RequireEffectiveCosts = false
    s = BatchSchedule.resolve(resolver, "Target", 1, { A = 1, B = 1, C = 1, D = 1, E = 1, F = 1 }, context)
    assert(not s.Craftable); equal(s.Issues[1].Reason, "native_input_slot_limit")
    s = BatchSchedule.resolve(resolver, "Target", 257, {}, context)
    assert(not s.Craftable); equal(s.Issues[1].Reason, "schedule_batch_limit")
end)

test("batch schedule never expands charcoal through a foreign furnace", function()
    local recipes = {
        Target = { OutputItem = "Target", OutputAmount = 1, WorkAmount = 1, Materials = { Charcoal = 5 } },
        Charcoal = { OutputItem = "Charcoal", OutputAmount = 1, WorkAmount = 1, Materials = { Wood = 2 } },
    }
    local context = { canCraft = function() return true end, StationRecipes = { Target = true } }
    local stock = { Charcoal = 5, Wood = 100 }
    local s = BatchSchedule.resolve(Resolver.new(recipes), "Target", 2, stock, context)
    assert(not s.Craftable); equal(s.FailedBatch, 2)
    equal(stock, { Charcoal = 5, Wood = 100 })
end)

local SnapshotPlanner = require("BetterWorkbench.NativeSnapshotPlan")
local JobPlan = require("BetterWorkbench.JobPlan")
local function nativePacket()
    return { Schema = 1, ReadOnly = true, NativeCosts = true, ScopeComplete = true,
        EligibilityVerified = false, RecipeId = "Bio_Battery", Batches = 3,
        StationRecipes = { Bio_Battery = true, CarbonFiber = true, CarbonFiber2 = true },
        Inventory = { CarbonFiber = 1, Coal = 4, Charcoal = 10, FireOrgan = 2,
            ElectricOrgan = 3, IronIngot = 3, Wood = 100 },
        BatchDemand = { CarbonFiber = 3, ElectricOrgan = 3, IronIngot = 3 },
        Recipes = {
            Bio_Battery = { OutputItem = "Bio_Battery", OutputAmount = 1, WorkAmount = 8,
                Materials = { CarbonFiber = 2, ElectricOrgan = 2, IronIngot = 2 },
                EffectiveMaterials = { CarbonFiber = 1, ElectricOrgan = 1, IronIngot = 1 } },
            CarbonFiber = { OutputItem = "CarbonFiber", OutputAmount = 1, WorkAmount = 4,
                Materials = { Coal = 4, FireOrgan = 1 }, EffectiveMaterials = { Coal = 2, FireOrgan = 1 } },
            CarbonFiber2 = { OutputItem = "CarbonFiber", OutputAmount = 1, WorkAmount = 4,
                Materials = { Charcoal = 10, FireOrgan = 1 }, EffectiveMaterials = { Charcoal = 5, FireOrgan = 1 } },
            Charcoal = { OutputItem = "Charcoal", OutputAmount = 1, WorkAmount = 2,
                Materials = { Wood = 2 }, EffectiveMaterials = { Wood = 2 } },
        } }
end
test("owned native snapshot drives researched mixed battery schedule", function()
    local packet = nativePacket()
    local before = Util.copy(packet)
    local plan = SnapshotPlanner.check(packet)
    assert(plan.Craftable and plan.ReadOnly and not plan.EligibilityVerified)
    equal(plan.ActualInputs, { CarbonFiber = 1, Coal = 4, FireOrgan = 2, ElectricOrgan = 3, IronIngot = 3 })
    equal(plan.Units[1].Inputs, { CarbonFiber = 1, ElectricOrgan = 1, IronIngot = 1 })
    equal(plan.Units[2].Inputs, { Coal = 2, FireOrgan = 1, ElectricOrgan = 1, IronIngot = 1 })
    equal(plan.Units[1].WorkAmount, 8); equal(plan.Units[2].WorkAmount, 12)
    equal(packet, before)
end)
test("snapshot validates native batch and complete authoritative scope", function()
    local packet = nativePacket()
    packet.BatchDemand.CarbonFiber = 6
    fails(function() SnapshotPlanner.check(packet) end, "native batch demand changed")
    packet = nativePacket(); packet.ScopeComplete = false
    fails(function() SnapshotPlanner.check(packet) end, "unverified native snapshot")
    packet = nativePacket(); packet.Inventory.Coal = nil
    fails(function() SnapshotPlanner.check(packet) end, "native scope stock")
    packet = nativePacket(); packet.Recipes.CarbonFiber.EffectiveMaterials.Wood = 2
    fails(function() SnapshotPlanner.check(packet) end, "native cost identity")
end)
test("native snapshot uses existing charcoal fallback but never furnace expansion", function()
    local packet = nativePacket(); packet.Inventory.Coal = 0
    local plan = SnapshotPlanner.check(packet)
    assert(plan.Craftable); equal(plan.ActualInputs.Charcoal, 10); equal(plan.ActualInputs.Wood, nil)
    packet.Inventory.Charcoal = 0
    plan = SnapshotPlanner.check(packet)
    assert(not plan.Craftable)
    equal(plan.Issues[1].Reason, "cross_station_recipe")
    equal(packet.Inventory.Wood, 100)
end)
test("snapshot queue monitor handles rejection and stops cleanly on reload", function()
    local queue = { nativePacket(), nativePacket() }
    queue[1].BatchDemand.CarbonFiber = 100
    local loop, callback
    local api = {
        LoopAsync = function(_, fn) loop = fn end,
        ExecuteInGameThread = function(fn) callback = fn end,
        BetterWorkbenchNativeTakeSnapshot = function() return table.remove(queue, 1) end,
    }
    local monitor = SnapshotPlanner.start({}, api)
    assert(loop() == false); callback()
    equal(monitor.packets, 2); equal(monitor.errors, 1)
    assert(monitor.last.Craftable)
    monitor.stop(); assert(loop() == true)
    queue = { nativePacket() }; callback(); equal(#queue, 1)
end)
local stable = { WorldId = "world-001", StationId = "station-001", JobId = "job-001",
    GameBuild = "local-reviewed-build", Checkpoint = "native-save-001" }
local function nativeState(job, completed)
    local saved = job:export()
    return { Binding = Util.copy(saved.Binding), RecipeId = saved.RecipeId,
        Requested = saved.Batches, Remaining = saved.Batches - completed,
        SlotItems = Util.copy(saved.SlotItems), Inputs = BatchSchedule.remaining(
            { Craftable = true, Batches = saved.Batches, Units = saved.Units }, completed) }
end
test("task costs keep mixed units consistent through completion and save restore", function()
    local plan = SnapshotPlanner.check(nativePacket())
    local job = JobPlan.new(plan, stable)
    equal(job:view().UnitInputs, plan.Units[1].Inputs)
    job:confirmNativeCompletion(nativeState(job, 1))
    equal(job:view().UnitInputs, plan.Units[2].Inputs)
    equal(job:view().RemainingInputs, { Coal = 4, FireOrgan = 2, ElectricOrgan = 2, IronIngot = 2 })
    local saved = job:export()
    local restored = JobPlan.restore(saved, nativeState(job, 1))
    equal(restored:view(), job:view())
    restored:confirmNativeCompletion(nativeState(restored, 2))
    restored:confirmNativeCompletion(nativeState(restored, 3))
    equal(restored:view().RemainingInputs, {}); equal(restored:view().UnitInputs, {})
    equal(restored:view().OutputAmount, 0)
    fails(function() restored:confirmNativeCompletion(nativeState(restored, 3)) end, "already complete")
    -- The exported payload is detached and contains no virtual intermediate
    -- credits or raw game object pointers.
    saved.Units[2].Inputs.Coal = 999
    equal(job:view().UnitInputs.Coal, 2)
    equal(job:export().VirtualSurplus, nil)
end)
test("failed or repeated native transaction cannot advance task accounting", function()
    local job = JobPlan.new(SnapshotPlanner.check(nativePacket()), stable)
    local before = job:export()
    local wrong = nativeState(job, 1); wrong.Inputs.Coal = 3
    fails(function() job:confirmNativeCompletion(wrong) end, "native inputs")
    equal(job:export(), before)
    job:confirmNativeCompletion(nativeState(job, 1))
    before = job:export()
    fails(function() job:confirmNativeCompletion(nativeState(job, 1)) end, "native task progress")
    equal(job:export(), before)
end)
test("saved task rejects wrong world station generation build or checkpoint", function()
    local job = JobPlan.new(SnapshotPlanner.check(nativePacket()), stable)
    for _, field in ipairs({ "WorldId", "StationId", "JobId", "GameBuild", "Checkpoint" }) do
        local native = nativeState(job, 0); native.Binding[field] = "different"
        fails(function() JobPlan.restore(job:export(), native) end, "binding mismatch")
    end
    local saved = job:export(); saved.Units[2].Inputs.Coal = 3
    fails(function() JobPlan.restore(saved, nativeState(job, 0)) end, "total does not match")
    saved = job:export(); saved.SlotItems[1] = "unrelated"
    fails(function() JobPlan.restore(saved, nativeState(job, 0)) end, "slot order")
    saved = job:export(); saved.Schema = 2
    fails(function() JobPlan.restore(saved, nativeState(job, 0)) end, "unsupported task plan")
end)

test("new save checkpoints preserve task identity without blocking completion", function()
    local job = JobPlan.new(SnapshotPlanner.check(nativePacket()), stable)
    local native = nativeState(job, 1); native.Binding.Checkpoint = "native-save-002"
    job:confirmNativeCompletion(native)
    local payload = job:forSave("native-save-002")
    equal(job:export().Binding.Checkpoint, "native-save-001")
    local restored = JobPlan.restore(payload, native)
    equal(restored:view(), job:view())
    native.Binding.Checkpoint = "native-save-001"
    fails(function() JobPlan.restore(payload, native) end, "binding mismatch")
end)

test("normal native profile starts no background Lua probes", function()
    local previousLoop, previousDispatch, previousActive = LoopAsync, ExecuteInGameThread, BetterWorkbenchNativeIsActive
    local scheduled = 0
    LoopAsync = function() scheduled = scheduled + 1 end
    ExecuteInGameThread = function() scheduled = scheduled + 1 end
    BetterWorkbenchNativeIsActive = function() return true end
    local ready = require("BetterWorkbench.PalworldAdapter").start({ Diagnostics = { Enabled = false } })
    LoopAsync, ExecuteInGameThread, BetterWorkbenchNativeIsActive = previousLoop, previousDispatch, previousActive
    assert(ready)
    equal(scheduled, 0)
end)

local Disassembly = require("BetterWorkbench.DisassemblyPlan")
local function disassemblyState(owned)
    return {
        Recipes = { Part = { OutputItem = "Part", OutputAmount = 2,
            Materials = { Ingot = 3, Fiber = 1 }, WorkAmount = 20 } },
        Inventory = { Part = owned },
        Context = { StationRecipes = { Part = true }, canDisassemble = function() return true end,
            materialsForBatches = function() error("reverse must not use research costs") end },
    }
end

test("instant disassembly returns full original materials without work or recursion", function()
    local state = disassemblyState(7)
    local before = Util.copy(state.Recipes)
    local p = Disassembly.resolve("Part", 3, state)
    assert(p.CanDisassemble)
    equal(p.Consumed, { Part = 6 })
    equal(p.Returns, { Ingot = 9, Fiber = 3 })
    equal(p.WorkAmount, 0)
    equal(p.MaxBatches, 3)
    equal(state.Inventory, { Part = 7 })
    equal(state.Recipes, before)
    p.Returns.Ingot = 99
    equal(state.Recipes, before)
end)

test("disassembly requires whole output batches and fresh eligible station scope", function()
    local state = disassemblyState(3)
    local p = Disassembly.resolve("Part", 2, state)
    assert(not p.CanDisassemble and p.Reason == "insufficient_products")
    state.Context.StationRecipes = nil
    equal(Disassembly.resolve("Part", 1, state).Reason, "station_scope_unverified")
    state.Context.StationRecipes = {}
    equal(Disassembly.resolve("Part", 1, state).Reason, "cross_station_recipe")
    state.Context.StationRecipes.Part = true
    state.Context.canDisassemble = nil
    equal(Disassembly.resolve("Part", 1, state).Reason, "disassembly_policy_unverified")
    state.Context.canDisassemble = function() return false, "locked_recipe" end
    equal(Disassembly.resolve("Part", 1, state).Reason, "locked_recipe")
end)

test("disassembly rejects invalid quantities free recipes and overflow", function()
    local state = disassemblyState(10)
    for _, amount in ipairs({ 0, -1, 1.5, 257, math.huge }) do
        fails(function() Disassembly.resolve("Part", amount, state) end, "invalid")
    end
    state.Recipes.Part.Materials.Ingot = 1000000000
    fails(function() Disassembly.resolve("Part", 2, state) end, "count limit")
    state.Recipes.Part.Materials = {}
    equal(Disassembly.resolve("Part", 1, state).Reason, "no_return_materials")
end)

test("disassembly service recomputes inside authoritative transaction", function()
    local backend = { state = disassemblyState(6), commits = 0 }
    function backend:disassemblySnapshot() return self.state end
    function backend:disassemblyTransaction(context, build)
        local p, reason = build(self.state)
        if not p then return nil, reason end
        self.commits = self.commits + 1
        return p
    end
    local service = Service.new(backend)
    assert(service:previewDisassembly({}, "Part", 3).CanDisassemble)
    backend.state.Inventory.Part = 1
    local result, reason = service:disassemble({}, "Part", 3)
    assert(result == nil and reason == "insufficient_products" and backend.commits == 0)
    backend.state.Inventory.Part = 6
    backend.state.Recipes.Part.Materials.Ingot = 4
    local p = service:disassemble({}, "Part", 3)
    equal(p.Returns, { Ingot = 12, Fiber = 3 })
    equal(backend.commits, 1)
end)

test("disassembly preview shares only an explicit refresh snapshot and commits re-read", function()
    local backend = { reads = 0, state = disassemblyState(6) }
    function backend:disassemblySnapshot()
        self.reads = self.reads + 1
        return Util.copy(self.state)
    end
    function backend:disassemblyTransaction(_, build) return build(self.state) end
    local service = Service.new(backend)
    local base, _, snapshot = service:previewDisassembly({}, "Part", 1)
    assert(base.CanDisassemble)
    backend.state = disassemblyState(2)
    local current = service:previewDisassembly({}, "Part", 3, snapshot)
    assert(current.CanDisassemble and current.OwnedAmount == 6)
    equal(backend.reads, 1)
    local fresh = service:previewDisassembly({}, "Part", 3)
    assert(not fresh.CanDisassemble and fresh.OwnedAmount == 2)
    equal(backend.reads, 2)
    local result, reason = service:disassemble({}, "Part", 3)
    assert(result == nil and reason == "insufficient_products")
end)

test("disassembly requires its own backend instead of craft transactions", function()
    local service = Service.new({ transaction = function() error("craft transaction called") end,
        snapshot = function() error("craft stock queried") end })
    local p, reason = service:disassemble({}, "Part", 1)
    assert(p == nil and reason == "native_disassembly_unavailable")
    p, reason = service:previewDisassembly({}, "Part", 1)
    assert(p == nil and reason == "native_disassembly_unavailable")
end)

dofile(PROJECT_ROOT .. "/tests/disassembly_runtime.lua")(test, equal)
print(string.format("\n%d tests passed (including 200 conservation scenarios).", count))
