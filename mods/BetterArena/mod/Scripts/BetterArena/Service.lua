local Quota=require('BetterArena.Quota')
local M={}
function M.new(config,store,runtime)
    local self={busy=false}
    function self:preview(menu,rank)
        local context=runtime:read(menu,rank)
        local left,state=Quota.remaining(store:read(context.identity),context.day,config,context.playerRank)
        context.remaining=left
        context.pending=state.pending
        return context
    end
    function self:claim(menu,rank)
        assert(not self.busy,'claim already running')
        self.busy=true
        local ok,result=pcall(function()
            local context=self:preview(menu,rank)
            assert(context.challengeRank,'no cleared challenge')
            assert(not context.pending,'unresolved previous claim')
            assert(context.remaining>0,'daily limit reached')
            local plan=runtime:prepare(context)
            local state=Quota.reserve(store:read(context.identity),context.day,config,context.playerRank)
            store:write(context.identity,state)
            -- Any exception after reservation leaves it consumed and pending.
            -- Never replay an uncertain reward after a crash or failed save.
            runtime:award(context,plan)
            state.pending=false
            store:write(context.identity,state)
            local result=self:preview(menu,rank)
            result.receipt={items=plan.items,points=plan.points,rank=context.challengeRank}
            return result
        end)
        self.busy=false
        if not ok then error(result,0) end
        return result
    end
    return self
end
return M
