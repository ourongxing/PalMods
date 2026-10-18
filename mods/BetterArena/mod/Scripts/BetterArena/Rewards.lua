local M={}
local function f32(n) return (string.unpack('f',string.pack('f',n))) end
function M.points(base,playerRank,challengeRank,rates)
    assert(type(base)=='number' and base>=0 and base<=1000000 and base%1==0,'invalid NPC victory points')
    local rate=rates[playerRank-challengeRank] or 1
    assert(type(rate)=='number' and rate>=0 and rate<=100,'invalid rank difference multiplier')
    -- The native calculator uses single-precision multiplication, then truncates.
    return math.floor(f32(f32(base)*f32(rate)))
end
function M.roll(rows,random)
    random=random or math.random
    local items={}
    for _,row in ipairs(rows) do
        assert(type(row.id)=='string' and row.id~='' and row.id~='None','invalid reward item')
        assert(type(row.rate)=='number' and row.rate>=0 and row.rate<=100,'invalid reward probability')
        assert(type(row.min)=='number' and row.min%1==0 and row.min>=0 and row.max%1==0 and row.max>=row.min and row.max<=1000000,'invalid reward amount')
        if row.rate==100 or row.rate>0 and random()*100<row.rate then
            local count=row.min==row.max and row.min or random(row.min,row.max)
            items[row.id]=(items[row.id] or 0)+count
        end
    end
    return items
end
return M
