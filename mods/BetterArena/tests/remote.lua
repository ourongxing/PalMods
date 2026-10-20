package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local Network=require('BetterArena.Network')
local Remote=require('BetterArena.Remote')
local packets={}
Network.send=function(c,text,sequence,down) packets[#packets+1]={c,text,sequence,down} end
Network.component=function(pc) return pc.channel end
local awards=0
local function player(name)
 local pc={channel=name,GetFullName=function() return name end,HasAuthority=function() return false end}
 return pc
end
local a,b=player('A'),player('B')
local snapshot=function() return {remaining=3,playerRank=2,cleared={[1]=true,[3]=true},challengeRank=3,pending=false} end
local runtime={readPlayer=function(_,pc) return {identity='world_'..pc:GetFullName()} end}
local service={preview=function() return snapshot() end,
 claim=function(_,input,rank)
  assert(input.controller==a or input.controller==b)
  assert(rank==3,'challenge not cleared');awards=awards+1
  local c=snapshot();c.remaining=2;c.receipt={points=70,rank=3,items={Ball=4,Coin=20}};return c
 end}
local config={DailyLimits={1,3,5,7,9,11,13}}
local server=Remote.new(config,service,runtime)
local client=Remote.new(config,service,runtime)
client.token='100-200'
local menu={GetOwningPlayer=function() return a end}
assert(not pcall(client.preview,client,menu))
local request=table.remove(packets)
server:receive('A',a,request[2],request[3])
for _,p in ipairs(packets) do client:accept('A',a,p[2],p[3]) end
packets={}
local preview=client:preview(menu)
assert(preview.remaining==3 and preview.limit==3 and preview.cleared[1] and not preview.cleared[2])
local result
client:claim(menu,3,function(c) result=c end)
assert(not pcall(client.claim,client,menu,3,function() error('duplicate callback') end))
request=table.remove(packets)
server:receive('A',a,request[2],request[3]);server:receive('A',a,request[2],request[3])
assert(awards==1)
-- Completion never publishes a partial receipt or a different player's data.
for _,p in ipairs(packets) do client:accept('B',b,p[2],p[3]) end
assert(not result)
for i=1,#packets-1 do local p=packets[i];client:accept('A',a,p[2],p[3]) end
assert(not result)
local last=packets[#packets];client:accept('A',a,last[2],last[3])
assert(result.receipt.points==70 and result.receipt.items.Ball==4 and result.remaining==2)
client:accept('A',a,last[2],last[3]);assert(awards==1)
-- Replays and out-of-order requests remain rejected after later requests.
server:receive('A',a,'BA1|100-200|Q|0',3)
server:receive('A',a,'BA1|100-200|C|3',2);assert(awards==1)
server:receive('B',b,'BA1|100-200|C|3',2);assert(awards==2)
server:receive('A',a,'BA1|100-200|C|0',4);assert(awards==2)
server:receive('A',a,'BA1|100-200|C|2',4);assert(awards==2)
assert(Remote.errorCode('inventory full')==1 and Remote.errorCode('unknown')==0)
client.pending={callback=function() error('old claim callback invoked') end}
client.cache={remaining=99};client.retryAt=os.time()+100
require('BetterArena.Lifecycle').reset()
assert(not client.pending and not client.cache and not client.retryAt)
assert(server.serverCount==0 and next(server.servers)==nil)
print('PASS: owned player isolation, authoritative preview/receipt, duplicate and stale requests, partial results and locked challenges')
