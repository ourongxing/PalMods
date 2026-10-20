-- Uses the player's existing reliable, owned RPCs. No sockets or multicast.
-- Packet format is ours; the transport pattern was inspected in Pal Work
-- Priority (MIT, Matraweber), without copying its implementation.
local M={}
local ZERO={A=0,B=0,C=0,D=0}
local function valid(o) return o and o:IsValid() end
local function unwrap(o) local ok,v=pcall(function() return o:get() end);return ok and v or o end
function M.owner(c)
 local tx=c:GetOwner();assert(valid(tx),'network transmitter unavailable')
 local pc=tx:GetOwner();assert(valid(pc),'network player unavailable')
 assert(valid(pc.Transmitter) and pc.Transmitter:GetAddress()==tx:GetAddress(),'network owner mismatch')
 assert(tx:GetBaseCamp():GetAddress()==c:GetAddress(),'network component mismatch')
 return pc
end
function M.component(pc)
 assert(valid(pc) and valid(pc.Transmitter),'network unavailable')
 local c=pc.Transmitter:GetBaseCamp()
 assert(valid(c) and M.owner(c):GetAddress()==pc:GetAddress(),'network owner mismatch')
 return c
end
function M.send(c,name,sequence,down)
 assert(#name<=200 and sequence>=1 and sequence<=2147483647,'invalid network packet')
 if down then c:Notify_RequestClient_int32(ZERO,FName(name),sequence)
 else c:Request_Server_int32(ZERO,FName(name),sequence) end
end
function M.install(up,down)
 for _,spec in ipairs({{'Request_Server_int32',up,true},{'Notify_RequestClient_int32',down,false}}) do
  RegisterHook('/Script/Pal.PalNetworkBaseCampComponent:'..spec[1],function(ctx,_,name,sequence)
   local ok,err=pcall(function()
    local text=unwrap(name):ToString()
    if text:sub(1,4)~='BW1|' or #text>200 then return end
    local c=unwrap(ctx);local pc=M.owner(c)
    if pc:HasAuthority()~=spec[3] then return end
    local n=unwrap(sequence)
    assert(type(n)=='number' and n%1==0 and n>=1 and n<=2147483647,'invalid sequence')
    spec[2](c,pc,text,n)
   end)
   if not ok then print('[BetterWorkbench.Network] '..tostring(err)..'\n') end
  end)
 end
end
return M
