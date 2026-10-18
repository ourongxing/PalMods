local t = require('CustomPresets.I18n').text
local Store = require('CustomPresets.Store')
local Schema = require('CustomPresets.Schema')
local M = {}
local names = {[1]='easy',[2]='normal',[3]='hard',[4]='hardcore',[5]='custom'}
local function validateName(name)
    assert(type(name)=='string','Preset name required')
    name=name:match('^%s*(.-)%s*$')
    local length=utf8.len(name)
    assert(length and length>=1 and length<=30 and not name:find('%c'),t('invalid_name'))
    assert(not name:match('^FString: %x+$'),'Invalid string address label')
    return name
end
function M.new(directory, kind)
    kind=kind or 'world'
    assert(kind=='world' or kind=='character','Invalid preset kind')
    local schema=Schema[kind]
    local fields={{'Name','string'}}
    for _,field in ipairs(schema) do fields[#fields+1]=field end
    local backups=directory..'../backups/'
    local self={}
    local function path(id)
        assert(type(id)=='number' and id>=1 and id%1==0 and id<1000000000,'Invalid preset id')
        return directory..kind..'-'..id..'.preset'
    end
    local function ids()
        local result={}
        for filename in CustomPresetsNativeListFiles(directory):gmatch('[^\n]+') do
            local id=filename:match('^'..kind..'%-(%d+)%.preset$')
            if id and tonumber(id)>0 and tonumber(id)<1000000000 then result[#result+1]=tonumber(id) end
        end
        table.sort(result)
        return result
    end
    local function entry(selection)
        assert(selection and selection.Kind=='user','Original presets are read-only')
        return assert(Store.read(path(selection.Id),fields),'Preset was deleted')
    end
    local function write(id,name,values)
        local flat={Name=name}
        for _,field in ipairs(schema) do flat[field[1]]=values[field[1]] end
        Store.write(path(id),flat,fields,backups..kind..'-'..id..'.preset.bak')
    end
    local function snapshot(values)
        local copy=Store.decode(Store.encode(values,schema),schema)
        if kind=='world' then copy.Difficulty=5 end
        return copy
    end
    function self:list()
        local result={}
        for _,id in ipairs(ids()) do result[#result+1]={Kind='user',Id=id} end
        return result
    end
    function self:name(selection)
        if selection.Kind=='builtin' then return t(assert(names[selection.Id])) end
        return entry(selection).Name
    end
    function self:load(selection)
        if selection.Kind=='builtin' then return nil end
        return Store.decode(Store.encode(entry(selection),schema),schema)
    end
    function self:save(selection,values)
        write(selection.Id,entry(selection).Name,snapshot(values))
    end
    function self:add(values,name)
        name=validateName(name)
        local existing=ids()
        local id=(existing[#existing] or 0)+1
        write(id,name,snapshot(values))
        return {Kind='user',Id=id}
    end
    function self:previewPath(selection)
        assert(kind=='character' and selection.Kind=='user','Only character presets have previews')
        assert(type(selection.Id)=='number' and selection.Id>=1 and selection.Id%1==0,'Invalid preset id')
        return directory..'character-'..selection.Id..'.png'
    end
    function self:hasPreview(selection)
        local file=io.open(self:previewPath(selection),'rb')
        if not file then return false end
        local header=file:read(8);file:close()
        return header=='\137PNG\13\10\26\10'
    end
    function self:invalidatePreview(selection)
        local path=self:previewPath(selection)
        local file=io.open(path,'rb')
        if file then
            file:close()
            local backup=backups..'character-'..selection.Id..'.png.bak'
            os.remove(backup);assert(os.rename(path,backup))
        end
    end
    function self:remove(selection)
        entry(selection)
        local backup=backups..kind..'-'..selection.Id..'.preset.bak'
        os.remove(backup)
        assert(os.rename(path(selection.Id),backup))
        if kind=='character' then self:invalidatePreview(selection) end
    end
    return self
end
return M
