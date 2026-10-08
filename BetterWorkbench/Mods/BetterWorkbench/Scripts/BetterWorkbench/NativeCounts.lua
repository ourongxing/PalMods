-- Local UI diagnostics only. These two queries are NOT server authority and
-- must not be summed until their overlap / native craft scope is verified.
local Counts = {}
Counts.__index = Counts
local methods = {
    CountLocalPlayerInventoryItemNum64 = "PlayerInventory",
    CountLocalPlayerInsideBaseCampItemNum64 = "InsideBase",
}

function Counts.new(class, nameFactory, maxReads)
    maxReads = maxReads or 6
    assert(type(maxReads) == "number" and maxReads % 1 == 0 and maxReads >= 1
        and maxReads <= 48, "invalid inventory sample limit")
    -- Installed UE4SS exposes FName as callable userdata (__call), not a Lua function.
    assert(type(nameFactory) == "function" or type(nameFactory) == "userdata"
        or type(nameFactory) == "table", "FName constructor unavailable")
    local verified = {}
    class:ForEachFunction(function(func)
        local name = func:GetFName():ToString()
        if not methods[name] then return end
        local fields, order = {}, {}
        func:ForEachProperty(function(property)
            local label = property:GetFName():ToString()
            fields[label] = property:GetFullName():match("^(%S+)")
            order[#order + 1] = label
        end)
        local flags = func:GetFunctionFlags()
        verified[name] = fields.WorldContextObject == "ObjectProperty"
            and fields.StaticItemId == "NameProperty" and fields.ReturnValue == "Int64Property"
            and table.concat(order, ",") == "WorldContextObject,StaticItemId,ReturnValue"
            and flags & 0x00002000 ~= 0 and flags & 0x10000000 ~= 0 -- static + BlueprintPure
    end)
    for name in pairs(methods) do assert(verified[name], "unverified count function: " .. name) end
    local utility = class:GetCDO()
    assert(utility:IsValid(), "item utility default object unavailable")
    return setmetatable({ utility = utility, nameFactory = nameFactory, reads = 0,
        maxReads = maxReads, busy = false, disabled = false }, Counts)
end

function Counts:read(context, itemIds)
    if self.disabled or self.busy or self.reads >= self.maxReads then return nil end
    self.busy = true
    local ok, result = pcall(function()
        assert(context:IsValid() and self.utility:IsValid(), "inventory query context unavailable")
        assert(#itemIds >= 1 and #itemIds <= 8, "inventory query item limit")
        self.reads = self.reads + 1
        local counts = { PlayerInventory = {}, InsideBase = {} }
        for _, id in ipairs(itemIds) do
            assert(type(id) == "string" and id ~= "" and id ~= "None", "invalid inventory item ID")
            local name = self.nameFactory(id)
            for method, scope in pairs(methods) do
                local amount = self.utility[method](self.utility, context, name)
                assert(type(amount) == "number" and amount % 1 == 0 and amount >= 0
                    and amount <= 1000000000, "invalid native inventory count")
                counts[scope][id] = amount
            end
        end
        return counts
    end)
    self.busy = false
    if not ok then self.disabled = true; return nil, result end
    return result
end

return Counts
