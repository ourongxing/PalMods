-- Copies borrowed UI material data synchronously. Never retains native values.
local View = {}
local Util = require("BetterWorkbench.Util")
local expected = "ScriptStruct /Script/Pal.PalStaticItemIdAndNum"

function View.copy(array)
    assert(array:type() == "TArray", "material result is not a TArray")
    local count, capacity = array:GetArrayNum(), array:GetArrayMax()
    Util.integer(count, 0, 64, "material count")
    assert(type(capacity) == "number" and capacity % 1 == 0 and capacity >= count,
        "invalid material capacity")
    local costs = {}
    for index = 1, count do
        assert(array:GetArrayNum() == count, "materials changed during copy")
        local entry = array[index] -- bounded index, not UE4SS TArray.ForEach
        assert(entry:type() == "UScriptStruct" and entry:GetFullName() == expected,
            "unexpected material structure")
        -- IsValid validates metadata only; require a live property/data mapping.
        assert(entry:IsMappedToObject() and entry:IsMappedToProperty(), "unmapped material structure")
        assert(entry:GetStructAddress() > 0 and entry:GetPropertyAddress() > 0, "null material mapping")
        local name = entry.StaticItemId
        assert(name:type() == "FName", "material item is not an FName")
        local id, amount = name:ToString(), entry.Num
        assert(type(id) == "string" and id ~= "" and #id <= 256, "invalid material ID")
        Util.integer(amount, 0, 1000000000, "material amount")
        if id ~= "None" and amount > 0 then
            costs[id] = Util.integer((costs[id] or 0) + amount, 1, 1000000000, "material total")
        end
    end
    assert(array:GetArrayNum() == count, "materials changed during copy")
    return costs
end

return View
