-- Only serializes our fixed Arena patch shape; never copies native structs.
local M={}
M.blueprint='/Game/Pal/Blueprint/System/BP_PalGameSetting'
local ranks={'Bronze','Silver','Gold','Platinum','Diamond','Master','Legend'}
function M.patches(base,multiplier)
 local rows={}
 for _,rank in ipairs(ranks) do
  local fields={}
  for _,field in ipairs({'FirstClearReward','RepeatClearReward'}) do
   local items={}
   for _,r in ipairs(base[rank][field]) do
    local id=r.ItemName.Key
    assert(id:match('^[%w_]+$'),'invalid baseline item ID')
    items[#items+1]=('{"ItemName":{"Key":"%s"},"Rate":%s,"Min":%d,"Max":%d}'):format(id,r.Rate,r.Min*multiplier,r.Max*multiplier)
   end
   fields[#fields+1]='"'..field..'":['..table.concat(items,',')..']'
  end
  rows[#rows+1]='"'..rank..'":{'..table.concat(fields,',')..'}'
 end
 local points=('{"Arena_RankPoint_WinToNPC":%d}'):format(50*multiplier)
 return '{"DT_ArenaSoloRewardTable":{'..table.concat(rows,',')..'}}\n',
  '{"BP_PalGameSetting_C":'..points..',"'..M.blueprint..'":'..points..'}\n'
end
function M.write(path,text)
 -- Called synchronously on the game thread. The watcher queues its JSON
 -- parsing onto that same thread, after this complete write and close.
 -- A rename is unsuitable: PalSchema watches Add/Modified, not Move events.
 local f=assert(io.open(path,'wb'))
 local ok,err=f:write(text);local closed,closeError=f:close()
 assert(ok and closed,err or closeError)
end
function M.autoReload(path)
 local f=assert(io.open(path,'rb'),'PalSchema configuration unavailable')
 local text=f:read('*a');f:close()
 if text:match('"enableAutoReload"%s*:%s*true') then return true end
 local updated,count=text:gsub('("enableAutoReload"%s*:%s*)false','%1true')
 assert(count==1,'PalSchema enableAutoReload setting unavailable')
 M.write(path,updated)
 return false -- PalSchema already read its settings: requires one restart.
end
function M.matches(base,arena,multiplier)
 for index,rank in ipairs(ranks) do
  for _,field in ipairs({'FirstClearReward','RepeatClearReward'}) do
   local actual={}
   local function add(row)
    local ok,value=pcall(function() return row:get() end);row=ok and value or row
    actual[#actual+1]={id=row.ItemName.Key:ToString(),rate=row.Rate,min=row.Min,max=row.Max}
   end
   local result=arena:GetSoloClearReward(index-1,field=='FirstClearReward')
   if type(result)=='table' then for _,r in ipairs(result) do add(r) end
   else result:ForEach(function(_,r) add(r) end) end
   local expected=base[rank][field]
   if #actual~=#expected then return false end
   for i,r in ipairs(actual) do
    local e=expected[i]
    if r.id~=e.ItemName.Key or r.rate~=e.Rate or r.min~=e.Min*multiplier or r.max~=e.Max*multiplier then return false end
   end
  end
 end
 return true
end
return M
