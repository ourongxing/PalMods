package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local timers={}
LoopAsync=function(ms,callback) timers[#timers+1]={ms=ms,callback=callback} end
local getenv=os.getenv
os.getenv=function(name) if name=='LOCALAPPDATA' then return 'unused-test-profile' end;return getenv(name) end
assert(require('config').Enabled==nil)
dofile(PROJECT_ROOT..'/mod/Scripts/main.lua')
assert(#timers==1 and timers[1].ms==250)
print('PASS: entry starts sweep UI without Enabled or a native data-patching timer')
