local CLASS='WBP_ExpeditionStatusWorldHUD_C'
local PATH='/Game/Pal/Blueprint/UI/Expedition/WBP_ExpeditionStatusWorldHUD.WBP_ExpeditionStatusWorldHUD_C'
local widgets={}
local created={}
local discovered=false
local queued=false
local warnings=0
local function valid(o) return o and o:IsValid() end
local function update()
    if not BetterExpeditionNativeIsActive or not BetterExpeditionNativeIsActive() then return end
    if not discovered then
        for _,hud in ipairs(FindAllOf(CLASS) or {}) do created[#created+1]=hud end
        discovered=true
    end
    for _,hud in ipairs(created) do
        if valid(hud) then widgets[hud:GetAddress()]=hud end
    end
    created={}
    for address,hud in pairs(widgets) do
        if not valid(hud) then
            widgets[address]=nil
        elseif hud.bAlreadySetup and hud:IsVisible()
            and valid(hud.ConcreteModel) and valid(hud.WBP_PalWork_Expedition) then
            local running,elapsed=BetterExpeditionNativeStatus(hud.ConcreteModel)
            if running then
                -- One refresh per second, outside the blueprint Tick path.
                hud.WBP_PalWork_Expedition:SetRemainSeconds(math.floor(elapsed))
            end
        end
    end
end
-- Creation notification only records wrappers; inspect objects on the game thread.
NotifyOnNewObject(PATH,function(hud) created[#created+1]=hud end)
LoopAsync(1000,function()
    -- Slow game threads must not accumulate queued refreshes.
    if queued then return end
    queued=true
    ExecuteInGameThread(function()
        local ok,err=pcall(update)
        queued=false
        if not ok and warnings<3 then
            warnings=warnings+1
            print('[BetterExpedition] HUD update skipped: '..tostring(err)..'\n')
        end
    end)
end)
