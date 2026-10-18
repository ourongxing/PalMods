local M = {}
local function escape(s)
    return (s:gsub('[^%w%._%- ]', function(c) return string.format('%%%02X', c:byte()) end))
end
local function unescape(s)
    assert(not s:gsub('%%%x%x', ''):find('%%'), 'Invalid escape')
    return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end
function M.encode(values, schema)
    local lines = {'MorePresets:1'}
    for _, field in ipairs(schema) do
        local value, kind = values[field[1]], field[2]
        assert(type(value) == (kind == 'name' and 'string' or kind), 'Invalid ' .. field[1])
        if kind == 'number' then assert(value == value and math.abs(value) < math.huge, 'Nonfinite number') end
        lines[#lines + 1] = field[1] .. '=' .. escape(tostring(value))
    end
    return table.concat(lines, '\n') .. '\n'
end
function M.decode(data, schema, limit)
    assert(#data <= (limit or 65536) and data:match('^MorePresets:1\n'), 'Invalid preset format')
    local raw, result = {}, {}
    for line in data:sub(15):gmatch('[^\n]+') do
        local key, value = line:match('^([%w%._]+)=(.*)$')
        assert(key and not raw[key], 'Invalid or duplicate field')
        raw[key] = unescape(value)
    end
    for _, field in ipairs(schema) do
        local value = assert(raw[field[1]], 'Missing ' .. field[1])
        if field[2] == 'number' then
            value = assert(tonumber(value), 'Invalid number')
            assert(value == value and math.abs(value) < math.huge, 'Nonfinite number')
        elseif field[2] == 'boolean' then
            assert(value == 'true' or value == 'false', 'Invalid boolean')
            value = value == 'true'
        end
        result[field[1]] = value
    end
    return result
end
function M.read(path, schema, limit)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local data = file:read((limit or 65536)+1); file:close()
    return M.decode(data, schema, limit)
end
function M.write(path, values, schema, backup, limit)
    local data = M.encode(values, schema)
    assert(#data <= (limit or 65536), 'Preset data exceeds size limit')
    backup = backup or path .. '.bak'
    local file = assert(io.open(path .. '.tmp', 'wb'))
    assert(file:write(data)); assert(file:close())
    -- Preserve the last valid copy if replacement is interrupted on Windows.
    os.remove(backup)
    local existing = io.open(path, 'rb')
    if existing then existing:close(); assert(os.rename(path, backup)) end
    local ok, err = os.rename(path .. '.tmp', path)
    if not ok then os.rename(backup, path); error(err) end
end
return M
