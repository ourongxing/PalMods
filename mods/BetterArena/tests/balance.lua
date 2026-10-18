package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local Balance=require('BetterArena.Balance')
assert(Balance.multiplier(require('config'))==2)
assert(not pcall(Balance.multiplier,{}))
for _,bad in ipairs({'2',false,-1,0,0.5,1.5,10.1,11,101,math.huge,0/0}) do assert(not pcall(Balance.multiplier,{RewardMultiplier=bad})) end
for value=1,10 do assert(Balance.multiplier({RewardMultiplier=value})==value) end
assert(not pcall(Balance.requireReady,'world'))
-- A sweep reads the PalSchema-adjusted source without applying another multiplier.
local runtime=require('BetterArena.Runtime').new()
runtime.checkSpace=function(_,_,items) assert(items.Ball==4) end
local context={challengeRank=1,playerRank=1,points=20,
 arena={GetSoloClearReward=function() return {{ItemName={Key={ToString=function() return 'Ball' end}},Rate=100,Min=4,Max=4}} end},
 setting={Arena_RankPoint_WinToNPC=100,Arena_RankPointDiffRate={ForEach=function() end}},
 parameter={SaveParameter={ArenaRankPoint=20},OnUpdateArenaRankPointDelegate={Broadcast=function() end}}}
local plan=runtime:prepare(context)
assert(plan.items.Ball==4 and plan.points==100)
print('PASS: integer multipliers 1..10, unverified rewards rejected and no double sweep scaling')
