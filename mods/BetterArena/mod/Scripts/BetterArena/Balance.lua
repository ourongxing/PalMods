-- PalSchema owns reward table writes. Only the scalar NPC RP setting is
-- synchronized for the already-created game setting instance after reload.
local M={}
local active
function M.multiplier(config)
 local n=config.RewardMultiplier
 assert(type(n)=='number' and n%1==0 and n>=1 and n<=10,'RewardMultiplier must be an integer from 1 to 10')
 return n
end
function M.requireReady(world)
 assert(active and active.world==world and active.ready,'arena rewards are initializing')
end
function M.start(config,directory,api)
 api=api or _G
 local Schema=require('BetterArena.Schema')
 local base=require('BetterArena.BaseRewards')
 local multiplier=M.multiplier(config)
 local schemaRoot=assert(directory:match('^(.*)/BetterArena$'),'unexpected BetterArena installation path')..'/PalSchema'
 assert(Schema.autoReload(schemaRoot..'/config/config.json'),
  'PalSchema automatic reload enabled. Fully restart Palworld once to finish setup.')
 local raw,points=Schema.patches(base,multiplier)
 active={ready=false};local queued=false;local errors={}
 local function valid(o) return o and o:IsValid() end
 local utility,instance
 api.LoopAsync(500,function()
  if queued then return end;queued=true
  api.ExecuteInGameThread(function()
   local ok,err=pcall(function()
    if not valid(utility) then utility=api.StaticFindObject('/Script/Pal.Default__PalUtility') end
    if not valid(instance) then instance=api.FindFirstOf('PalGameInstance') end
    local u,gi=utility,instance
    if not valid(u) or not valid(gi) then return end
    local controller=u:GetLocalPlayerController(gi)
    if not valid(controller) or not controller:HasAuthority() then return end
    local game=u:GetPalGameStateInGame(controller)
    local arena=u:GetArenaWorldSubsystem(controller)
    local setting=u:GetGameSetting(controller)
    if not valid(game) or not valid(arena) or not valid(setting) then return end
    local name=game:GetWorldSaveDirectoryName()
    local world=type(name)=='string' and name or name:ToString()
    if active.game~=game:GetFullName() or active.world~=world then
     active={game=game:GetFullName(),world=world,ready=false,failed=true,attempts=0}
     -- Ensure the table exists before PalSchema's file watcher applies JSON.
     api.LoadAsset('/Game/Pal/DataTable/Arena/DT_ArenaSoloRewardTable')
     Schema.write(schemaRoot..'/mods/BetterArena/raw/arena_rewards.json',raw)
     Schema.write(schemaRoot..'/mods/BetterArena/blueprints/arena_points.json',points)
     active.failed=false
     print(('[BetterArena] Applying Arena rewards x%d through PalSchema.\n'):format(multiplier))
     return
    end
    if active.ready or active.failed then return end
    active.attempts=active.attempts+1
    if Schema.matches(base,arena,multiplier) then
     -- Blueprint hot reload updates the default object, not this existing
     -- settings instance. This one reflected numeric field is shared by both
     -- normal NPC victories and sweeps; no native reward arrays are written.
     active.failed=true
     setting.Arena_RankPoint_WinToNPC=50*multiplier
     assert(setting.Arena_RankPoint_WinToNPC==50*multiplier,'NPC RP update failed')
     active.ready=true
     active.failed=false
     print(('[BetterArena] Verified all 14 Arena reward lists and NPC victory RP x%d.\n'):format(multiplier))
    elseif active.attempts>=30 then
     active.failed=true
     error('PalSchema reward reload timed out; sweeps remain unavailable')
    end
   end)
   queued=false
   if not ok and not errors[tostring(err)] then
    errors[tostring(err)]=true;print('[BetterArena] '..tostring(err)..'\n')
   end
  end)
 end)
end
return M
