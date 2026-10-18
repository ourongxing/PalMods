-- PalSchema owns native data patches. This module only checks local config.
local M={}
function M.multiplier(config)
 local n=config.RewardMultiplier
 if n==nil then n=2 end
 assert(type(n)=='number' and n%1==0 and n>=1 and n<=10,'RewardMultiplier must be an integer from 1 to 10')
 return n
end
function M.verify(config,applied)
 local requested=M.multiplier(config)
 assert(applied==requested,'RewardMultiplier changed: close Palworld and run ConfigureRewards.cmd to apply PalSchema patches')
 return requested
end
return M
