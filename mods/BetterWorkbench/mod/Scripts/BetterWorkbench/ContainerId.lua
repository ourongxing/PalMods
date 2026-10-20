local M = {}
-- PalContainerId wraps a Guid; it is not itself an FGuid. Discover the exact
-- wrapper member from reflection before constructing an engine argument.
function M.factory(api)
    local struct = api.StaticFindObject("/Script/Pal.PalContainerId")
    assert(struct and struct:IsValid(), "container ID type unavailable")
    local member
    struct:ForEachProperty(function(property)
        local ok, inner = pcall(function() return property:GetStruct() end)
        if ok and inner and inner:IsValid() and inner:GetFName():ToString() == "Guid" then
            assert(not member, "ambiguous container ID layout")
            member = property:GetFName():ToString()
        end
    end)
    assert(member, "container ID Guid field unavailable")
    return function(guid) return { [member] = guid } end
end
return M
