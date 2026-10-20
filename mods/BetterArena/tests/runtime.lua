package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
package.loaded['BetterArena.Balance']={requireReady=function(world) assert(world==string.rep('a',32)) end}
local function object(t) t.IsValid=function() return true end;return t end
local pc=object{HasAuthority=function() return true end,GetAddress=function() return 10 end}
local parameter=object{IsInArena=function() return false end,GetArenaRank=function() return 2 end,GetArenaRankPoint=function() return 850 end}
local component=object{IsDead=function() return false end,GetIndividualParameter=function() return parameter end}
pc.Pawn=object{Controller=pc,GetCharacterParameterComponent=function() return component end}
local record=object{ArenaSoloClearCount={Items={GetArrayNum=function() return 1 end,
 ForEach=function(_,fn) fn(1,{Key={ToString=function() return 'Bronze' end},Value=1}) end}}}
pc.PlayerState=object{PlayerUId={A=1,B=2,C=3,D=4},GetRecordData=function() return record end,
 GetInventoryData=function() return object{} end}
local utility={GetPalmi=function() error('must not resolve the local player') end,
 GetPalGameStateInGame=function() return object{GetWorldSaveDirectoryName=function() return string.rep('a',32) end} end,
 GetTimeManager=function() return {GetCurrentPalWorldTime_TotalDay=function() return 40 end} end,
 GetArenaWorldSubsystem=function() return object{} end,GetGameSetting=function() return object{} end}
local runtime=require('BetterArena.Runtime').new({StaticFindObject=function() return utility end})
local c=runtime:readPlayer(pc,1)
assert(c.playerRank==3 and c.challengeRank==1 and c.day==40 and c.controller==pc)
assert(c.identity==string.rep('a',32)..'_00000001000000020000000300000004')
assert(not pcall(runtime.readPlayer,runtime,pc,2))
assert(runtime:read({controller=pc},1).identity==c.identity)
pc.Pawn.Controller=object{GetAddress=function() return 20 end}
assert(not pcall(runtime.readPlayer,runtime,pc,1))
print('PASS: dedicated controller pawn resolution, ownership, server record/day/rank and locked difficulty')
