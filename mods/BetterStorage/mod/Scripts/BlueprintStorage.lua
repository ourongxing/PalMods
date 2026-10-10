local M = {}
local targets = {Shelf01_Stone = true, Shelf07_Stone = true}
local function valid(object) return object and object:IsValid() end
local function onlyBlueprint(array)
    return #array == 1 and array[1] == 12 -- EPalItemTypeA::Blueprint
end
local function restrict(permission)
    if onlyBlueprint(permission.PermissionTypeA) and #permission.PermissionTypeB == 0
        and #permission.PermissionItemStaticIds == 0 then return end
    permission.PermissionTypeA:Empty()
    permission.PermissionTypeB:Empty()
    permission.PermissionItemStaticIds:Empty()
    permission.PermissionTypeA = {12}
end
function M.start(bridge, scripts)
    local slots = 360
    local ok, config = pcall(function() return assert(loadfile(scripts .. "/config.lua"))() end)
    local value = ok and type(config) == "table" and config.BlueprintChestSlots
    if type(value) == "number" and value == math.floor(value) and value >= 1 and value <= 4096 then
        slots = value
    else
        print("[BetterStorage] invalid BlueprintChestSlots; using 360\n")
    end
    local queued, lastError = false, nil
    local function reconcile()
        -- Templates supply vanilla capacity and permission for new furniture.
        for _, parameter in ipairs(FindAllOf("PalMapObjectItemChestParameterComponent") or {}) do
            if valid(parameter) then
                local path = parameter:GetFullName()
                local id = path:match("/Game/Pal/Blueprint/MapObject/BuildObject/Furniture/BP_BuildObject_([%w_]+)%.")
                if targets[id] then
                    parameter.SlotNum = slots
                    if not onlyBlueprint(parameter.TargetTypesA) or #parameter.TargetTypesB ~= 0 then
                        parameter.TargetTypesA:Empty()
                        parameter.TargetTypesB:Empty()
                        parameter.TargetTypesA = {12}
                    end
                end
            end
        end
        local world = FindFirstOf("PalGameState")
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if not valid(world) or not valid(utility) or not utility:IsServer(world) then return end
        -- Saved models exist independently of streamed furniture actors.
        for _, model in ipairs(FindAllOf("PalMapObjectItemChestModel") or {}) do
            if valid(model) and targets[model:TryGetMapObjectId():ToString()] then
                local module = model:GetItemContainerModule()
                if valid(module) then
                    local container = module:GetContainer()
                    if valid(container) then
                        restrict(container.Permission)
                        local count, err = bridge.growBlueprintStorage(world:GetAddress(), model:GetAddress(), slots)
                        if not count then error(err) end
                        module.DisplayContainerSlotNumDefault = slots
                    end
                end
            end
        end
    end
    local function queue()
        if queued then return end
        queued = true
        ExecuteInGameThread(function()
            local ok, err = pcall(reconcile)
            queued = false
            if not ok and err ~= lastError then
                lastError = err
                print("[BetterStorage] blueprint storage: " .. tostring(err) .. "\n")
            end
        end)
    end
    queue()
    LoopAsync(5000, function() queue(); return false end)
    print("[BetterStorage] blueprint chest capacity: " .. slots .. " (blueprints only, shared with antique large cabinet)\n")
end
return M
