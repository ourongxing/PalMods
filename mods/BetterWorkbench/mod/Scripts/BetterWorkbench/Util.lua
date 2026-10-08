local M = {}

function M.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = M.copy(v) end
    return result
end

function M.integer(value, min, max, label)
    assert(type(value) == "number" and value == value and value >= min
        and value <= max and value % 1 == 0, "invalid " .. label)
    return value
end

function M.keys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function M.rows(map)
    local rows = {}
    for _, key in ipairs(M.keys(map)) do
        if map[key] > 0 then rows[#rows + 1] = { Item = key, Amount = map[key] } end
    end
    return rows
end

return M
