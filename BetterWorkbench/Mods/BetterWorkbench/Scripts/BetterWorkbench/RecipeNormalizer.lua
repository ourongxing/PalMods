local Util = require("BetterWorkbench.Util")
local M = {}

-- Observed in an installed Lua mod: Product_Count and MaterialN_Id/Count.
-- This is a pure conversion utility, not an assertion of live API compatibility.
-- Adapter supplies verified output identity and EFFECTIVE work/cost data.
function M.fromFlat(row, metadata, nameOf)
    assert(type(metadata) == "table", "verified recipe metadata required")
    assert(type(metadata.OutputItem) == "string" and metadata.OutputItem ~= "", "verified OutputItem required")
    assert(type(metadata.WorkAmount) == "number" and metadata.WorkAmount >= 0
        and metadata.WorkAmount < math.huge, "verified WorkAmount required")
    local output = Util.integer(metadata.OutputAmount or row.Product_Count, 1, 1000000000, "flat output count")
    nameOf = nameOf or function(value)
        assert(type(value) == "string", "FName conversion function required")
        return value
    end
    local materials = {}
    for index = 1, 5 do
        local amount = row["Material" .. index .. "_Count"]
        Util.integer(amount, 0, 1000000000, "flat material amount")
        if amount ~= 0 then
            local item = nameOf(row["Material" .. index .. "_Id"])
            assert(type(item) == "string" and item ~= "", "invalid flat material ID")
            -- Cooked rows can retain nonzero counts in slots with FName None.
            -- The item identity marks an unused slot, regardless of its count.
            if item ~= "None" then
                materials[item] = Util.integer((materials[item] or 0) + amount, 1, 1000000000, "flat total")
            end
        end
    end
    return {
        OutputItem = metadata.OutputItem,
        OutputAmount = output,
        WorkAmount = metadata.WorkAmount,
        Materials = materials,
        Expand = metadata.Expand,
    }
end

return M
