local Network=require('BetterArena.Network')
local M={}
local function mask(c)
 local n=0;for rank=1,7 do if c.cleared[rank] then n=n|(1<<(rank-1)) end end;return n
end
local errors={'inventory full','daily limit','unresolved previous','challenge not cleared','arena rewards are initializing'}
function M.errorCode(err)
 for i,message in ipairs(errors) do if tostring(err):find(message,1,true) then return i end end
 return 0
end
function M.new(config,service,runtime,api)
 api=api or _G
 local self={serial=0,servers={},token=tostring(os.time())..'-'..tostring(math.random(1,1000000000))}
 require('BetterArena.Lifecycle').onReset(function()
  self.pending=nil;self.cache=nil;self.cacheAt=nil;self.owner=nil
  self.retryAt=nil;self.lastError=nil;self.servers={};self.serverCount=0
  self.token=tostring(os.time())..'-'..tostring(math.random(1,1000000000))
 end)
 -- Server state contains strings/numbers only, never retained player objects.
 function self:receive(c,pc,text,sequence)
  local token,op,rank=text:match('^BA1|(%d+%-%d+)|([QC])|([0-7])$')
  if not token or #token>32 then return end
  rank=tonumber(rank)
  if op=='C' and rank==0 then return end
  local ready,context=pcall(runtime.readPlayer,runtime,pc)
  if not ready then
   if self.lastServerError~=tostring(context) then
    self.lastServerError=tostring(context);print('[BetterArena.Server] snapshot rejected: '..tostring(context)..'\n')
   end
   Network.send(c,'BA1|'..token..'|E|'..M.errorCode(context),sequence,true);return
  end
  local key=context.identity..'|'..pc:GetFullName()
  local session=self.servers[key]
  if not session then
   -- Reconnecting controllers get a new name; bound storage, fail closed.
   if self.serverCount and self.serverCount>=1024 then return end
   self.serverCount=(self.serverCount or 0)+1
   session={tokens={},count=0};self.servers[key]=session
  end
  local high=session.tokens[token]
  if high and sequence<=high then return end
  if not high then
   if session.count>=32 then return end
   session.count=session.count+1
  end
  session.tokens[token]=sequence -- consumed before calling any game operation
  local function packet(field) Network.send(c,'BA1|'..token..'|'..field,sequence,true) end
  local ok,result=pcall(function()
   local input={controller=pc}
   if op=='C' then return service:claim(input,rank) end
   return service:preview(input)
  end)
  if not ok then packet('E|'..M.errorCode(result));print('[BetterArena.Server] '..tostring(result)..'\n');return end
  local limit=require('BetterArena.Quota').limit(config,result.playerRank)
  packet(('S|%d|%d|%d|%d|%d'):format(result.remaining,result.playerRank,mask(result),result.pending and 1 or 0,limit))
  if result.receipt then
   packet(('R|%d|%d'):format(result.receipt.points,result.receipt.rank))
   local count=0
   for id,n in pairs(result.receipt.items) do
    assert(id:match('^[%w_]+$') and #id<=100 and n>=0 and n<=2147483647,'invalid reward receipt')
    packet(('I|%s|%d'):format(id,n));count=count+1
   end
   packet('D|'..count)
  else packet('D|0') end
  print(('[BetterArena.Server] %s request %d completed for %s\n'):format(op,sequence,context.identity))
 end
 function self:accept(c,pc,text,sequence)
  local p=self.pending
  if not p or p.sequence~=sequence or p.owner~=pc:GetFullName() then return end
  local token,body=text:match('^BA1|(%d+%-%d+)|(.+)$')
  if token~=self.token then return end
  local code=body:match('^E|([0-5])$')
  if code then
   self.retryAt=os.time()+3
   if self.lastError~=code then
    self.lastError=code;print('[BetterArena.Client] server rejected request: '..(errors[tonumber(code)] or 'server claim failed')..'\n')
   end
   self.pending=nil;self.cache=nil
   if p.callback then p.callback(nil,errors[tonumber(code)] or 'server claim failed') end
   return
  end
  local left,rank,cleared,pending,limit=body:match('^S|(%d+)|([1-7])|(%d+)|([01])|(%d+)$')
  if left then
   left,cleared,limit=tonumber(left),tonumber(cleared),tonumber(limit)
   assert(left<=100 and cleared<=127 and limit<=100,'invalid server snapshot')
   p.result={remaining=left,playerRank=tonumber(rank),cleared={},pending=pending=='1',limit=limit}
   for i=1,7 do if cleared&(1<<(i-1))~=0 then p.result.cleared[i]=true;p.result.challengeRank=i end end
   return
  end
  if not p.result then return end
  local points,rewardRank=body:match('^R|(%d+)|([1-7])$')
  if points then
   assert(tonumber(points)<=2000000000,'invalid receipt points')
   p.result.receipt={points=tonumber(points),rank=tonumber(rewardRank),items={}};return
  end
  local id,n=body:match('^I|([%w_]+)|(%d+)$')
  if id and p.result.receipt then
   assert(#id<=100 and tonumber(n)<=2147483647 and not p.result.receipt.items[id],'invalid receipt item')
   p.result.receipt.items[id]=tonumber(n);p.items=(p.items or 0)+1;assert(p.items<=32,'receipt too large');return
  end
  local count=body:match('^D|(%d+)$')
  if count and tonumber(count)==(p.items or 0) and (p.kind=='Q' or p.result.receipt) then
   self.pending=nil;self.cache=p.result;self.cacheAt=os.time()
   if p.callback then p.callback(p.result) end
   print('[BetterArena.Client] server result received request '..sequence..'\n')
  end
 end
 function self:request(menu,kind,rank,callback)
  local pc=menu:GetOwningPlayer()
  local owner=pc:GetFullName()
  if self.owner~=owner then self.pending=nil;self.cache=nil;self.owner=owner end
  if self.pending and os.time()-self.pending.at>15 then
   local old=self.pending;self.pending=nil;self.cache=nil
   if old.callback then old.callback(nil,'server response timed out') end
  end
  if self.pending then return false end
  if kind=='Q' and self.retryAt and os.time()<self.retryAt then return false end
  self.serial=self.serial+1
  self.pending={sequence=self.serial,owner=owner,at=os.time(),kind=kind,callback=callback}
  local ok,err=pcall(function()
   Network.send(Network.component(pc),'BA1|'..self.token..'|'..kind..'|'..(rank or 0),self.serial,false)
  end)
  if not ok then self.pending=nil;error(err,0) end
  if self.serial==1 then print('[BetterArena.Client] first owned request sent\n') end
  return true
 end
 function self:preview(menu,rank)
  local pc=menu:GetOwningPlayer()
  if pc:HasAuthority() then return service:preview(menu,rank) end
  if self.owner~=pc:GetFullName() or not self.cacheAt or os.time()-self.cacheAt>=2 then self:request(menu,'Q') end
  assert(self.cache,'arena rewards are initializing')
  if rank then assert(self.cache.cleared[rank],'challenge not cleared') end
  return self.cache
 end
 function self:claim(menu,rank,callback)
  if menu:GetOwningPlayer():HasAuthority() then return service:claim(menu,rank) end
  assert(self:request(menu,'C',rank,callback),'claim already running')
 end
 function self:start()
  Network.install(function(...) self:receive(...) end,function(...) self:accept(...) end)
  api.RegisterHook('/Script/Engine.PlayerController:ClientRestart',function(context)
   local pc=context:get()
   if pc and pc:IsValid() and not pc:HasAuthority() then
    self.pending=nil;self.cache=nil;self.cacheAt=nil;self.owner=nil
    self.token=tostring(os.time())..'-'..tostring(math.random(1,1000000000))
   end
  end)
 end
 return self
end
return M
