-- Pure rules. Rank indexes here are 1..7, independently of engine enum values.
local M = {}
local function integer(n, minimum, maximum)
    assert(type(n)=='number' and n%1==0 and n>=minimum and n<=maximum, 'invalid integer')
    return n
end
function M.limit(config, rank)
    integer(rank,1,7)
    return integer(config.DailyLimits[rank],0,100)
end
function M.current(state, day)
    integer(day,0,100000000)
    state=state or {day=day,used=0,pending=false,sequence=0}
    -- Moving the clock backwards never replenishes an already issued allowance.
    if day>state.day then return {day=day,used=0,pending=false,sequence=state.sequence} end
    return {day=state.day,used=state.used,pending=state.pending,sequence=state.sequence}
end
function M.remaining(state, day, config, rank)
    local current=M.current(state,day)
    return math.max(0,M.limit(config,rank)-current.used),current
end
function M.reserve(state, day, config, rank)
    local left,current=M.remaining(state,day,config,rank)
    assert(not current.pending,'unresolved previous claim')
    assert(left>0,'daily limit reached')
    current.used=current.used+1
    current.sequence=current.sequence+1
    current.pending=true
    return current
end
return M
