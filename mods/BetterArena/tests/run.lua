package.path=PROJECT_ROOT..'/mod/Scripts/?.lua;'..package.path
local Q=require('BetterArena.Quota')
local Store=require('BetterArena.Store')
local Service=require('BetterArena.Service')
local defaults=require('config')
assert(defaults.RewardMultiplier==2)
for rank=1,7 do assert(Q.limit(defaults,rank)==rank*2-1) end
assert(Q.remaining(nil,10,defaults,4)==7)
local defaultState=Q.reserve(nil,10,defaults,1);defaultState.pending=false
assert(Q.remaining(defaultState,10,defaults,2)==2)
-- Keep a smaller custom quota for transaction/failure scenarios below.
local config={DailyLimits={1,2,3,4,5,6,7}}
local state
for rank=1,7 do assert(Q.limit(config,rank)==rank) end
assert(Q.remaining(nil,10,config,1)==1)
state=Q.reserve(nil,10,config,2)
assert(state.used==1 and state.pending)
assert(not pcall(Q.reserve,state,10,config,2))
state.pending=false
assert(Q.remaining(state,10,config,3)==2) -- promotion only adds the difference
assert(Q.remaining(state,9,config,3)==2) -- clock rollback doesn't reset
assert(Q.remaining(state,11,config,3)==3) -- new game day, no carry-over
local first=Q.reserve(nil,10,config,3)
local text=Store.encode(first)
assert(Store.decode(text).pending)
first.pending=false;text=text..Store.encode(first)
assert(Store.decode(text).used==1)
assert(not pcall(Store.decode,text:sub(1,-2)))
assert(not pcall(Store.decode,text:gsub('10','11',1)))
assert(not pcall(Store.decode,text..text))
local logs,rank,challenge,day,awards={},2,5,10,0
local storage={}
function storage:read(id) return Store.decode(logs[id] or '') end
function storage:write(id,s) logs[id]=(logs[id] or '')..Store.encode(s) end
local fail,saveFailure,reentrant=false,false,false
local runtime={}
function runtime:read(menu)
 return {identity=menu,day=day,playerRank=rank,challengeRank=challenge}
end
function runtime:prepare(c) assert(c.challengeRank);return {items=10,points=500} end
local service
function runtime:award(c,plan)
 assert(storage:read(c.identity).pending) -- durable reservation precedes effects
 if reentrant then assert(not pcall(service.claim,service,c.identity)) end
 awards=awards+1
 if fail then error('injected award failure') end
 rank=3
end
service=Service.new(config,storage,runtime)
challenge=nil;assert(not pcall(service.claim,service,'worldA_player'));assert(awards==0)
challenge=5;reentrant=true
local completed=service:claim('worldA_player')
assert(completed.remaining==2 and completed.receipt.items==10 and completed.receipt.points==500 and completed.receipt.rank==5)
assert(service:claim('worldA_player').remaining==1)
assert(service:claim('worldA_player').remaining==0)
assert(not pcall(service.claim,service,'worldA_player'));assert(awards==3)
assert(service:preview('worldB_player').remaining==3)
assert(service:preview('worldA_otherPlayer').remaining==3)
day=11;fail=true
assert(not pcall(service.claim,service,'worldA_player'))
assert(service:preview('worldA_player').pending)
fail=false;assert(not pcall(service.claim,service,'worldA_player'));assert(awards==4)
day=12;assert(service:claim('worldA_player').remaining==2)
local previous=storage.write
function storage:write() error('disk full') end
day=13;assert(not pcall(service.claim,service,'worldA_player'));assert(awards==5)
storage.write=previous
-- A failed completion is uncertain, so it blocks same-day automatic replay.
local writes=0
function storage:write(id,s)
 writes=writes+1
 if writes==2 then error('completion disk failure') end
 previous(self,id,s)
end
assert(not pcall(service.claim,service,'worldC_player'))
local Rewards=require('BetterArena.Rewards')
assert(Rewards.points(500,3,3,{})==500)
assert(Rewards.points(500,3,4,{[-1]=1.2000000476837})==600)
assert(Rewards.points(500,4,3,{[1]=0.89999997615814})==450)
assert(Rewards.points(50,7,1,{[6]=0.050000000745058})==2)
local rolled=Rewards.roll({{id='BattleTicket',rate=100,min=10,max=10},{id='Ball',rate=0,min=1,max=2}},function() error('guaranteed rewards do not draw random probability') end)
assert(rolled.BattleTicket==10 and not rolled.Ball)
assert(Rewards.roll({{id='Ball',rate=50,min=1,max=2}},function(a,b) if a then return b end;return 0.49 end).Ball==2)
assert(not next(Rewards.roll({{id='Ball',rate=50,min=1,max=2}},function() return 0.5 end)))
assert(not pcall(Rewards.roll,{{id='None',rate=100,min=1,max=1}}))
local function object(fields) fields.IsValid=function() return true end;return fields end
local function name(s) return {ToString=function() return s end} end
local slots={object{StackCount=90,ItemId={StaticId=name('Ball')},GetMaxStack=function() return 100 end},object{StackCount=0}}
local container=object{GetFullName=function() return 'backpack' end,Num=function() return #slots end,Get=function(_,i) return slots[i+1] end}
local inventory=object{TryGetContainerFromStaticItemID=function(_,id,out) out.OutContainer=container;return true end}
local manager=object{GetStaticItemData=function() return object{GetMaxStackCount=function() return 100 end} end}
local utility=object{GetItemIDManager=function() return manager end}
local runtimeAdapter=require('BetterArena.Runtime').new{StaticFindObject=function() return utility end,FName=function(s) return s end}
runtimeAdapter:checkSpace({inventory=inventory},{Ball=110}) -- existing 10 + one new stack
assert(not pcall(runtimeAdapter.checkSpace,runtimeAdapter,{inventory=inventory},{Ball=111}))
assert(not pcall(runtimeAdapter.checkSpace,runtimeAdapter,{inventory=inventory},{Ball=20,Ticket=1})) -- two rewards share empty slots
runtimeAdapter:checkSpace({inventory=inventory},{Ball=10,Ticket=100})
local tags={['zh-CN']='扫荡',['zh-TW']='掃蕩',['ja-JP']='掃討',['en-US']='Sweep'}
for tag,expected in pairs(tags) do
 StaticFindObject=function() return {GetCurrentCulture=function() return {ToString=function() return tag end} end} end
 assert(require('BetterArena.I18n').current().action==expected)
end
assert(service:preview('worldC_player').pending)
assert(not pcall(service.claim,service,'worldC_player'))
