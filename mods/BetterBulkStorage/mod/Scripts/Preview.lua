-- One session per official quick-storage entry. All UObject work stays on the
-- game thread, advancing saved cursors; never restart from an inventory change.
return function(d)
    local api, job = {}, nil
    local white, grey = {R=1,G=1,B=1,A=1}, {R=1,G=1,B=1,A=0.5}
    local function key(base)
        local id = d.guid(base:GetId())
        return table.concat({id.A,id.B,id.C,id.D}, ":")
    end
    local function visible(world)
        return d.valid(world) and d.valid(world.Canvas_QuickStack) and world.Canvas_QuickStack:IsVisible()
    end
    local function render(j, entry, allowed)
        if not d.valid(entry.button) or not d.valid(entry.slot) then return end
        if entry.slot:IsEmpty() or entry.slot:GetItemId().StaticId:ToString() ~= entry.id then return end
        allowed = allowed and not j.excluded[entry.id]
        entry.button:SetColorAndOpacity(allowed and white or grey)
        if allowed and not j.added[entry.slot:GetAddress()] then
            j.world.CurrentStackableSlotIds:Add(entry.slot:GetSlotId(), entry.slot)
            j.added[entry.slot:GetAddress()] = true
            j.addedCount=j.addedCount+1
        elseif not allowed and j.added[entry.slot:GetAddress()] then
            j.world.CurrentStackableSlotIds:Remove(entry.slot:GetSlotId())
            j.added[entry.slot:GetAddress()] = nil
            j.addedCount=j.addedCount-1
        end
    end
    function api:stop(restore)
        local previous = job
        job = nil
        d.activate(nil)
        if restore and previous and d.valid(previous.world) then
            previous.world.CurrentStackableSlotIds:Empty()
            for _, entry in ipairs(previous.entries) do
                if d.valid(entry.button) then entry.button:SetColorAndOpacity(white) end
            end
        end
    end
    function api:arm(world)
        self:stop(true)
        job = {world=world,entries={},added={},addedCount=0,excluded={},cache={}}
        d.activate(world)
    end
    -- UE4SS only registers its callback Lua states. User-created coroutine
    -- states cannot call reflected UObject methods/properties. Each phase runs
    -- directly in the scheduled game-thread callback and saves its cursor.
    local function initialize(j)
        if j.world.CurrentInBaseCamp~=true then error("storage is not enabled for this base") end
        local pal=StaticFindObject("/Script/Pal.Default__PalUtility")
        j.base,j.remote=d.resolveTarget(j.world)
        if not d.valid(pal) or not d.valid(j.base) then error("no storage destination") end
        j.baseKey=key(j.base)
        j.items=pal:GetItemIDManager(j.world)
        local state=pal:GetLocalPlayerState(j.world)
        if not d.valid(j.items) or not d.valid(state) then error("inventory data unavailable") end
        j.record=state:GetLocalRecordData()
        if not d.valid(j.record) then error("exclusion list unavailable") end
        if not j.remote then
            j.maps=pal:GetMapObjectManager(j.world)
            local controller=pal:GetLocalPalPlayerController(j.world)
            if not d.valid(j.maps) or not d.valid(controller) then error("base data unavailable") end
            j.uid=d.guid(controller:GetPlayerUId())
        end
        j.cursor=1
        j.containers,j.seen={},{}
        j.containerRecords,j.resolvedChests=0,0
        j.phase="exclusions"
    end
    local function nextArray(j,array,callback)
        if j.cursor>array:GetArrayNum() then j.cursor=1; return false end
        local value=d.unwrap(array[j.cursor])
        j.cursor=j.cursor+1
        callback(value)
        return true
    end
    local function addChest(j)
        local module=j.chest:GetItemContainerModule()
        if not d.valid(module) then return end
        local container=module:GetContainer()
        if not d.valid(container) or j.seen[container:GetAddress()] then return end
        j.seen[container:GetAddress()]=true
        j.containers[#j.containers+1]={container=container,slots={},nextSlot=1}
    end
    local function finishItem(j,allowed)
        j.cache[j.entry.id]=allowed
        render(j,j.entry,allowed)
        j.phase="buttons"
    end
    local function matches(j,slot)
        if not d.valid(slot) or not d.valid(j.data) then return false end
        if not slot:IsEmpty() then
            if slot:IsMaxStack() then return false end
            local item=slot:GetItemId()
            if item.StaticId:ToString()~=j.entry.id or d.nonzero(item.DynamicId.LocalIdInCreatedWorld) then return false end
        end
        return d.slotAllows(slot:GetAddress(),j.data:GetAddress())
    end
    local function step(j)
        if j.phase=="initialize" then initialize(j)
        elseif j.phase=="exclusions" then
            if not nextArray(j,j.record.Local_ItemQuickMoveExceptionIDList,function(name)
                j.excluded[name:ToString()]=true
            end) then j.phase=j.remote and "getButtons" or "modules" end
        elseif j.phase=="modules" then
            if not nextArray(j,j.base.ModuleArray,function(module)
                if d.valid(module) and module:IsA("/Script/Pal.PalBaseCampModuleItemStorage") then j.storage=module end
            end) then
                if not d.valid(j.storage) then error("base storage index unavailable") end
                j.phase="containers"
            end
        elseif j.phase=="containers" then
            if not nextArray(j,j.storage.ContainerInfos,function(info)
                j.containerRecords=j.containerRecords+1
                -- This index stores concrete-model IDs, not parent model IDs.
                local chest=j.maps:FindConcreteModel(d.guid(info.OwnerMapObjectConcreteModelInstanceId))
                if d.valid(chest) then j.resolvedChests=j.resolvedChests+1 end
                if not d.valid(chest) or not chest:IsA("/Script/Pal.PalMapObjectItemChestModel")
                    or not d.sameGuid(chest:GetBaseCampIdBelongTo(),j.base:GetId())
                    or chest:IsLockedPrivateByNot(j.uid) then return end
                local security=chest:GetGuildSecurityModule()
                if d.valid(security) and not security:CheckGuildSecurityAccess(j.uid) then return end
                j.chest=chest
                local lock=chest:GetPasswordLockModule()
                if d.valid(lock) and d.unwrap(lock:GetLockState())==0 then
                    j.lock,j.lockCursor,j.unlocked=lock,1,false
                    j.phase="password"
                else addChest(j) end
            end) then j.phase="getButtons" end
        elseif j.phase=="password" then
            if not d.valid(j.chest) or not d.valid(j.lock) then j.phase="containers"; return end
            local infos=j.lock.PlayerInfos
            if j.lockCursor<=infos:GetArrayNum() then
                local info=d.unwrap(infos[j.lockCursor]); j.lockCursor=j.lockCursor+1
                if d.sameGuid(info.PlayerUId,j.uid) and d.unwrap(info.TrySuccessCache)==true then j.unlocked=true end
            else
                if j.unlocked then addChest(j) end
                j.phase="containers"
            end
        elseif j.phase=="getButtons" then
            local output={}
            j.world.WBP_PalPlayerInventoryScrollList:GetItemSlotButtons(0,output)
            -- Array OutParm reuses the supplied table and populates numeric
            -- entries; unlike UObject OutParm it adds no property-name key.
            -- Unwrap RemoteUnrealParam entries while the output is fresh.
            j.buttons={}
            for i,button in ipairs(output) do j.buttons[i]=d.unwrap(button) end
            j.buttonCursor=1
            j.phase="buttons"
        elseif j.phase=="buttons" then
            if j.buttonCursor>#j.buttons then j.phase="done"; return end
            local button=d.unwrap(j.buttons[j.buttonCursor]); j.buttonCursor=j.buttonCursor+1
            if not d.valid(button) then return end
            local target={}; button:GetTargetSlot(target)
            local slot=target.TargetSlot
            if not d.valid(slot) or slot:IsEmpty() then return end
            local name=slot:GetItemId().StaticId
            local entry={button=button,slot=slot,id=name:ToString()}
            j.entries[#j.entries+1]=entry
            button:SetColorAndOpacity(grey)
            j.entry=entry
            if j.cache[entry.id]~=nil then render(j,entry,j.cache[entry.id]); return end
            j.data=j.items:GetStaticItemData(name)
            if not d.valid(j.data) or (j.data:HasDynamicItemClass() and d.unwrap(j.data.TypeB)~=30) then
                finishItem(j,false)
            elseif j.remote then finishItem(j,true)
            else j.chestCursor=1; j.phase="acceptContainer" end
        elseif j.phase=="acceptContainer" then
            if not d.valid(j.data) or j.chestCursor>#j.containers then finishItem(j,false); return end
            j.currentChest=j.containers[j.chestCursor]; j.chestCursor=j.chestCursor+1
            local container=j.currentChest.container
            if d.valid(container) and d.containerAllows(container:GetAddress(),j.data:GetAddress()) then
                j.slotCursor=1; j.phase="cachedSlots"
            end
        elseif j.phase=="cachedSlots" then
            local chest=j.currentChest
            if not d.valid(chest.container) then j.phase="acceptContainer"; return end
            if j.slotCursor>#chest.slots then j.phase="newSlots"; return end
            local slot=chest.slots[j.slotCursor]; j.slotCursor=j.slotCursor+1
            if matches(j,slot) then finishItem(j,true) end
        elseif j.phase=="newSlots" then
            local chest=j.currentChest
            if not d.valid(chest.container) or not d.valid(j.data) then j.phase="acceptContainer"; return end
            local slots=chest.container.ItemSlotArray
            if chest.nextSlot>slots:GetArrayNum() then j.phase="acceptContainer"; return end
            local slot=d.unwrap(slots[chest.nextSlot]); chest.nextSlot=chest.nextSlot+1
            if not d.valid(slot) then return end
            local usable=slot:IsEmpty()
            if not usable and not slot:IsMaxStack() then
                usable=not d.nonzero(slot:GetItemId().DynamicId.LocalIdInCreatedWorld)
            end
            if usable then
                chest.slots[#chest.slots+1]=slot
                if matches(j,slot) then finishItem(j,true) end
            end
        end
    end
    local function tick(j)
        if job~=j then return end
        if not visible(j.world) then api:stop(false); return end
        local ok,err=pcall(function()
            if j.baseKey then
                local base,remote=d.resolveTarget(j.world)
                if not d.valid(base) or key(base)~=j.baseKey or remote~=j.remote then
                    api:stop(true); return
                end
            end
            local deadline=d.now()+1.5
            for _=1,32 do
                step(j)
                if j.phase=="done" then
                    print("[BetterBulkStorage] incremental preview completed: "..#j.entries.." inventory slots checked, "..j.addedCount.." selected, "..#j.containers.." usable containers, "..j.resolvedChests.."/"..j.containerRecords.." concrete models resolved\n")
                    return
                end
                if d.now()>=deadline then break end
            end
            if job==j then d.defer(function() tick(j) end) end
        end)
        if not ok then
            api:stop(true)
            print("[BetterBulkStorage] incremental preview stopped: "..tostring(err).."\n")
        end
    end
    function api:opened(world)
        if not job or job.world:GetAddress()~=world:GetAddress() then return end
        if not visible(world) then self:stop(false); return end
        world.CurrentStackableSlotIds:Empty()
        local current=job
        current.phase="initialize"
        d.defer(function() tick(current) end)
    end
    function api:excludeChanged(record,name,excluded)
        if not job or not job.record or job.record:GetAddress()~=record:GetAddress() then return end
        local id=name:ToString()
        job.excluded[id]=excluded or nil
        for _,entry in ipairs(job.entries) do
            if entry.id==id then render(job,entry,job.cache[id]==true) end
        end
    end
    return api
end
