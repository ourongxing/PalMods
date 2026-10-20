package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local Network=require('BetterArena.Network')
local function object(t) t.IsValid=function() return true end;return t end
local pc,tx,c
pc=object{HasAuthority=function() return true end,GetAddress=function() return 1 end}
tx=object{GetAddress=function() return 2 end,GetOwner=function() return pc end,GetBaseCamp=function() return c end}
c=object{GetAddress=function() return 3 end,GetOwner=function() return tx end}
pc.Transmitter=tx
assert(Network.owner(c)==pc and Network.component(pc)==c)
local original=pc.Transmitter;pc.Transmitter=object{GetAddress=function() return 9 end}
assert(not pcall(Network.owner,c));pc.Transmitter=original
local hooks={};RegisterHook=function(name,fn) hooks[name]=fn end
local up,down=0,0
Network.install(function() up=up+1 end,function() down=down+1 end)
local function wrap(v) return {get=function() return v end} end
local function packet(path,text,n)
 hooks['/Script/Pal.PalNetworkBaseCampComponent:'..path](wrap(c),nil,wrap({ToString=function() return text end}),wrap(n))
end
packet('Request_Server_int32','OtherMod',1);assert(up==0)
packet('Request_Server_int32','BA1|100-200|Q|0',1);assert(up==1)
packet('Notify_RequestClient_int32','BA1|100-200|D|0',1);assert(down==0)
pc.HasAuthority=function() return false end
packet('Request_Server_int32','BA1|100-200|Q|0',2);assert(up==1)
packet('Notify_RequestClient_int32','BA1|100-200|D|0',2);assert(down==1)
packet('Notify_RequestClient_int32','BA1|'..string.rep('x',201),2);assert(down==1)
packet('Notify_RequestClient_int32','BA1|100-200|D|0',-1);assert(down==1)
print('PASS: RPC roles, transmitter/controller/component ownership, namespace and packet bounds')
