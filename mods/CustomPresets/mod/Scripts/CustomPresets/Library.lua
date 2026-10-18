local t = require('CustomPresets.I18n').text
local Store = require('CustomPresets.Store')
local Schema = require('CustomPresets.Schema')
local M = {}
local catalogueSchema = {{'Ids', 'string'}, {'NextId', 'number'}}
local nameSchema = {{'Name', 'string'}}
local names = {[1]='easy', [2]='normal', [3]='hard', [4]='hardcore', [5]='custom'}
function M.new(directory, kind)
    kind = kind or "world"
    assert(kind == "world" or kind == "character", "Invalid preset kind")
    local schema = Schema[kind]
    local prefix = kind == "character" and "character-" or ""
    local self = {}
    local function index()
        local raw = Store.read(directory .. prefix .. 'catalogue.preset', catalogueSchema) or {Ids='', NextId=1}
        assert(raw.NextId >= 1 and raw.NextId < 1000000000 and raw.NextId % 1 == 0, 'Invalid preset sequence')
        local ids, seen = {}, {}
        assert(raw.Ids == '' or raw.Ids:match('^%d+[,0-9]*$'), 'Invalid preset catalogue')
        for text in raw.Ids:gmatch('[^,]+') do
            local id = tonumber(text)
            assert(id and id >= 1 and id < raw.NextId and id % 1 == 0 and not seen[id], 'Invalid preset id')
            seen[id] = true; ids[#ids + 1] = id
        end
        return raw, ids, seen
    end
    local function filepath(selection)
        assert(selection and (selection.Kind == 'builtin' or selection.Kind == 'user'), 'No current preset')
        assert(type(selection.Id) == 'number' and selection.Id >= 1 and selection.Id % 1 == 0, 'Invalid preset id')
        if selection.Kind == 'builtin' then assert(names[selection.Id], 'Invalid original preset') end
        return directory .. prefix .. selection.Kind .. '-' .. selection.Id .. '.preset'
    end
    local function snapshot(values)
        local copy = Store.decode(Store.encode(values, schema), schema)
        if kind == "world" then copy.Difficulty = 5 end
        return copy
    end
    function self:list()
        local _, ids = index()
        local result = {}
        for _, id in ipairs(ids) do result[#result + 1] = {Kind='user', Id=id} end
        return result
    end
    function self:name(selection)
        if selection.Kind == 'builtin' then return t(assert(names[selection.Id])) end
        local saved = Store.read(filepath(selection) .. '.name.preset', nameSchema)
        -- Ignore address labels accidentally persisted by 0.3.16's tostring.
        if saved and saved.Name:match('^FString: %x+$') then saved = nil end
        return saved and saved.Name or t('legacy', selection.Id)
    end
    function self:load(selection)
        if selection.Kind == 'builtin' then return nil end
        if selection.Kind == 'user' then
            local _, _, seen = index()
            assert(seen[selection.Id], 'Preset was deleted')
        end
        local values = Store.read(filepath(selection), schema)
        return values
    end
    function self:save(selection, values)
        assert(selection.Kind == 'user', 'Original presets are read-only; add a new user preset instead')
        local _, _, seen = index()
        assert(seen[selection.Id], 'Cannot overwrite a deleted preset')
        Store.write(filepath(selection), snapshot(values), schema)
    end
    function self:add(values, name)
        assert(type(name) == 'string', 'Preset name required')
        name = name:match('^%s*(.-)%s*$')
        local length = utf8.len(name)
        assert(length and length >= 1 and length <= 30 and not name:find('%c'), t('invalid_name'))
        assert(not name:match('^FString: %x+$'), 'Invalid string address label')
        local raw, ids = index()
        local selection = {Kind='user', Id=raw.NextId}
        -- Do not overwrite an orphan left by an interrupted catalogue write.
        while true do
            local file = io.open(filepath(selection), 'rb')
            if not file then break end
            file:close(); selection.Id = selection.Id + 1
        end
        Store.write(filepath(selection), snapshot(values), schema)
        Store.write(filepath(selection) .. '.name.preset', {Name=name}, nameSchema)
        ids[#ids + 1] = selection.Id
        Store.write(directory .. prefix .. 'catalogue.preset', {Ids=table.concat(ids, ','), NextId=selection.Id+1}, catalogueSchema)
        return selection
    end
    function self:previewPath(selection)
        assert(kind == 'character' and selection.Kind == 'user', 'Only character presets have previews')
        return filepath(selection) .. '.preview-v4.png'
    end
    function self:hasPreview(selection)
        local file = io.open(self:previewPath(selection), 'rb')
        if not file then return false end
        local header = file:read(8); file:close()
        return header == '\137PNG\13\10\26\10'
    end
    function self:invalidatePreview(selection)
        local path = self:previewPath(selection)
        local file = io.open(path,'rb')
        if file then
            file:close(); os.remove(path..'.bak')
            assert(os.rename(path,path..'.bak'))
        end
    end
    function self:remove(selection)
        assert(selection.Kind == 'user', 'Original presets cannot be deleted')
        local raw, ids, seen = index()
        assert(seen[selection.Id], 'Preset was already deleted')
        local remaining = {}
        for _, id in ipairs(ids) do if id ~= selection.Id then remaining[#remaining+1] = id end end
        Store.write(directory .. prefix .. 'catalogue.preset', {Ids=table.concat(remaining, ','), NextId=raw.NextId}, catalogueSchema)
        -- Catalogue commit is authoritative; a failed archive cannot resurrect it.
        os.rename(filepath(selection), filepath(selection) .. '.deleted')
        if kind == 'character' then os.rename(self:previewPath(selection), self:previewPath(selection)..'.deleted') end
    end
    return self
end
return M
