local Store = require('CustomPresets.Store')
local Schema = require('CustomPresets.Schema')
local function get(o, path)
    for part in path:gmatch('[^.]+') do o = o[part] end
    return o
end
local function set(o, path, value)
    local parent, leaf = path:match('^(.*)%.([^.]*)$')
    if parent then o = get(o, parent) else leaf = path end
    o[leaf] = value
end
local function capture(o, kind)
    local result = {}
    for _, field in ipairs(Schema[kind]) do
        local value = get(o, field[1])
        if field[2] == 'name' then value = value:ToString()
        elseif field[2] == 'string' and type(value) ~= 'string' then value = value:ToString() end
        result[field[1]] = value
    end
    return result
end
local function apply(o, kind, values)
    -- Validate the entire preset before touching the editor.
    Store.encode(values, Schema[kind])
    local original = capture(o, kind)
    local ok, err = pcall(function()
        for _, field in ipairs(Schema[kind]) do
            local value = values[field[1]]
            if field[2] == 'name' then value = FName(value) end
            set(o, field[1], value)
        end
    end)
    if not ok then
        for _, field in ipairs(Schema[kind]) do
            local value = original[field[1]]
            pcall(set, o, field[1], field[2] == 'name' and FName(value) or value)
        end
        error(err)
    end
end
return {capture = capture, apply = apply}
