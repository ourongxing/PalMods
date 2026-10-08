local Util = require("BetterWorkbench.Util")
local Book = {}
Book.__index = Book

-- Canonical schema, independent of UE structs and DataTable storage.
-- Source adapters provide the current recipe identities / base quantities.
-- Nonlinear research rounding must use Context.materialsForBatches instead of
-- storing a one-batch rounded UI quantity here and multiplying it later.
function Book.new(recipes, maxCount, preferred)
    assert(type(recipes) == "table", "recipes must be a table")
    local self = setmetatable({ recipes = {}, outputs = {}, preferred = Util.copy(preferred or {}) }, Book)
    for _, id in ipairs(Util.keys(recipes)) do
        local row = recipes[id]
        assert(type(id) == "string" and id ~= "" and type(row) == "table", "invalid recipe")
        assert(type(row.OutputItem) == "string" and row.OutputItem ~= "", "invalid OutputItem")
        Util.integer(row.OutputAmount, 1, maxCount, "OutputAmount")
        assert(type(row.Materials) == "table", "invalid Materials")
        local materials = {}
        for item, amount in pairs(row.Materials) do
            assert(type(item) == "string" and item ~= "", "invalid material ID")
            materials[item] = Util.integer(amount, 1, maxCount, "material amount")
        end
        local work = row.WorkAmount or 0
        assert(type(work) == "number" and work >= 0 and work < math.huge, "invalid WorkAmount")
        local copy = Util.copy(row)
        copy.Materials, copy.WorkAmount = materials, work
        self.recipes[id] = copy
        self.outputs[row.OutputItem] = self.outputs[row.OutputItem] or {}
        table.insert(self.outputs[row.OutputItem], id)
    end
    return self
end

function Book:get(id)
    return Util.copy(self.recipes[id])
end

function Book:forOutput(item, stationRecipes)
    local all = self.outputs[item] or {}
    local candidate, count = nil, 0
    for _, id in ipairs(all) do
        if stationRecipes == nil or stationRecipes[id] == true then
            candidate, count = id, count + 1
        end
    end
    local preferred = self.preferred[item]
    if preferred then
        local row = self.recipes[preferred]
        if row and row.OutputItem == item then
            if stationRecipes ~= nil and stationRecipes[preferred] ~= true then
                return nil, nil, "cross_station_recipe"
            end
            return preferred, Util.copy(row)
        end
        return nil, nil, "invalid_preference"
    end
    if count == 1 then return candidate, Util.copy(self.recipes[candidate]) end
    if count > 1 then return nil, nil, "ambiguous_recipe" end
    if #all > 0 then return nil, nil, "cross_station_recipe" end
    return nil, nil, "no_recipe"
end

return Book
