local config=require('config')
local Quota=require('BetterArena.Quota')
for rank=1,7 do Quota.limit(config,rank) end
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local modDirectory=assert(source:match('^(.*)/Scripts/[^/]+$'),'mod directory unavailable')
require('BetterArena.Balance').start(config,modDirectory)
local directory=assert(os.getenv('LOCALAPPDATA'),'LOCALAPPDATA unavailable'):gsub('\\','/')..'/Pal/Saved/BetterArena'
local store=require('BetterArena.Store').new(directory)
local runtime=require('BetterArena.Runtime').new()
local service=require('BetterArena.Service').new(config,store,runtime)
require('BetterArena.UI').start(config,service)
print('[Better Arena / 更好的竞技场] Loaded. Arena menu > Sweep > cleared difficulty, shared daily rank quota.\n')
