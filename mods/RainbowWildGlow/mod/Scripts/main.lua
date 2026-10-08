local config = require("config")
local REFRESH_MILLISECONDS = 1000
local EFFECT_ID = 47 -- EPalVisualEffectID::WorldTreeAura；原生世界树光晕负责挂载与尺寸。
local RAINBOW_RANK = 4 -- Rank 5 为世界树词条，不能用 >= 判断。
-- NS_RareFishGlow_Purple 原生 RGB=(12.6998,0,100)。
-- 归一化后混入 35% 白色，得到柔和淡紫色，保留原光晕亮度范围。
local LILAC = { R = 0.4325487, G = 0.35, B = 1, A = 1 }
local actors, ranks = {}, {}
local lastError = nil

local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    return ok and inner or value
end

local function valid(value)
    if value == nil then return false end
    local ok, result = pcall(function() return value:IsValid() end)
    return ok and result == true
end

local function track(actor)
    actor = unwrap(actor)
    if not valid(actor) or not actor:IsA("/Script/Pal.PalMonsterCharacter") then return end
    local key = actor:GetFullName()
    if not actors[key] then actors[key] = { actor = actor, key = key } end
end

-- 函数返回的词条数组可能是 Lua 表，也可能是 UE4SS TArray。
local function forEachPassive(parameter, callback)
    local list = parameter:GetPassiveSkillList()
    if type(list) == "table" and type(list.ForEach) ~= "function" then
        for index, name in pairs(list) do
            if type(index) == "number" then callback(index, name) end
        end
    else
        list:ForEach(callback)
    end
end

local function readRank(manager, name)
    name = unwrap(name)
    local id = name:ToString()
    if id == "None" then return nil end
    if ranks[id] ~= nil then return ranks[id] end
    local out = {}
    local found, returned = manager:GetSkillData(name, out)
    if found == false then return nil end
    local rank = out.Rank
    if rank == nil and returned ~= nil then rank = returned.Rank end
    rank = tonumber(unwrap(rank))
    if rank ~= nil then ranks[id] = rank end
    return rank
end

local function qualifies(actor, utility)
    if config.OnlyWildPals ~= false and not utility:IsWildNPC(actor) then return false end
    local component = actor:GetCharacterParameterComponent()
    if not valid(component) then return nil end
    if component:IsDead() then return false end
    local parameter = component:GetIndividualParameter()
    if not valid(parameter) then return nil end
    -- 通过帕鲁身份提前排除稀有，词条列表中再检查 Rare。
    if parameter:IsRarePal() then return false end
    local manager = utility:GetPassiveSkillManager(actor)
    if not valid(manager) then return nil end
    local rainbow, unreadable, excluded = false, false, false
    forEachPassive(parameter, function(_, name)
        local id = unwrap(name):ToString()
        if id ~= "None" then
            if id == "Rare" or id:match("^WorldTree_") then
                excluded = true
            else
                local rank = readRank(manager, name)
                if rank == nil then unreadable = true
                elseif rank == 5 then excluded = true
                elseif rank == RAINBOW_RANK then rainbow = true end
            end
        end
    end)
    -- 混合词条也排除整只帕鲁，避免覆盖或叠加它的原生光晕。
    if excluded then return false end
    if rainbow then return true end
    if unreadable then return nil end
    return false
end

local function removeEffect(entry)
    -- The particle is deliberately detached from the native blueprint's visibility control.
    if valid(entry.particle) then entry.particle:K2_DestroyComponent(false) end
    entry.particle = nil
    if valid(entry.effect) then
        if not entry.effect:IsEndVisualEffect() then
            entry.effect:OnEndVisualEffect()
            entry.effect.bIsEndVisualEffect = true
        end
    end
    entry.effect = nil
end

local function updateParticle(entry)
    -- SpawnEffect 等待帕鲁尺寸初始化后才创建 NiagaraComponent，下一次刷新重试。
    local particle = entry.particle
    if not valid(particle) then
        particle = entry.effect.Effect
        if not valid(particle) then return end
        -- NameProperty requires FName userdata; plain strings can crash UE4SS marshaling.
        particle:SetVariableLinearColor(FName("User.Color"), LILAC)
        -- Native WorldTreeAura continuously applies eligibility/graphics visibility rules.
        -- Keep its completed attachment and scaling, but stop it controlling our component.
        entry.particle = particle
        entry.effect.Effect = nil
    end
    -- 世界树蓝图通过 Activate/Deactivate 控制显示，仅 SetVisibility 不会恢复粒子模拟。
    -- 只处理本 Mod 保存的组件；Activate(false) 保留已运行的模拟，不反复重置。
    particle:SetVisibility(true, true)
    if not particle:IsActive() then
        particle:Activate(false)
    end
end

local function refresh(entry, utility)
    local actor = entry.actor
    local wanted = qualifies(actor, utility)
    if wanted == nil then return end -- 参数尚未同步，稍后重试。
    if wanted then
        if valid(entry.particle) or (valid(entry.effect) and not entry.effect:IsEndVisualEffect()) then
            updateParticle(entry)
            return
        end
        local component = actor.VisualEffectComponent
        if not valid(component) then return end
        -- 原生 BP_VisualEffect_WorldTreeAura 负责主网格挂载和各尺寸缩放参数。
        local effect = component:AddVisualEffect_Local(EFFECT_ID, { FloatValues = {} })
        if not valid(effect) then
            removeEffect(entry)
            error("Native WorldTreeAura visual effect was not created")
        end
        entry.effect = effect
        updateParticle(entry)
    elseif entry.effect ~= nil then
        -- 只结束本 Mod 创建的效果实例，不按 ID 移除其他来源的效果。
        removeEffect(entry)
    end
end

local function tick()
    local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
    if not valid(utility) then return end
    for key, entry in pairs(actors) do
        if not valid(entry.actor) then
            actors[key] = nil
        else
            local ok, err = pcall(refresh, entry, utility)
            if not ok and tostring(err) ~= lastError then
                lastError = tostring(err)
                print("[RainbowWildGlow] retry after error: " .. lastError .. "\n")
            end
        end
    end
end

-- Native post hook: 参数初始化后加入跟踪；周期检查处理捕获与延迟同步。
RegisterHook("/Script/Pal.PalCharacter:LocalInitialized", function() end,
    function(context) pcall(track, context) end)

-- 周期补扫未被初始化钩子发现的帕鲁。
local scanCountdown = 0
local function update()
    if scanCountdown <= 0 then
        for _, actor in ipairs(FindAllOf("PalMonsterCharacter") or {}) do pcall(track, actor) end
        scanCountdown = 5
    end
    scanCountdown = scanCountdown - 1
    tick()
end

if type(LoopInGameThreadWithDelay) == "function" then
    LoopInGameThreadWithDelay(REFRESH_MILLISECONDS, update)
else
    local pending = false
    LoopAsync(REFRESH_MILLISECONDS, function()
        if not pending then
            pending = true
            ExecuteInGameThread(function()
                local ok, err = pcall(update)
                pending = false
                if not ok then print("[RainbowWildGlow] update error: " .. tostring(err) .. "\n") end
            end)
        end
        return false
    end)
end
print("[RainbowWildGlow] v0.9.9 fishing-lilac world tree aura loaded; rainbow rank "
    .. RAINBOW_RANK .. "; WorldTree/Rare excluded; OnlyWildPals="
    .. tostring(config.OnlyWildPals ~= false) .. "\n")
print("[RainbowWildGlow] discovery=LocalInitialized + 5-second fallback scans\n")
