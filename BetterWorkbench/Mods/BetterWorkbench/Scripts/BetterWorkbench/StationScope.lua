-- Copies only verified TArray<FName> results while their native call is alive.
-- No ForEach, structure fields, retained native pointers, or native writes.
local Scope = {}

function Scope.copyNames(array, limit)
    limit = limit or 4096
    assert(array:type() == "TArray", "station result is not a TArray")
    local count, capacity = array:GetArrayNum(), array:GetArrayMax()
    assert(type(count) == "number" and count % 1 == 0 and count >= 0 and count <= limit,
        "invalid station recipe count")
    assert(type(capacity) == "number" and capacity % 1 == 0 and capacity >= count,
        "invalid station recipe capacity")
    local names = {}
    for index = 1, count do
        -- UE4SS index access can grow an out-of-range array, even on a read.
        -- Recheck length before indexing; callbacks execute synchronously.
        assert(array:GetArrayNum() == count, "station recipe list changed during copy")
        local name = array[index]
        assert(name:type() == "FName", "station recipe element is not an FName")
        local id = name:ToString()
        assert(type(id) == "string" and id ~= "" and id ~= "None" and #id <= 256,
            "invalid station recipe ID")
        names[id] = true
    end
    assert(array:GetArrayNum() == count, "station recipe list changed during copy")
    return names, count
end

return Scope
