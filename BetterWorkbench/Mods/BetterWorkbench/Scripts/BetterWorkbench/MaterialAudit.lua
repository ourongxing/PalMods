-- Observational only. Loaded-world slot changes are NOT a craft inventory pool.
local Util = require("BetterWorkbench.Util")
local Normalizer = require("BetterWorkbench.RecipeNormalizer")
local Audit = {}
Audit.__index = Audit

local function valid(value)
    local ok, result = pcall(function() return value ~= nil and value:IsValid() end)
    return ok and result == true
end

local function name(value)
    if type(value) == "string" then return value end
    return value:ToString()
end

local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

local function identifier(object)
    return tostring(object:GetAddress())
end

function Audit.new(api, log, options)
    options = options or {}
    return setmetatable({ api = api, log = log, recipes = {}, uiCosts = {}, pending = {},
        maxSlots = Util.integer(options.MaxSlots or 20000, 1, 100000, "MaxSlots"),
        maxEvents = Util.integer(options.MaxEvents or 24, 1, 100, "MaxEvents"),
        recipeCount = 0, events = 0, busy = false, errors = {}, tracked = {}, finishes = {} }, Audit)
end

function Audit:errorOnce(key, err)
    if self.errors[key] then return end
    self.errors[key] = true
    self.log("AUDIT unavailable " .. key .. " " .. tostring(err):gsub("[\r\n]", " "):sub(1, 200))
end

function Audit:snapshot()
    assert(type(self.api.FindAllOf) == "function", "FindAllOf unavailable")
    local slots = self.api.FindAllOf("PalItemSlot")
    assert(type(slots) == "table", "no loaded item slots found")
    local result = { Slots = {}, Failures = 0, Count = 0, Complete = true }
    local seen = {}
    for _, slot in ipairs(slots) do
        if valid(slot) then
            local ok, err = pcall(function()
                local key = identifier(slot)
                if seen[key] then return end
                seen[key] = true
                result.Count = result.Count + 1
                if result.Count > self.maxSlots then result.Complete = false; return end
                local item = name(slot.ItemId.StaticId)
                local amount = Util.integer(slot.StackCount, 0, 1000000000, "slot count")
                local outer = slot:GetOuter()
                assert(valid(outer), "slot owner unavailable")
                result.Slots[key] = { Item = item, Amount = amount,
                    OwnerId = identifier(outer), Owner = outer:GetFullName() }
            end)
            if not ok then
                result.Failures = result.Failures + 1
                result.Complete = false
                result.FirstError = result.FirstError or tostring(err)
            end
        else
            result.Failures = result.Failures + 1
            result.Complete = false
            result.FirstError = result.FirstError or "invalid slot during snapshot"
        end
    end
    return result
end

function Audit.diff(before, after)
    local rows, totals, uncertain = {}, {}, 0
    for _, key in ipairs(Util.keys(before.Slots)) do
        local old, new = before.Slots[key], after.Slots[key]
        if not new or old.OwnerId ~= new.OwnerId then
            uncertain = uncertain + 1 -- disappeared/reused pointers are not material debits
        elseif old.Item ~= new.Item or old.Amount ~= new.Amount then
            rows[#rows + 1] = { Slot = key, Owner = old.Owner, Before = old, After = new }
            if old.Item ~= "None" then totals[old.Item] = (totals[old.Item] or 0) - old.Amount end
            if new.Item ~= "None" then totals[new.Item] = (totals[new.Item] or 0) + new.Amount end
        end
    end
    for key in pairs(after.Slots) do
        if not before.Slots[key] then uncertain = uncertain + 1 end
    end
    return { Changes = rows, Totals = totals, UncertainSlots = uncertain,
        Complete = before.Complete and after.Complete and uncertain == 0 }
end

function Audit:materials(array)
    local result, count = {}, 0
    array:ForEach(function(_, wrapped)
        count = count + 1
        assert(count <= 64, "material array limit exceeded")
        local entry = unwrap(wrapped)
        local item = name(entry.StaticItemId)
        local amount = Util.integer(entry.Num, 0, 1000000000, "material array count")
        if item ~= "None" and amount > 0 then result[item] = (result[item] or 0) + amount end
    end)
    return result
end

function Audit:cache(method, phase, args)
    if phase ~= "POST" and method ~= "Setup" then return end
    if method == "BP_FindRow" and args.bResult == true and args.ReturnValue then
        local id = name(args.RowName)
        if self.recipeCount >= 2048 and not self.recipes[id] then return end
        local row = args.ReturnValue
        local normalized = Normalizer.fromFlat(row, {
            OutputItem = name(row.Product_Id), OutputAmount = row.Product_Count,
            WorkAmount = row.WorkAmount,
        }, name)
        if not self.recipes[id] then self.recipeCount = self.recipeCount + 1 end
        self.recipes[id] = normalized -- refreshes changes made by other mods
    elseif method == "Setup" and args.RecipeID and args.MatInfo then
        self.uiCosts[name(args.RecipeID)] = self:materials(args.MatInfo)
    elseif method == "CollectLocalPlayerControllableItemInfos" and args.OutItemInfos then
        -- Captured native view only; not used as authoritative server inventory.
        local view = self:materials(args.OutItemInfos)
        self.lastNativeView = view
    end
end

local function costs(map)
    local parts = {}
    for _, id in ipairs(Util.keys(map)) do parts[#parts + 1] = id .. "=" .. map[id] end
    return table.concat(parts, ",")
end

function Audit:event(method, phase, object)
    if not valid(object) then return end
    local transaction = method == "ChangeRecipe_ServerInternal" or method == "Cancel_ServerInternal"
        or method == "PickupProduct_ServerInternal" or method == "OnFinishWorkInServer"
    if not transaction then return end
    local objectId = identifier(object)
    local key = method .. ":" .. objectId
    if phase == "CALL" then
        if self.events >= self.maxEvents then return end
        if method == "ChangeRecipe_ServerInternal" then
            self.tracked[objectId], self.finishes[objectId] = true, 0
        elseif not self.tracked[objectId] then
            return -- only audit tasks whose creation was observed in this session
        elseif method == "OnFinishWorkInServer" then
            if (self.finishes[objectId] or 0) >= 2 then return end
            self.finishes[objectId] = (self.finishes[objectId] or 0) + 1
        end
        self.events = self.events + 1
        local snapshot = self:snapshot()
        self.pending[key] = self.pending[key] or {}
        table.insert(self.pending[key], { Snapshot = snapshot, Event = self.events })
        self.log("AUDIT BEGIN event=" .. self.events .. " method=" .. method
            .. " scope=loaded_world_slots count=" .. snapshot.Count .. " complete=" .. tostring(snapshot.Complete))
        if snapshot.FirstError then self:errorOnce("slot-read", snapshot.FirstError) end
        return
    end
    local stack = self.pending[key]
    if not stack or #stack == 0 then return end
    local pending = table.remove(stack)
    local after = self:snapshot()
    local delta = Audit.diff(pending.Snapshot, after)
    local recipeId = name(object.CurrentRecipeId)
    if recipeId == "None" then self.tracked[objectId] = nil end
    self.log("AUDIT END event=" .. pending.Event .. " method=" .. method .. " recipe=" .. recipeId
        .. " requested=" .. tostring(object.RequestedProductNum) .. " remaining=" .. tostring(object.RemainProductNum)
        .. " complete=" .. tostring(delta.Complete) .. " changed=" .. #delta.Changes
        .. " uncertain=" .. delta.UncertainSlots .. " NET=" .. costs(delta.Totals))
    for index, change in ipairs(delta.Changes) do
        if index > 64 then self.log("AUDIT slot-detail truncated"); break end
        self.log("AUDIT SLOT event=" .. pending.Event .. " slot=" .. change.Slot
            .. " before=" .. change.Before.Item .. ":" .. change.Before.Amount
            .. " after=" .. change.After.Item .. ":" .. change.After.Amount
            .. " owner=" .. change.Owner)
    end
    local recipe = self.recipes[recipeId]
    if recipe then
        self.log("AUDIT RECIPE id=" .. recipeId .. " output=" .. recipe.OutputItem .. ":" .. recipe.OutputAmount
            .. " work=" .. recipe.WorkAmount .. " RAW=" .. costs(recipe.Materials))
    end
    if self.uiCosts[recipeId] then self.log("AUDIT UI id=" .. recipeId .. " materials=" .. costs(self.uiCosts[recipeId])) end
end

function Audit:observe(method, phase, object, args)
    if self.busy then return end -- read-only native getters may re-enter a hook
    self.busy = true
    local ok, err = pcall(self.cache, self, method, phase, args)
    if not ok then self:errorOnce("cache-" .. method, err) end
    ok, err = pcall(self.event, self, method, phase, object)
    if not ok then self:errorOnce("event-" .. method .. "-" .. phase, err) end
    self.busy = false
end

return Audit
