local Util = require("BetterWorkbench.Util")
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(snapshot, maxCount)
    assert(type(snapshot) == "table", "inventory snapshot must be a table")
    local self = setmetatable({ stock = {}, generated = {}, consumed = {} }, Inventory)
    for item, amount in pairs(snapshot) do
        assert(type(item) == "string" and item ~= "", "invalid inventory item")
        self.stock[item] = Util.integer(amount, 0, maxCount, "inventory count")
    end
    return self
end

-- Only real stock goes into consumed. Virtual intermediate surplus is never
-- deducted from storage and is never granted as a world item by this module.
function Inventory:take(item, amount)
    local real = math.min(self.stock[item] or 0, amount)
    self.stock[item] = (self.stock[item] or 0) - real
    self.consumed[item] = (self.consumed[item] or 0) + real
    local virtual = math.min(self.generated[item] or 0, amount - real)
    self.generated[item] = (self.generated[item] or 0) - virtual
    return amount - real - virtual
end

function Inventory:addVirtual(item, amount, maxCount)
    local total = (self.generated[item] or 0) + amount
    Util.integer(total, 0, maxCount, "virtual surplus")
    self.generated[item] = total
end

return Inventory
