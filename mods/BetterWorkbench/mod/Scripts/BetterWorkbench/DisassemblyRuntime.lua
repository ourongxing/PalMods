local Util = require("BetterWorkbench.Util")
local Scope = require("BetterWorkbench.StationScope")
local Capacity = require("BetterWorkbench.DisassemblyCapacity")
local M = {}
M.__index = M
local function valid(object)
    if not object then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end
local function identity(object) return object:GetFullName() end
local function containers(inventory)
    local result, seen = {}, {}
    for _, kind in ipairs({ 0, 2, 3, 4, 5 }) do
        local out = {}
        if inventory:TryGetContainerFromInventoryType(kind, out) and valid(out.OutContainer) then
            local key = identity(out.OutContainer)
            if not seen[key] then result[#result + 1], seen[key] = out.OutContainer, true end
        end
    end
    assert(#result > 0, "player inventory containers unavailable")
    return result
end
local function scan(inventory, sourceContainers)
    local slots, totals = {}, {}
    for _, container in ipairs(sourceContainers or containers(inventory)) do
        local containerId = identity(container)
        local size = Util.integer(container:Num(), 0, 256, "container size")
        for index = 0, size - 1 do
            local slot = container:Get(index)
            assert(valid(slot), "inventory slot unavailable")
            local count = Util.integer(slot.StackCount, 0, 1000000000, "slot count")
            local item = count > 0 and slot.ItemId.StaticId:ToString() or "None"
            assert(type(item) == "string" and (count == 0 or item ~= "None"), "invalid slot identity")
            local key = containerId .. ":" .. index
            slots[#slots + 1] = { Key = key, Object = slot, Container = containerId, Item = item, Count = count }
            if count > 0 then totals[item] = Util.integer((totals[item] or 0) + count, 1, 1000000000, "inventory total") end
        end
    end
    return slots, totals
end
local function each(array, limit, callback)
    assert(array:GetArrayNum() <= limit, "inventory scope exceeds limit")
    array:ForEach(function(_, parameter) callback(parameter:get()) end)
end
local function sourceContainers(api, inventory, concrete, controller)
    local result, seen = containers(inventory), {}
    for _, container in ipairs(result) do seen[identity(container)] = true end
    local base = concrete:GetBaseCampModelBelongTo()
    local storage
    if valid(base) then
        each(base.ModuleArray, 32, function(module)
            if module:GetClass():GetFName():ToString() == "PalBaseCampModuleItemStorage" then storage = module end
        end)
        assert(valid(storage), "base storage unavailable")
        local manager = api.StaticFindObject("/Script/Pal.Default__PalUtility"):GetItemContainerManager(controller)
        assert(valid(manager), "base container manager unavailable")
        local function add(info)
            if not info.bShouldUseContainerIdCache then return end
            local container = manager:GetContainer(info.ContainerIdCache)
            -- Storage caches can retain removed or unloaded container IDs.
            -- Skip those entries; read() still verifies the product total
            -- against the game's accessible inventory before any writes.
            if not valid(container) then return end
            local key = identity(container)
            if not seen[key] then result[#result + 1], seen[key] = container, true end
        end
        each(storage.ContainerInfos, 4096, add)
        add(storage.GuildContainerInfo)
    end
    return result, storage
end
function M.new(api)
    return setmetatable({ api = api or _G, busy = false }, M)
end
function M:read(session)
    assert(valid(session.workspace) and valid(session.card), "workbench closed")
    local controller = session.workspace:GetOwningPlayer()
    assert(valid(controller) and controller:HasAuthority(), "disassembly requires the local server host")
    -- The workspace owns a UI UObject under this exact Blueprint field name;
    -- authority belongs to the player controller, not this presentation model.
    local model = session.workspace["Convert Item Model"]
    assert(valid(model), "workbench model unavailable")
    local recipeId = session.card.RecipeId:ToString()
    assert(recipeId == session.recipeId, "workbench recipe changed")
    local concrete = {}
    assert(model:TryGetConcreteModel(concrete) and valid(concrete.Model), "current workbench unavailable")
    local recipes = concrete.Model:GetRecipes()
    local station
    if type(recipes) == "table" then
        assert(#recipes <= 4096, "invalid workbench recipe count")
        station = {}
        for _, parameter in ipairs(recipes) do
            local kind = parameter:type()
            local name = (kind == "RemoteUnrealParam" or kind == "LocalUnrealParam") and parameter:get() or parameter
            assert(name:type() == "FName", "workbench recipe is not FName")
            local id = name:ToString()
            assert(id ~= "" and id ~= "None" and #id <= 256, "invalid workbench recipe ID")
            station[id] = true
        end
    else station = Scope.copyNames(recipes) end
    assert(station[recipeId], "recipe outside current workbench")
    local inventory = controller.PlayerState:GetInventoryData()
    assert(valid(inventory), "player inventory unavailable")
    local utility = self.api.StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
    assert(valid(utility), "recipe table utility unavailable")
    local table = utility:GetItemRecipeDataTableAccess(controller)
    assert(valid(table), "recipe table unavailable")
    local found = {}
    local row = table:BP_FindRow(self.api.FName(recipeId), found)
    assert(found.bResult == true, "recipe unavailable")
    local recipe = { OutputItem = row.Product_Id:ToString(), OutputAmount = row.Product_Count,
        Materials = {}, WorkAmount = row.WorkAmount }
    for index = 1, 5 do
        local id, count = row["Material" .. index .. "_Id"]:ToString(), row["Material" .. index .. "_Count"]
        Util.integer(count, 0, 1000000000, "recipe material count")
        if id ~= "None" and count > 0 then recipe.Materials[id] = (recipe.Materials[id] or 0) + count end
    end
    assert(not recipe.Materials[recipe.OutputItem], "self-returning recipe unavailable")
    local slots, backpackTotals = scan(inventory)
    local scope, storage = sourceContainers(self.api, inventory, concrete.Model, controller)
    local sourceSlots, totals = scan(inventory, scope)
    -- Match the production detail pane's exact collection mode. If a locked,
    -- inaccessible or uncached chest changes the accessible count, fail before
    -- any writes rather than presenting stock we cannot safely debit.
    local itemUtility = self.api.StaticFindObject("/Script/Pal.Default__PalItemUtility")
    assert(valid(itemUtility), "production inventory utility unavailable")
    local collected = {}
    itemUtility:CollectLocalPlayerControllableItemInfos(session.workspace,
        { self.api.FName(recipe.OutputItem) }, collected, 2)
    local accessible = 0
    local function count(info)
        if info.StaticItemId:ToString() == recipe.OutputItem then
            accessible = accessible + Util.integer(info.Num, 0, 1000000000, "accessible product stock")
        end
    end
    local infos = collected.OutItemInfos or collected
    if type(infos) == "table" then
        assert(#infos <= 4096, "invalid accessible inventory")
        for _, parameter in ipairs(infos) do
            local kind = parameter:type()
            count((kind == "RemoteUnrealParam" or kind == "LocalUnrealParam") and parameter:get() or parameter)
        end
    else each(infos, 4096, count) end
    assert(accessible == (totals[recipe.OutputItem] or 0), "production inventory scope mismatch")
    return { Recipes = { [recipeId] = recipe }, Inventory = totals,
        Context = { StationRecipes = station, canDisassemble = function() return true end } },
        { inventory = inventory, slots = slots, controller = controller, backpackTotals = backpackTotals,
            sourceSlots = sourceSlots, sourceContainers = scope, storage = storage }
end
function M:disassemblySnapshot(session)
    local state = self:read(session)
    return state
end
local function refresh(slot)
    pcall(function() slot:OnRep_StackCount() end)
    pcall(function() slot:OnRep_ItemId() end)
end
function M:disassemblyTransaction(session, build)
    if self.disabled then return nil, "disassembly_disabled_after_inventory_error" end
    if self.busy then return nil, "disassembly_in_progress" end
    self.busy = true
    local ok, plan, reason = pcall(function()
        local state, runtime = self:read(session)
        local sourceSlots = runtime.sourceSlots or runtime.slots
        local plan, problem = build(state)
        if not plan then return nil, problem end
        local targets, limits = {}, {}
        local utility = self.api.StaticFindObject("/Script/Pal.Default__PalUtility")
        assert(valid(utility), "item utility unavailable")
        local manager = utility:GetItemIDManager(runtime.controller)
        assert(valid(manager), "item definitions unavailable")
        for item in pairs(plan.Returns) do
            local out = {}
            assert(runtime.inventory:TryGetContainerFromStaticItemID(self.api.FName(item), out) and valid(out.OutContainer),
                "return container unavailable")
            targets[item] = identity(out.OutContainer)
            local data = manager:GetStaticItemData(self.api.FName(item))
            assert(valid(data), "return item definition unavailable")
            limits[item] = Util.integer(data.MaxStackCount, 1, 1000000000, "return stack limit")
            -- Rollback is limited to ordinary stackable recipe materials.
            assert(limits[item] > 1, "non-stackable return material unsupported")
        end
        local fits, problem = Capacity.check(runtime.slots, plan.Returns, targets, limits)
        if not fits then return nil, problem end
        local before = {}
        for _, slot in ipairs(sourceSlots) do before[slot.Key] = slot end
        local function refreshContainers()
            if runtime.sourceContainers then
                for _, container in ipairs(runtime.sourceContainers) do
                    container:OnRep_ItemSlotArray()
                    if valid(runtime.storage) then runtime.storage:OnUpdateItemContainer(container) end
                end
            end
        end
        local function rollback()
            local after = scan(runtime.inventory, runtime.sourceContainers)
            for _, slot in ipairs(after) do
                local old = before[slot.Key]
                assert(old, "inventory layout changed during disassembly")
                if slot.Count ~= old.Count or slot.Item ~= old.Item then
                    assert(slot.Object.ItemId.StaticId:ToString() == old.Item or old.Count == 0,
                        "inventory item changed during disassembly")
                    slot.Object.StackCount = old.Count
                    refresh(slot.Object)
                end
            end
            refreshContainers()
        end
        local applied, failed = pcall(function()
            for _, item in ipairs(Util.keys(plan.Returns)) do
                -- Enable the native acquisition log/toast for each returned
                -- material, using the same item-add path as the reference mod.
                runtime.inventory:AddItem_ServerInternal(self.api.FName(item), plan.Returns[item], true, 0.0, true)
            end
            local _, totals = scan(runtime.inventory)
            local expected = Util.copy(runtime.backpackTotals or state.Inventory)
            for item, count in pairs(plan.Returns) do expected[item] = (expected[item] or 0) + count end
            for item, count in pairs(expected) do assert(totals[item] == count, "native material return mismatch") end
            for item in pairs(totals) do assert(expected[item], "unexpected inventory return") end
            local remaining = plan.Consumed[plan.ProductItem]
            for _, slot in ipairs(sourceSlots) do
                if slot.Item == plan.ProductItem and remaining > 0 then
                    assert(slot.Object.StackCount == slot.Count, "product stock changed")
                    local used = math.min(remaining, slot.Count)
                    slot.Object.StackCount = slot.Count - used
                    assert(slot.Object.StackCount == slot.Count - used, "product debit failed")
                    remaining = remaining - used
                end
            end
            assert(remaining == 0, "product debit incomplete")
            refreshContainers()
            expected = Util.copy(state.Inventory)
            for item, count in pairs(plan.Returns) do expected[item] = (expected[item] or 0) + count end
            expected[plan.ProductItem] = (expected[plan.ProductItem] or 0) - plan.Consumed[plan.ProductItem]
            local _, final = scan(runtime.inventory, runtime.sourceContainers)
            for item, count in pairs(expected) do assert((final[item] or 0) == count, "final inventory mismatch") end
            for item in pairs(final) do assert(expected[item], "unexpected final inventory item") end
        end)
        if not applied then
            -- A native add may fall back to a world drop. Even if backpack counts
            -- can be restored, do not permit a retry in this runtime session.
            self.disabled = true
            local restored, restoreError = pcall(rollback)
            if not restored then error("inventory rollback failed: " .. tostring(restoreError)) end
            return nil, tostring(failed)
        end
        local after = scan(runtime.inventory, runtime.sourceContainers)
        for _, slot in ipairs(after) do
            if slot.Count ~= before[slot.Key].Count or slot.Item ~= before[slot.Key].Item then refresh(slot.Object) end
        end
        return plan
    end)
    self.busy = false
    if not ok then return nil, tostring(plan) end
    return plan, reason
end
return M
