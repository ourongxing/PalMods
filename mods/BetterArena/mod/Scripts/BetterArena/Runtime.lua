local Rewards=require('BetterArena.Rewards')
local M={}
local function valid(o) return o and o:IsValid() end
local function value(o)
    local ok,v=pcall(function() return o:get() end)
    return ok and v or o
end
local function integer(n,min,max)
    assert(type(n)=='number' and n%1==0 and n>=min and n<=max,'invalid engine value')
    return n
end
local function guid(g)
    return ('%08x%08x%08x%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)
end
local function stringValue(s) return type(s)=='string' and s or s:ToString() end
function M.new(api)
    api=api or _G
    local self={}
    function self:read(menu,selectedRank)
        assert(valid(menu) and menu:IsVisible(),'arena menu closed')
        local controller=menu:GetOwningPlayer()
        assert(valid(controller) and controller:HasAuthority(),'host only')
        local u=api.StaticFindObject('/Script/Pal.Default__PalUtility')
        local player=u:GetPalmi(controller)
        assert(valid(player),'player unavailable')
        local component=player:GetCharacterParameterComponent()
        assert(valid(component) and not component:IsDead(),'player unavailable')
        local parameter=component:GetIndividualParameter()
        assert(valid(parameter) and not parameter:IsInArena(),'battle in progress')
        local state=controller.PlayerState
        assert(valid(state),'player state unavailable')
        local record=state:GetRecordData()
        assert(valid(record),'record unavailable')
        local highest,cleared=nil,{}
        local ranks={Bronze=1,Silver=2,Gold=3,Platinum=4,Diamond=5,Master=6,Legend=7}
        -- Do not pass the outer thread-safe record struct through Lua UFunction
        -- marshalling: it contains native synchronization primitives. Read only
        -- its reflected Items entries, on the game thread, without copying it.
        local entries=record.ArenaSoloClearCount.Items
        assert(entries:GetArrayNum()<=64,'invalid clear record')
        entries:ForEach(function(_,entry)
            entry=value(entry)
            local rank=ranks[entry.Key:ToString()]
            if rank and integer(entry.Value,0,2147483647)>0 then cleared[rank]=true;highest=math.max(highest or 0,rank) end
        end)
        if selectedRank~=nil then
            integer(selectedRank,1,7)
            assert(cleared[selectedRank],'challenge not cleared')
        end
        local game=u:GetPalGameStateInGame(controller)
        assert(valid(game),'world unavailable')
        local world=stringValue(game:GetWorldSaveDirectoryName())
        assert(world:match('^[%x]+$') and #world==32,'world identity unavailable')
        require('BetterArena.Balance').requireReady(world)
        local uid=guid(state.PlayerUId)
        assert(uid~=string.rep('0',32),'player identity unavailable')
        local day=integer(u:GetTimeManager(controller):GetCurrentPalWorldTime_TotalDay(),0,100000000)
        local rank=integer(parameter:GetArenaRank(),0,6)+1
        local arena=u:GetArenaWorldSubsystem(controller)
        local inventory=state:GetInventoryData()
        local setting=u:GetGameSetting(controller)
        assert(valid(arena) and valid(inventory) and valid(setting),'arena unavailable')
        return {identity=world..'_'..uid,day=day,playerRank=rank,challengeRank=selectedRank or highest,cleared=cleared,
            menu=menu,controller=controller,parameter=parameter,arena=arena,inventory=inventory,setting=setting,
            points=integer(parameter:GetArenaRankPoint(),0,2000000000)}
    end
    function self:prepare(c)
        local rows={}
        local rewards=c.arena:GetSoloClearReward(c.challengeRank-1,false)
        local function add(row)
            rows[#rows+1]={id=row.ItemName.Key:ToString(),rate=row.Rate,min=row.Min,max=row.Max}
        end
        if type(rewards)=='table' then for _,row in ipairs(rewards) do add(value(row)) end
        else rewards:ForEach(function(_,row) add(value(row)) end) end
        assert(#rows>0 and #rows<=32,'reward table unavailable')
        local rates={}
        c.setting.Arena_RankPointDiffRate:ForEach(function(k,v) rates[value(k)]=value(v) end)
        local points=Rewards.points(c.setting.Arena_RankPoint_WinToNPC,c.playerRank,c.challengeRank,rates)
        assert(c.points+points<=2000000000,'rank points overflow')
        local items=Rewards.roll(rows)
        self:checkSpace(c,items)
        assert(c.parameter.SaveParameter.ArenaRankPoint==c.points,'rank parameter changed')
        assert(type(c.parameter.OnUpdateArenaRankPointDelegate.Broadcast)=='function','rank notification unavailable')
        return {items=items,points=points}
    end
    function self:checkSpace(c,items)
        local utility=api.StaticFindObject('/Script/Pal.Default__PalUtility')
        local manager=utility:GetItemIDManager(c.controller)
        assert(valid(manager),'item manager unavailable')
        local containers={}
        for id,count in pairs(items) do
            if count>0 then
                local out={}
                assert(c.inventory:TryGetContainerFromStaticItemID(api.FName(id),out) and valid(out.OutContainer),'inventory unavailable')
                local container=out.OutContainer
                local key=container:GetFullName()
                local bucket=containers[key]
                if not bucket then
                    bucket={empty=0,required=0,slots={}};containers[key]=bucket
                    for index=0,integer(container:Num(),0,4096)-1 do
                        local slot=container:Get(index)
                        if valid(slot) then
                            if slot.StackCount==0 then bucket.empty=bucket.empty+1
                            else bucket.slots[#bucket.slots+1]=slot end
                        end
                    end
                end
                local remaining=count
                for _,slot in ipairs(bucket.slots) do
                    if slot.ItemId.StaticId:ToString()==id then
                        remaining=math.max(0,remaining-math.max(0,slot:GetMaxStack()-slot.StackCount))
                    end
                end
                local data=manager:GetStaticItemData(api.FName(id))
                assert(valid(data),'reward item unavailable')
                local maxStack=integer(data:GetMaxStackCount(),1,1000000000)
                bucket.required=bucket.required+math.ceil(remaining/maxStack)
            end
        end
        for _,bucket in pairs(containers) do assert(bucket.empty>=bucket.required,'inventory full') end
    end
    function self:award(c,plan)
        local current=self:read(c.menu,c.challengeRank)
        assert(current.identity==c.identity and current.day==c.day and current.points==c.points and current.challengeRank==c.challengeRank,'arena context changed')
        for id,count in pairs(plan.items) do
            if count>0 then
                local result=c.inventory:AddItem_ServerInternal(api.FName(id),count,true,0.0,true)
                assert(result==0,'reward delivery failed')
            end
        end
        -- The controller's Debug_SetArenaRankPoint is a no-op in this shipping
        -- build. Update the reflected saved integer on the authoritative game
        -- thread and broadcast the same native delegate used by real wins.
        c.parameter.SaveParameter.ArenaRankPoint=c.points+plan.points
        c.parameter.OnUpdateArenaRankPointDelegate:Broadcast(c.parameter,c.points+plan.points)
        assert(c.parameter:GetArenaRankPoint()==c.points+plan.points,'rank update failed')
    end
    return self
end
return M
