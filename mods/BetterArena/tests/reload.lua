package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local Balance=require('BetterArena.Balance')
local Schema=require('BetterArena.Schema')
local base=require('BetterArena.BaseRewards')
local writes={}
Schema.write=function(path,text) writes[#writes+1]={path,text} end
Schema.autoReload=function() return true end
local function object(t) t.IsValid=function() return true end;return t end
local factor=2
local ranks={'Bronze','Silver','Gold','Platinum','Diamond','Master','Legend'}
local arena=object{GetSoloClearReward=function(_,rank,first)
 local out={}
 for _,e in ipairs(base[ranks[rank+1]][first and 'FirstClearReward' or 'RepeatClearReward']) do
  out[#out+1]={ItemName={Key={ToString=function() return e.ItemName.Key end}},Rate=e.Rate,Min=e.Min*factor,Max=e.Max*factor}
 end
 return out
end}
local world='world-a'
local game=object{GetFullName=function() return 'instance-'..world end,GetWorldSaveDirectoryName=function() return world end}
local setting=object{Arena_RankPoint_WinToNPC=100,Arena_RankPoint_LoseToNPC=15,Arena_RankPoint_Win=90}
local controller=object{HasAuthority=function() return true end}
local utility=object{GetLocalPlayerController=function() return controller end,GetPalGameStateInGame=function() return game end,
 GetArenaWorldSubsystem=function() return arena end,GetGameSetting=function() return setting end}
local tick
local searches=0
local api={LoopAsync=function(ms,fn) assert(ms==500);tick=fn end,ExecuteInGameThread=function(fn) fn() end,
 StaticFindObject=function() return utility end,FindFirstOf=function() searches=searches+1;return object{} end,LoadAsset=function() end}
Balance.start({RewardMultiplier=3},'/mods/BetterArena',api)
tick();assert(#writes==2 and not pcall(Balance.requireReady,world))
tick();assert(not pcall(Balance.requireReady,world) and setting.Arena_RankPoint_WinToNPC==100)
factor=3;tick();Balance.requireReady(world)
assert(setting.Arena_RankPoint_WinToNPC==150 and setting.Arena_RankPoint_LoseToNPC==15 and setting.Arena_RankPoint_Win==90)
tick();assert(#writes==2) -- no repeated writes after verification
world='world-b';factor=2;tick();assert(#writes==4 and not pcall(Balance.requireReady,world))
factor=3;tick();Balance.requireReady(world)
world='world-c';factor=2;tick()
for _=1,35 do tick() end
assert(not pcall(Balance.requireReady,world) and #writes==6) -- bounded verification, no free claim
world='world-d';factor=3
Schema.write=function() error('disk full') end
tick();tick();assert(not pcall(Balance.requireReady,world)) -- old values matching cannot bypass failed generation
assert(searches==1,'persistent game instance must not be searched every tick')
Schema.autoReload=function() return false end
assert(not pcall(Balance.start,{RewardMultiplier=3},'/mods/BetterArena',api))
print('PASS: startup regeneration, real-value verification, shared scalar RP, world changes, bounded timeout and one-time reload setup')
