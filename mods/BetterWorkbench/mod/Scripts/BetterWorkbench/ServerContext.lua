local M = {}
local function valid(o) return o and o:IsValid() end
function M.guid(text)
    assert(type(text) == "string" and #text == 32 and text:match("^%x+$"), "invalid workbench identity")
    local guid = {}
    for i, key in ipairs({"A", "B", "C", "D"}) do
        local n = tonumber(text:sub((i-1)*8+1, i*8), 16)
        guid[key] = n >= 0x80000000 and n-0x100000000 or n
    end
    return guid
end
function M.text(guid)
    return ("%08x%08x%08x%08x"):format(guid.A&0xffffffff, guid.B&0xffffffff, guid.C&0xffffffff, guid.D&0xffffffff)
end
function M.read(pc, station, recipe, api)
    api = api or _G
    assert(valid(pc) and pc:HasAuthority(), "server authority required")
    local pawn = pc.Pawn
    assert(valid(pawn) and valid(pawn.Controller) and pawn.Controller:GetAddress() == pc:GetAddress(), "player unavailable")
    local parameter = pawn:GetCharacterParameterComponent()
    assert(valid(parameter) and not parameter:IsDead(), "player unavailable")
    local utility = api.StaticFindObject("/Script/Pal.Default__PalUtility")
    local manager = utility:GetMapObjectManager(pc)
    assert(valid(manager), "workbench manager unavailable")
    -- The concrete crafting model exposes its owner ModelInstanceId. Resolve
    -- that in the parent-model index, then obtain its concrete implementation.
    -- FindConcreteModel uses a different concrete-instance index.
    local owner = manager:FindModel(M.guid(station))
    assert(valid(owner), "workbench owner unavailable")
    local model = owner:GetConcreteModel(true)
    assert(valid(model) and model:IsA("/Script/Pal.PalMapObjectConvertItemModel"), "workbench unavailable")
    assert(M.text(model.ModelInstanceId) == station, "workbench identity mismatch")
    local position, player = model:GetTransform().Translation, pawn:K2_GetActorLocation()
    local distance = (position.X-player.X)^2+(position.Y-player.Y)^2+(position.Z-player.Z)^2
    assert(distance == distance and distance <= 1000^2, "workbench out of reach")
    local security = model:GetGuildSecurityModule()
    if valid(security) then
        assert(valid(pc.PlayerState) and security:CheckGuildSecurityAccess(pc.PlayerState.PlayerUId), "workbench access denied")
    end
    assert(type(recipe) == "string" and #recipe <= 100 and recipe:match("^[%w_]+$"), "invalid recipe")
    return { controller = pc, concrete = model, recipeId = recipe }
end
return M
