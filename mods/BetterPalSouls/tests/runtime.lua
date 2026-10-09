-- Exercise actual slot journaling, native bill checking and post-request rollback.
local Runtime=require('BetterPalSouls.Runtime')
local Plan=require('BetterPalSouls.Plan')
local Service=require('BetterPalSouls.Service')
local ids,fields=Plan.items,{'Rank_Attack','Rank_Defence','Rank_HP','Rank_CraftSpeed'}
local function object(name,fields)
    fields=fields or {};fields.IsValid=function() return true end;fields.GetFullName=function() return name end
    return fields
end
local function fname(s) return {ToString=function() return s end} end
local function guid() return {A=0,B=0,C=0,D=0} end
for _,failure in ipairs({'none','write','request','cost','missing_output','unknown_item'}) do
    local objects={}
    for i=1,2 do
        objects[i]=object('Slot-'..i,{ItemId={StaticId=fname(i==1 and ids[3] or 'None'),
            DynamicId={CreatedWorldId=guid(),LocalIdInCreatedWorld=guid()}},StackCount=i==1 and 1 or 0,
            OnRep_ItemId=function() end,OnRep_StackCount=function() end})
    end
    local bag=object('Bag',{Num=function() return 2 end,Get=function(_,i) return objects[i+1] end})
    local parameter=object('Parameter',{SaveParameter={},SaveParameterMirror={},OnRep_SaveParameter=function() end})
    for _,field in ipairs(fields) do parameter.SaveParameter[field]=0;parameter.SaveParameterMirror[field]=0 end
    local handle=object('Pal-A')
    local menu=object('Menu',{CurrentHandle=handle})
    local state={Session={Menu=menu},Controller=object('Controller',{HasAuthority=function() return true end}),
        Handle=handle,HandleKey='Pal-A',Parameter=parameter,Sources={{Object=bag,Backpack=true}},
        Stock=Plan.copy({[ids[3]]=1}),Current={0,0,0,0},Schedule={{Item=ids[1],Count=1}},
        Limits=Plan.copy({[ids[1]]=99,[ids[2]]=99,[ids[3]]=99,[ids[4]]=99}),Slots={}}
    for i,o in ipairs(objects) do state.Slots[i]={Object=o,Key=o:GetFullName(),Item=o.ItemId.StaticId:ToString(),Count=o.StackCount,Backpack=true} end
    local operation=object('Operation',{GetCurrentStatusRank=function(_,p,stat) return p.SaveParameter[fields[stat]] end,
        GetRequiredItemCountForCharacterStatus=function(_,_,_,ranks,out)
            if failure=='missing_output' then return end
            if failure=='unknown_item' then out.RequiredItems={UnknownItem=1}; return end
            out.RequiredItems={
                [{get=function() return fname(ids[1]) end}]={get=function() return failure=='cost' and 2 or ranks[1] end}
            }
        end})
    local utility=object('Utility',{CollectLocalPlayerControllableItemInfos=function(_,_,_,out)
        out.OutItemInfos={}
        for _,o in ipairs(objects) do if Plan.weight[o.ItemId.StaticId:ToString()] and o.StackCount>0 then
            out.OutItemInfos[#out.OutItemInfos+1]={StaticItemId=o.ItemId.StaticId,Num=o.StackCount}
        end end
    end})
    local n=0
    local runtime=Runtime.new({StaticFindObject=function(path)
        return path:find('PalCharacterStatusOperation',1,true) and operation or utility
    end,FName=function(s)
        n=n+1
        if failure=='write' and n==6 then error('Injected second write failure') end
        return fname(s)
    end})
    function runtime:read() return state end
    menu['Invoke Rankup']=function(_,ranks)
        parameter.SaveParameter.Rank_Attack=ranks[1]
        objects[1].StackCount=objects[1].StackCount-1
        if failure=='request' then error('Injected native request failure') end
    end
    local service=Service.new(runtime)
    local result=service:submit(state.Session,{1,0,0,0},'Pal-A',{0,0,0,0})
    if failure=='none' then
        assert(result and parameter.SaveParameter.Rank_Attack==1)
        assert(objects[1].ItemId.StaticId:ToString()==ids[1] and objects[1].StackCount==1)
        assert(objects[2].ItemId.StaticId:ToString()==ids[2] and objects[2].StackCount==1)
    else
        assert(not result and parameter.SaveParameter.Rank_Attack==0)
        assert(objects[1].ItemId.StaticId:ToString()==ids[3] and objects[1].StackCount==1)
        assert(objects[2].ItemId.StaticId:ToString()=='None' and objects[2].StackCount==0)
        if failure=='cost' or failure=='missing_output' or failure=='unknown_item' then
            assert(n==4 and not service.disabled,'Invalid native bills must fail before inventory writes')
        end
    end
end
local screenshotPlan=assert(Plan.prepare(Plan.copy({[ids[3]]=30}),Plan.copy({[ids[1]]=10,[ids[2]]=3})))
assert(screenshotPlan.Remaining[ids[3]]==26 and screenshotPlan.Cost==16,
    'Thirty large souls can pay ten small plus three medium souls, leaving twenty-six large')
print('Verified runtime slot writes, pre-mutation native cost check, partial-write and partial-request restoration.')
