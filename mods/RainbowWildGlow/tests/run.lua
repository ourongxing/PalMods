package.path = PROJECT_ROOT .. '/mod/Scripts/?.lua;' .. package.path
-- Emulate the UE4SS NameProperty contract rather than accepting plain strings.
local nameMeta = {}
function FName(text)
    assert(type(text) == 'string')
    return setmetatable({ToString=function() return text end}, nameMeta)
end
local function assertColorName(name)
    assert(getmetatable(name) == nameMeta, 'Niagara color parameter must be FName userdata')
    assert(name:ToString() == 'User.Color')
end
local function object(t)
    t = t or {}
    function t:IsValid() return not self.invalid end
    return t
end
local adds, ends = 0, 0
local utility = object()
function utility:IsWildNPC(actor) return actor.wild end
function utility:IsBaseCampPal(actor) return actor.base == true end
function utility:GetPassiveSkillManager() return self.manager end
local player = object()
function player:K2_GetActorLocation() return {X=0,Y=0,Z=0} end
function utility:GetPlayerCharacterByPlayerIndex(_, index) assert(index == 0); return player end
utility.manager = object()
local skillRanks = { Rare=4, WorldTree_ATK=5, WorldTree_MoveSpeed=5 }
function utility.manager:GetSkillData(name, out)
    if name.id == 'pending' then return false end
    out.Rank = skillRanks[name.id] or tonumber(name.id)
    return true
end
local function pal(id, rank, wild, rare)
    local a = object({id=id, wild=wild, rare=rare, rank=rank})
    function a:GetFullName() return self.id end
    function a:K2_GetActorLocation() return {X=self.x or 500,Y=0,Z=0} end
    function a:IsA(path) return path == '/Script/Pal.PalMonsterCharacter' end
    a.parameter = object()
    function a.parameter:IsRarePal() return a.rare end
    function a.parameter:GetPassiveSkillList()
        if PLAIN_PASSIVE_LIST then
            if a.unready then error('parameter not ready') end
            local list = {}
            for index, id in ipairs(a.skills or {a.rank}) do
                list[index] = {id=id, ToString=function(self) return self.id end}
            end
            return list
        end
        return {ForEach=function(_, callback)
            if a.unready then error('parameter not ready') end
            for index, id in ipairs(a.skills or {a.rank}) do
                callback(index, {get=function() return {id=id, ToString=function(self) return self.id end} end})
            end
        end}
    end
    a.component = object()
    function a.component:IsDead() return a.dead == true end
    function a.component:GetIndividualParameter() return a.parameter end
    function a:GetCharacterParameterComponent() return self.component end
    a.VisualEffectComponent = object()
    function a.VisualEffectComponent:AddVisualEffect_Local(id, params)
        assert(id == 47 and type(params.FloatValues) == 'table')
        if a.failEffect then return nil end
        adds = adds + 1
        local e = object({active=true})
        if not a.delayParticle then
            e.Effect = object({colorCalls=0, active=false, activateCalls=0})
            function e.Effect:K2_DestroyComponent() self.invalid=true; self.active=false end
            function e.Effect:IsActive() return self.active end
            function e.Effect:Activate(reset)
                assert(reset == false, 'activation must not reset a running simulation')
                self.active = true
                self.activateCalls = self.activateCalls + 1
            end
            function e.Effect:SetVariableLinearColor(name, color)
                assertColorName(name)
                assert(math.abs(color.R - 0.4325487) < 0.0000001 and color.G == 0.35 and color.B == 1 and color.A == 1)
                self.colorCalls = self.colorCalls + 1
                self.lilac = true
            end
            function e.Effect:SetVisibility(visible, propagate)
                assert(visible and propagate)
                self.visible = visible
            end
        end
        function e:IsEndVisualEffect() return self.bIsEndVisualEffect == true end
        function e:OnEndVisualEffect() self.active=false; self.invalid=true; ends=ends+1 end
        a.particle = e.Effect
        a.effect = e
        return e
    end
    return a
end
local gold = pal('gold', '3', true, false)
local rainbow = pal('rainbow', '4', true, false)
local owned = pal('owned', '4', false, false)
local lucky = pal('lucky', '4', true, true)
local deferred = pal('deferred', 'pending', true, false)
local worldTree = pal('world-tree', 'WorldTree_ATK', true, false)
local worldTreeMixed = pal('world-tree-mixed', '4', true, false)
worldTreeMixed.skills = {'4', 'WorldTree_MoveSpeed'}
local rareTrait = pal('rare-trait', 'Rare', true, false)
local rareMixed = pal('rare-mixed', '4', true, false)
rareMixed.skills = {'4', 'Rare'}
local rankFive = pal('rank-five', '5', true, false)
local rankSix = pal('rank-six', '6', true, false)
local collection = {gold, rainbow, owned, lucky, deferred, worldTree, worldTreeMixed,
    rareTrait, rareMixed, rankFive, rankSix}
local hook, tick
function StaticFindObject(path)
    assert(path == '/Script/Pal.Default__PalUtility')
    return utility
end
function FindAllOf(name) assert(name == 'PalMonsterCharacter'); return collection end
function RegisterHook(path, pre, post)
    assert(path == '/Script/Pal.PalCharacter:LocalInitialized')
    assert(pre and post); hook = post
end
function LoopInGameThreadWithDelay(ms, callback) assert(ms == 1000); tick = callback end
dofile(PROJECT_ROOT .. '/mod/Scripts/main.lua')
tick()
assert(adds == 1, 'only wild rank 4 should glow')
tick(); assert(adds == 1, 'effect must not be duplicated')
tick(); assert(rainbow.effect.active and adds == 1, 'native wrapper must not be respawned each tick')
assert(rainbow.particle.lilac and rainbow.particle.colorCalls == 1,
    'only the created particle instance is colored, once per instance')
assert(rainbow.effect.Effect == nil, 'native blueprint must relinquish its particle reference')
assert(rainbow.particle.active and rainbow.particle.activateCalls == 1,
    'inactive native aura must be activated without repeated simulation resets')
deferred.rank = '4'; tick(); assert(adds == 2, 'unknown skill must retry')
for _, excluded in ipairs({worldTree, worldTreeMixed, rareTrait, rareMixed, rankFive, rankSix}) do
    assert(excluded.effect == nil, 'WorldTree/Rare and non-rank-4 pals must not receive lilac aura')
end
rainbow.wild = false; tick(); assert(ends == 1, 'capture must end our effect')
deferred.dead = true; tick(); assert(ends == 2, 'death must end our effect')
assert(lucky.effect == nil and owned.effect == nil)
local spawned = pal('spawned', '4', true, false)
spawned.unready = true
hook({get=function() return spawned end})
tick(); assert(adds == 2)
spawned.unready = false; spawned.failEffect = true
tick(); assert(adds == 2)
spawned.failEffect = false; tick(); assert(adds == 3, 'failed effect creation must retry')
spawned.rank = '3'; tick(); assert(ends == 3, 'loss of rainbow skill must remove effect')
spawned.invalid = true; tick()
owned.dead = false; owned.base = true
tick(); assert(adds == 3, 'base pals must remain excluded ')
owned.base = false
tick(); assert(adds == 3, 'party pals must remain excluded ')
owned.base = true; owned.rank = '3'
tick(); assert(adds == 3, 'base pals must remain excluded regardless of passive rank')
local delayed = pal('delayed-aura', '4', true, false)
delayed.delayParticle = true
hook({get=function() return delayed end}); tick()
assert(delayed.effect.active and not delayed.effect.Effect, 'wait for native size initialization')
local particle = object({colorCalls=0, active=false})
function particle:K2_DestroyComponent() self.invalid=true; self.active=false end
function particle:SetVisibility(visible) self.visible = visible end
function particle:IsActive() return self.active end
function particle:Activate(reset) assert(reset == false); self.active = true end
function particle:SetVariableLinearColor(name, color)
    assertColorName(name)
    assert(color.G == 0.35 and math.abs(color.R - 0.4325487) < 0.0000001 and color.B == 1)
    self.colorCalls = self.colorCalls + 1
end
delayed.effect.Effect = particle
tick(); assert(particle.colorCalls == 1, 'color particle after deferred initialization')
tick(); assert(particle.colorCalls == 1, 'do not reset parameters every tick')
assert(delayed.effect.Effect == nil and particle.visible and particle.active,
    'detached component must remain visible and active independently of the blueprint')
particle.active = false
tick(); assert(particle.active, 'native visibility deactivation must be recovered')
particle.invalid = true
local replacement = object({colorCalls=0, active=false, K2_DestroyComponent=particle.K2_DestroyComponent,
    SetVariableLinearColor=particle.SetVariableLinearColor,
    SetVisibility=particle.SetVisibility, IsActive=particle.IsActive, Activate=particle.Activate})
delayed.effect.Effect = replacement
tick(); assert(replacement.colorCalls == 1, 'recreated particle component must also turn lilac')
local otherSource = object({active=true})
delayed.otherEffect = otherSource
delayed.wild = false; tick()
assert(not delayed.effect.active and otherSource.active and replacement.invalid, 'capture destroys our detached particle and ends only our wrapper')
local destroyed = pal('destroyed-aura', '4', true, false)
hook({get=function() return destroyed end}); tick()
destroyed.invalid = true; tick()
assert(otherSource.active, 'natural effects remain untouched')
local changed = pal('changed-traits', '4', true, false)
hook({get=function() return changed end}); tick()
local beforeExclusion = ends
changed.skills = {'4', 'WorldTree_ATK'}; tick()
assert(ends == beforeExclusion + 1 and changed.particle.invalid,
    'new WorldTree trait must remove an existing lilac aura even alongside rainbow traits')
changed.skills = {'4'}; tick()
local beforeRare = ends
changed.skills = {'4', 'Rare'}; tick()
assert(ends == beforeRare + 1 and changed.particle.invalid,
    'new Rare trait must also remove an existing lilac aura')
local config = require('config')
assert(config.OnlyWildPals == true, 'wild-only display must be enabled by default')
config.OnlyWildPals = false
owned.rank = '4'; owned.base = true
tick()
assert(owned.effect and owned.effect.active, 'disabled wild-only filter must allow base pals')
owned.base = false; tick()
assert(owned.effect.active, 'disabled wild-only filter must allow party pals')
assert(lucky.effect == nil and rareMixed.effect == nil and worldTreeMixed.effect == nil,
    'disabling wild-only filter must preserve Rare/WorldTree exclusions')
config.OnlyWildPals = true; tick()
assert(owned.particle.invalid and not owned.effect.active,
    'enabling wild-only filter must clean up owned pal aura')
local lateOwned = pal('late-owned', '4', false, false)
collection[#collection + 1] = lateOwned
config.OnlyWildPals = false
for _ = 1, 5 do tick() end
assert(lateOwned.effect and lateOwned.particle.active,
    'periodic scan must discover a summoned pal even when initialization hook is missed')
config.OnlyWildPals = true; tick()
assert(lateOwned.particle.invalid, 'wild-only filter must still apply to rescanned pals')
print('RainbowWildGlow lilac world tree aura lifecycle regressions passed')
