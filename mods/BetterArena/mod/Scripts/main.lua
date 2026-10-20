local config=require('config')
require('BetterArena.Lifecycle').install()
local Quota=require('BetterArena.Quota')
for rank=1,7 do Quota.limit(config,rank) end
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local modDirectory=assert(source:match('^(.*)/Scripts/[^/]+$'),'mod directory unavailable')
require('BetterArena.Balance').start(config,modDirectory)
local serverFile=io.open(modDirectory..'/server.txt','rb')
local dedicated=serverFile~=nil
if serverFile then serverFile:close() end
local directory
if dedicated then
 directory=assert(modDirectory:match('^(.*)/Mods/NativeMods/UE4SS/Mods/BetterArena$'),'server root unavailable')..'/Pal/Saved/BetterArena'
else
 directory=assert(os.getenv('LOCALAPPDATA'),'LOCALAPPDATA unavailable'):gsub('\\','/')..'/Pal/Saved/BetterArena'
end
local store=require('BetterArena.Store').new(directory)
local runtime=require('BetterArena.Runtime').new()
local service=require('BetterArena.Service').new(config,store,runtime)
local remote=require('BetterArena.Remote').new(config,service,runtime)
remote:start()
if not dedicated then require('BetterArena.UI').start(config,remote) end
print('[Better Arena / 更好的竞技场] Loaded. Arena menu > Sweep > cleared difficulty, shared daily rank quota.\n')
