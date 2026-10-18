-- Append-only claim journal: reserve durably BEFORE issuing anything.
-- A truncated/corrupt journal fails closed; it must never silently reset quota.
local M = {}
local function checksum(text)
    local hash=2166136261
    for i=1,#text do hash=((hash ~ text:byte(i))*16777619)&0xffffffff end
    return ('%08x'):format(hash)
end
function M.encode(s)
    local body=('%d %d %d %d'):format(s.sequence,s.day,s.used,s.pending and 1 or 0)
    return body..' '..checksum(body)..'\n'
end
function M.decode(text)
    local state
    assert(text=='' or text:sub(-1)=='\n','incomplete claim journal')
    for line in text:gmatch('[^\n]+') do
        local sequence,day,used,pending,hash=line:match('^(%d+) (%d+) (%d+) ([01]) (%x+)$')
        assert(sequence and hash==checksum(line:match('^(.*) %x+$')),'corrupt claim journal')
        local nextState={sequence=tonumber(sequence),day=tonumber(day),used=tonumber(used),pending=pending=='1'}
        assert(nextState.sequence<=100000000 and nextState.day<=100000000 and nextState.used<=100,'invalid claim journal')
        if state then
            assert(nextState.day>=state.day and nextState.sequence>=state.sequence,'claim journal went backwards')
            if nextState.sequence==state.sequence then
                assert(state.pending and not nextState.pending and nextState.day==state.day and nextState.used==state.used,'invalid claim completion')
            else
                assert(nextState.sequence==state.sequence+1 and nextState.pending,'invalid claim reservation')
                assert(nextState.day>state.day and nextState.used==1 or nextState.day==state.day and not state.pending and nextState.used==state.used+1,'invalid daily claim count')
            end
        else assert(nextState.sequence==1 and nextState.used==1 and nextState.pending,'invalid initial claim') end
        state=nextState
    end
    return state
end
function M.new(directory)
    local self={}
    local function path(identity)
        assert(type(identity)=='string' and identity:match('^[%w_-]+$') and #identity<=160,'invalid world/player identity')
        return directory..'/'..identity..'.claims'
    end
    function self:read(identity)
        local file,reason,code=io.open(path(identity),'rb')
        if not file then assert(code==2,reason); return nil end
        local text=assert(file:read('a')); assert(file:close())
        assert(#text<=8*1024*1024,'claim journal too large')
        return M.decode(text)
    end
    function self:write(identity,state)
        local file=assert(io.open(path(identity),'ab'))
        local ok,err=file:write(M.encode(state))
        local flushed,flushError=file:flush()
        local closed,closeError=file:close()
        assert(ok and flushed and closed,err or flushError or closeError or 'claim journal write failed')
    end
    return self
end
return M
