local Plan = require("BetterPalSouls.Plan")
local M = {}
M.__index = M
local rankFields = { "Rank_Attack", "Rank_Defence", "Rank_HP", "Rank_CraftSpeed" }
local function valid(o)
    local ok, result = pcall(function() return o and o:IsValid() end)
    return ok and result == true
end
M.valid = valid
local function name(o) return o:GetFullName() end
local function unwrap(o)
    local ok, result = pcall(function() return o:get() end)
    return ok and result or o
end
M.unwrap = unwrap
local function each(array, limit, fn)
    if type(array) == "table" then
        assert(#array <= limit, "array_too_large")
        for _, item in ipairs(array) do fn(unwrap(item)) end
    else
        assert(array:GetArrayNum() <= limit, "array_too_large")
        array:ForEach(function(_, item) fn(unwrap(item)) end)
    end
end
local function guid(o) return { A = o.A, B = o.B, C = o.C, D = o.D } end
local function sameGuid(a, b)
    return a.A == b.A and a.B == b.B and a.C == b.C and a.D == b.D
end
local function zeroGuid(o) return o.A == 0 and o.B == 0 and o.C == 0 and o.D == 0 end
local function plainItem(slot)
    return zeroGuid(slot.ItemId.DynamicId.CreatedWorldId) and zeroGuid(slot.ItemId.DynamicId.LocalIdInCreatedWorld)
end
local function scan(sources)
    local slots, stock = {}, Plan.copy({})
    for _, source in ipairs(sources) do
        assert(valid(source.Object), "container_unavailable")
        local count = Plan.integer(source.Object:Num(), 0, 4096)
        for index = 0, count - 1 do
            local object = source.Object:Get(index)
            assert(valid(object), "slot_unavailable")
            local amount = Plan.integer(object.StackCount, 0, 1000000000)
            local id = object.ItemId.StaticId:ToString()
            if Plan.weight[id] and amount > 0 then
                assert(plainItem(object), "dynamic_soul_unsupported")
                stock[id] = stock[id] + amount
            end
            -- Only empty, ordinary backpack slots may receive a new item type.
            slots[#slots + 1] = { Object = object, Key = name(object), Item = id, Count = amount,
                Backpack = source.Backpack and (amount > 0 or plainItem(object)) }
        end
    end
    return slots, stock
end
function M.new(api) return setmetatable({ api = api or _G }, M) end
function M:object(path)
    local object = self.api.StaticFindObject(path)
    assert(valid(object), "missing_interface: " .. path)
    return object
end
function M:sources(controller, inventory, world)
    local bag
    for _, id in ipairs(Plan.items) do
        local out = {}
        assert(inventory:TryGetContainerFromStaticItemID(self.api.FName(id), out) and valid(out.OutContainer),
            "backpack_unavailable")
        if bag then assert(name(bag) == name(out.OutContainer), "soul_container_mismatch") else bag = out.OutContainer end
    end
    local result, seen = { { Object = bag, Backpack = true } }, { [name(bag)] = true }
    local utility = self:object("/Script/Pal.Default__PalUtility")
    local player = utility:GetPalmi(controller)
    assert(valid(player), "player_unavailable")
    local check = player.InsideBaseCampCheckComponent
    local base = valid(check) and check:GetInsideBaseCampModel() or nil
    if valid(base) then
        local guild = self:object("/Script/Pal.Default__PalGroupUtility"):GetLocalPlayerGuild(player)
        assert(valid(guild) and sameGuid(guid(base:GetGroupIdBelongTo()), guid(guild:GetId())), "base_permission")
        local storage
        each(base.ModuleArray, 32, function(module)
            if module:GetClass():GetFName():ToString() == "PalBaseCampModuleItemStorage" then storage = module end
        end)
        assert(valid(storage), "base_storage_unavailable")
        local manager = utility:GetItemContainerManager(world)
        assert(valid(manager), "container_manager_unavailable")
        local function add(info)
            if not info.bShouldUseContainerIdCache then return end
            local container = manager:GetContainer(info.ContainerIdCache)
            if not valid(container) or seen[name(container)] then return end
            seen[name(container)] = true
            result[#result + 1] = { Object = container, Backpack = false }
        end
        each(storage.ContainerInfos, 4096, add)
        add(storage.GuildContainerInfo)
    end
    return result
end
function M:accessible(world)
    local ids, out, result = {}, {}, Plan.copy({})
    for _, id in ipairs(Plan.items) do ids[#ids + 1] = self.api.FName(id) end
    self:object("/Script/Pal.Default__PalItemUtility"):CollectLocalPlayerControllableItemInfos(world, ids, out, 2)
    each(out.OutItemInfos or out, 4096, function(info)
        local id = info.StaticItemId:ToString()
        assert(Plan.weight[id], "unexpected_inventory_item")
        result[id] = result[id] + Plan.integer(info.Num, 0, 1000000000)
    end)
    return result
end
function M:schedule(world)
    local utility = self:object("/Script/Pal.Default__PalMasterDataTablesUtility")
    local table = utility:GetCharacterUpgradeDataTable(world)
    assert(valid(table), "upgrade_table_unavailable")
    local result, max = {}, 0
    for _, row in pairs(table:GetRowMap()) do
        local rank = Plan.integer(row.Rank, 1, 255)
        local id = row.RequiredStaticItemId:ToString()
        assert(Plan.weight[id] and not result[rank], "unsupported_upgrade_table")
        result[rank] = { Item = id, Count = Plan.integer(row.RequiredItemNum, 0, 1000000000) }
        max = math.max(max, rank)
    end
    assert(max > 0, "upgrade_table_empty")
    for rank = 1, max do assert(result[rank], "upgrade_table_gap") end
    -- Verify the installed crusher conversion ratios instead of assuming modded recipes.
    local recipes = utility:GetItemRecipeDataTableAccess(world)
    for i = 1, 3 do
        for _, conversion in ipairs({
            { i == 3 and "PalUpgradeStone4_3" or "PalUpgradeStone" .. i .. "_" .. (i + 1), Plan.items[i], 2, Plan.items[i + 1], 1 },
            { i == 3 and "PalUpgradeStone3_4" or "PalUpgradeStone" .. (i + 1) .. "_" .. i, Plan.items[i + 1], 1, Plan.items[i], 2 },
        }) do
            local out = {}
            local row = recipes:BP_FindRow(self.api.FName(conversion[1]), out)
            assert(out.bResult and row.Material1_Id:ToString() == conversion[2]
                and row.Material1_Count == conversion[3] and row.Product_Id:ToString() == conversion[4]
                and row.Product_Count == conversion[5], "unsupported_conversion_recipe")
            for field = 2, 5 do
                assert(row["Material" .. field .. "_Id"]:ToString() == "None"
                    or row["Material" .. field .. "_Count"] == 0, "conversion_extra_cost")
            end
        end
    end
    return result
end
function M:ranks(parameter)
    local operation = self:object("/Script/Pal.Default__PalCharacterStatusOperation")
    local result = {}
    for stat = 1, 4 do result[stat] = Plan.integer(operation:GetCurrentStatusRank(parameter, stat), 0, 255) end
    return result
end
function M:read(session)
    assert(valid(session.Menu) and valid(session.Panel), "menu_closed")
    assert(session.Panel["Is Upgrade"] == true, "reset_mode")
    local controller = session.Menu:GetOwningPlayer()
    assert(valid(controller) and controller:HasAuthority(), "host_only")
    local handle = session.Menu.CurrentHandle
    assert(valid(handle), "pal_unavailable")
    local parameter = handle:TryGetIndividualParameter()
    assert(valid(parameter) and name(parameter) == name(session.Panel.CurrentIndividualParam), "pal_changed")
    local inventory = controller.PlayerState:GetInventoryData()
    assert(valid(inventory), "inventory_unavailable")
    local sources = self:sources(controller, inventory, session.Menu)
    local slots, stock = scan(sources)
    local accessible = self:accessible(session.Menu)
    for _, id in ipairs(Plan.items) do assert(stock[id] == accessible[id], "inventory_scope_mismatch") end
    local manager = self:object("/Script/Pal.Default__PalUtility"):GetItemIDManager(controller)
    local limits = {}
    for _, id in ipairs(Plan.items) do
        local data = manager:GetStaticItemData(self.api.FName(id))
        assert(valid(data), "soul_definition_unavailable")
        limits[id] = Plan.integer(data.MaxStackCount, 1, 1000000000)
    end
    return { Session = session, Handle = handle, HandleKey = name(handle), Parameter = parameter,
        Controller = controller, Sources = sources, Slots = slots, Stock = stock,
        Limits = limits, Current = self:ranks(parameter), Schedule = self:schedule(session.Menu) }
end
function M:check(state)
    assert(valid(state.Controller) and state.Controller:HasAuthority(), "host_only")
    assert(valid(state.Handle) and name(state.Session.Menu.CurrentHandle) == state.HandleKey, "pal_changed")
    local slots, stock = scan(state.Sources)
    assert(#slots == #state.Slots, "inventory_changed")
    for i, slot in ipairs(slots) do
        local before = state.Slots[i]
        assert(slot.Key == before.Key and slot.Item == before.Item and slot.Count == before.Count, "inventory_changed")
    end
    local current, accessible = self:ranks(state.Parameter), self:accessible(state.Session.Menu)
    for i = 1, 4 do assert(current[i] == state.Current[i], "rank_changed") end
    for _, id in ipairs(Plan.items) do assert(stock[id] == accessible[id], "inventory_scope_mismatch") end
end
local function refresh(object)
    object:OnRep_ItemId()
    object:OnRep_StackCount()
end
function M:apply(state, changes)
    state.Touched = {}
    for _, change in ipairs(changes) do
        local object = state.Slots[change.Index].Object
        state.Touched[change.Index] = true -- Journal BEFORE either field write.
        object.ItemId.StaticId = self.api.FName(change.Item)
        object.StackCount = change.Count
    end
    for index in pairs(state.Touched) do refresh(state.Slots[index].Object) end
end
function M:checkPrepared(state, expected)
    local _, stock = scan(state.Sources)
    local accessible = self:accessible(state.Session.Menu)
    for _, id in ipairs(Plan.items) do
        assert(stock[id] == expected[id] and accessible[id] == expected[id], "conversion_verification_failed")
    end
end
function M:checkCost(state, targets)
    local ranks, expected = {}, Plan.cost(state.Current, targets, state.Schedule)
    for i = 1, 4 do if targets[i] > state.Current[i] then ranks[i] = targets[i] end end
    -- Cross-check the native aggregate bill before issuing the original request.
    local out = {}
    self:object("/Script/Pal.Default__PalCharacterStatusOperation")
        :GetRequiredItemCountForCharacterStatus(state.Session.Menu, state.Parameter, ranks, out)
    -- UE4SS puts an out MapProperty under its reflected parameter name.
    -- The outer table's key is 'RequiredItems', not a soul item ID.
    local required = out.RequiredItems
    assert(type(required) == "table", "native_cost_output_unavailable")
    local actual = Plan.copy({})
    for id, count in pairs(required) do
        id = unwrap(id) -- Out-map keys are RemoteUnrealParam wrappers in UE4SS.
        local item = type(id) == "string" and id or id:ToString()
        assert(Plan.weight[item], "native_cost_unsupported")
        actual[item] = Plan.integer(unwrap(count), 0, 1000000000)
    end
    for _, id in ipairs(Plan.items) do assert(actual[id] == expected[id], "native_cost_mismatch") end
end
function M:upgrade(state, targets)
    local ranks = {}
    for i = 1, 4 do if targets[i] > state.Current[i] then ranks[i] = targets[i] end end
    -- Keeps the original owned-Pal checks, stat effects, save updates, result and sound.
    state.Session.Menu["Invoke Rankup"](state.Session.Menu, ranks)
end
function M:verify(state, targets, remaining)
    local current = self:ranks(state.Parameter)
    for stat = 1, 4 do assert(current[stat] == targets[stat], "native_upgrade_failed") end
    self:checkPrepared(state, remaining)
end
function M:restore(state)
    assert(valid(state.Parameter), "rollback_parameter_unavailable")
    for index, slot in ipairs(state.Slots) do
        if Plan.weight[slot.Item] or (state.Touched and state.Touched[index]) then
            assert(valid(slot.Object), "rollback_slot_unavailable")
            slot.Object.ItemId.StaticId = self.api.FName(slot.Item)
            slot.Object.StackCount = slot.Count
        end
    end
    local ranks = self:ranks(state.Parameter)
    local changed = false
    for i, field in ipairs(rankFields) do
        if ranks[i] ~= state.Current[i] then
            state.Parameter.SaveParameter[field] = state.Current[i]
            state.Parameter.SaveParameterMirror[field] = state.Current[i]
            changed = true
        end
    end
    if changed then state.Parameter:OnRep_SaveParameter() end
    for index, slot in ipairs(state.Slots) do
        if Plan.weight[slot.Item] or (state.Touched and state.Touched[index]) then refresh(slot.Object) end
    end
    local restored, stock = scan(state.Sources)
    for i, slot in ipairs(restored) do
        assert(slot.Item == state.Slots[i].Item and slot.Count == state.Slots[i].Count, "rollback_inventory_mismatch")
    end
    for _, id in ipairs(Plan.items) do assert(stock[id] == state.Stock[id], "rollback_value_mismatch") end
    for i, rank in ipairs(self:ranks(state.Parameter)) do assert(rank == state.Current[i], "rollback_rank_mismatch") end
end
return M
