package.path = PROJECT_ROOT .. '/mod/Scripts/?.lua;' .. package.path
local Plan = require('BetterPalSouls.Plan')
local Slots = require('BetterPalSouls.Slots')
local Service = require('BetterPalSouls.Service')
local Runtime = require('BetterPalSouls.Runtime')
local ids = Plan.items
local function counts(a,b,c,d) return { [ids[1]]=a or 0,[ids[2]]=b or 0,[ids[3]]=c or 0,[ids[4]]=d or 0 } end
local function equal(a,b) for _,id in ipairs(ids) do assert(a[id]==b[id],id) end end
local function copy(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end return o end
local function slot(id,n,bag) return {Item=id,Count=n,Backpack=bag} end
local limits=counts(99,99,99,99)
local schedule={}
for rank,n in ipairs({1,2,3,4,1,2,3,1,2,3,1,2,2,3,3,3,4,4,4,4}) do
    schedule[rank]={Item=ids[rank<=4 and 1 or rank<=7 and 2 or rank<=10 and 3 or 4],Count=n}
end
local zero={0,0,0,0}

-- Exhaust all small mixed inventories against bills containing every tier.
local cases=0
for a=0,4 do for b=0,3 do for c=0,3 do for d=0,2 do
    local stock=counts(a,b,c,d)
    for x=0,2 do for y=0,2 do for z=0,2 do for w=0,1 do
        local bill=counts(x,y,z,w)
        local before=copy(stock)
        local p,reason=Plan.prepare(stock,bill)
        equal(stock,before) -- Preview is pure.
        if Plan.value(stock)<Plan.value(bill) then assert(not p and reason=='insufficient_souls')
        else
            assert(Plan.value(p.Prepared)==Plan.value(stock))
            assert(Plan.value(p.Remaining)==Plan.value(stock)-Plan.value(bill))
            for _,id in ipairs(ids) do assert(p.Prepared[id]-bill[id]==p.Remaining[id] and p.Remaining[id]>=0) end
            for i=2,4 do assert(p.Remaining[ids[i]]==0,'Unspent souls must all be small') end
        end
        cases=cases+1
    end end end end
end end end end
equal(Plan.prepare(counts(0,0,1),counts(1)).Remaining,counts(3))
equal(Plan.prepare(counts(8),counts(0,0,0,1)).Prepared,counts(0,0,0,1))
equal(Plan.prepare(counts(2,3,1,1),counts(1,2)).Remaining,counts(15))
assert(not pcall(Plan.prepare,counts(-1),counts()))
assert(not pcall(Plan.cost, {1,0,0,0},zero,schedule))
local full=Plan.cost(zero,{20,0,0,0},schedule)
equal(full,counts(10,6,6,30))
assert(Plan.maximum(counts(3),zero,{0,1,0,0},schedule,1)==1)
assert(Plan.maximum(counts(3),zero,zero,schedule,1)==2)
assert(Plan.maximum(counts(0,0,0,100),zero,zero,schedule,1)==20)
-- Confirming an affordable maximum must leave too little value to raise
-- that same stat again, even when the other selected stats are paid too.
for budget=0,160 do
    for from=0,19 do
        local current={from,0,0,0}
        local targets={from,1,0,0}
        if budget>=1 then
            targets[1]=Plan.maximum(counts(budget),current,targets,schedule,1)
            local p=assert(Plan.prepare(counts(budget),Plan.cost(current,targets,schedule)))
            assert(Plan.maximum(p.Remaining,targets,targets,schedule,1)==targets[1],
                'A paid maximum must not permit another increase with unchanged inventory')
        end
    end
end

-- Never overwrite ordinary items, retype base slots, or overfill stacks.
local inventory={slot(ids[3],1,true),slot('Wood',30,true),slot('None',0,true),slot(ids[2],3,false)}
local writes=assert(Slots.allocate(inventory,counts(1,4),limits))
local after=copy(inventory)
for _,write in ipairs(writes) do after[write.Index].Item=write.Item;after[write.Index].Count=write.Count end
assert(after[2].Item=='Wood' and after[2].Count==30)
assert(after[4].Item==ids[2] and after[4].Count==4)
assert(inventory[1].Item==ids[3] and inventory[1].Count==1)
local noSpace,why=Slots.allocate({slot(ids[3],1,false)},counts(1,1),limits)
assert(not noSpace and why=='backpack_full')
assert(not Slots.allocate({slot('None',0,true)},counts(100),limits))
assert(Slots.allocate({slot('None',0,true),slot('None',0,true)},counts(100),limits))

local function backend(failure)
    local b={stock=counts(0,0,1),current=copy(zero),mutations=0}
    function b:read()
        return {Stock=copy(self.stock),Current=copy(self.current),Schedule=schedule,Limits=limits,
            HandleKey='Pal-A',Slots={slot(ids[3],self.stock[ids[3]],true),slot('None',0,true),slot('None',0,true)}}
    end
    function b:check() if failure=='check' then error('inventory_changed') end end
    function b:checkCost() if failure=='cost' then error('native_cost_mismatch') end end
    function b:apply(state,changes)
        self.mutations=self.mutations+1
        local slots=copy(state.Slots)
        for _,w in ipairs(changes) do slots[w.Index]=slot(w.Item,w.Count,true) end
        self.stock=counts()
        for _,s in ipairs(slots) do if Plan.weight[s.Item] then self.stock[s.Item]=self.stock[s.Item]+s.Count end end
        if failure=='apply' then error('partial_conversion') end
    end
    function b:checkPrepared(_,expected) equal(self.stock,expected) end
    function b:upgrade(state,targets)
        local required=Plan.cost(state.Current,targets,schedule)
        for _,id in ipairs(ids) do self.stock[id]=self.stock[id]-required[id] end
        self.current=copy(targets)
        if failure=='upgrade' then error('partial_upgrade') end
    end
    function b:verify(_,targets,remaining)
        if failure=='verify' then error('native_verification_failed') end
        equal(self.stock,remaining)
        for i=1,4 do assert(self.current[i]==targets[i]) end
    end
    function b:restore(state)
        if failure=='restore' then error('cannot_restore') end
        self.stock,self.current=copy(state.Stock),copy(state.Current)
    end
    return b
end
local b=backend();local service=Service.new(b)
assert(service:preview({}, {1,0,0,0}));equal(b.stock,counts(0,0,1));assert(b.mutations==0)
assert(service:submit({}, {1,0,0,0},'Pal-A',zero));equal(b.stock,counts(3));assert(b.current[1]==1)
for _,failure in ipairs({'check','cost','apply','upgrade','verify'}) do
    b=backend(failure);service=Service.new(b)
    local result=service:submit({}, {1,0,0,0},'Pal-A',zero)
    assert(not result);equal(b.stock,counts(0,0,1));assert(b.current[1]==0 and not service.busy)
    assert(service.disabled==((failure~='check' and failure~='cost') and true or nil))
end
b=backend();service=Service.new(b)
assert(not service:submit({}, {1,0,0,0},'Different-Pal',zero));assert(b.mutations==0)
assert(not service:submit({}, {1,0,0,0},'Pal-A',{1,0,0,0}));assert(b.mutations==0)
assert(not service:submit({}, zero,'Pal-A',zero));assert(b.mutations==0)
service.busy=true;local _,reason=service:submit({},zero,'Pal-A',zero);assert(reason=='busy')
b=backend('restore');function b:upgrade() error('rejected') end
service=Service.new(b);local _,errorText=service:submit({}, {1,0,0,0},'Pal-A',zero)
assert(errorText:find('rollback_failed') and service.disabled)

-- Exercise actual runtime decoding; the final two recipe names are reversed in-game.
local function fname(s) return {ToString=function() return s end} end
local rows={}
for rank,row in ipairs(schedule) do rows[rank]={Rank=rank,RequiredStaticItemId=fname(row.Item),RequiredItemNum=row.Count} end
local recipes={}
for i=1,3 do
    for _,v in ipairs({{i==3 and 'PalUpgradeStone4_3' or 'PalUpgradeStone'..i..'_'..(i+1),i,2,i+1,1},
        {i==3 and 'PalUpgradeStone3_4' or 'PalUpgradeStone'..(i+1)..'_'..i,i+1,1,i,2}}) do
        local row={Material1_Id=fname(ids[v[2]]),Material1_Count=v[3],Product_Id=fname(ids[v[4]]),Product_Count=v[5]}
        for n=2,5 do row['Material'..n..'_Id']=fname('None');row['Material'..n..'_Count']=0 end
        recipes[v[1]]=row
    end
end
local dt={IsValid=function() return true end,GetRowMap=function() return rows end}
local access={BP_FindRow=function(_,id,out) out.bResult=recipes[id:ToString()]~=nil;return recipes[id:ToString()] end}
local utility={IsValid=function() return true end,GetCharacterUpgradeDataTable=function() return dt end,
    GetItemRecipeDataTableAccess=function() return access end}
local runtime=Runtime.new({FName=fname,StaticFindObject=function() return utility end})
assert(#runtime:schedule({})==20)
recipes.PalUpgradeStone4_3.Material1_Count=3
assert(not pcall(function() runtime:schedule({}) end))
print(('Verified %d mixed conversion cases, shared budgets, slot allocation, failures and live-data recipe decoding.'):format(cases))
