package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local timers={}
NotifyOnNewObject=function() end
LoopAsync=function(ms,callback) timers[#timers+1]={ms=ms,callback=callback} end
local getenv=os.getenv
os.getenv=function(name) if name=='LOCALAPPDATA' then return 'unused-test-profile' end;return getenv(name) end
local started=false
package.loaded['BetterArena.Balance']={start=function(config,directory)
 assert(config.RewardMultiplier==2 and directory==PROJECT_ROOT..'/mod');started=true
end}
dofile(PROJECT_ROOT..'/mod/Scripts/main.lua')
assert(#timers==1 and timers[1].ms==250)
assert(started)
print('PASS: entry starts automatic PalSchema synchronization and sweep UI')
