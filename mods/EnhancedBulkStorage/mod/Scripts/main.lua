local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = source:match("^(.*)/Scripts/[^/]+$")
local loader, errorMessage
if directory then
    loader, errorMessage = package.loadlib(directory .. "/dlls/main.dll", "luaopen_EnhancedBulkStorage")
end
if not loader then
    print("[EnhancedBulkStorage] native bridge unavailable; original storage retained: " .. tostring(errorMessage) .. "\n")
    return
end
local ready = loader()
local inventoryClass = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C"
local function unwrap(value)
    local ok, inner = pcall(function() return value:get() end)
    return ok and inner or value
end
local function each(array, callback)
    array:ForEach(function(_, value) callback(unwrap(value)) end)
end

RegisterHook("/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos", function() end,
    function(context, worldContext, staticItemIds, outItemInfos)
        if not ready() then return end
        local world = unwrap(worldContext)
        if not world or not world:IsValid() or not world:IsA(inventoryClass) or world.CurrentInBaseCamp ~= true then return end
        local ok, err = pcall(function()
            local utility = unwrap(context)
            local existing = unwrap(outItemInfos)
            local result, seen = {}, {}
            each(existing, function(info)
                local name = unwrap(info.StaticItemId)
                local id = name:ToString()
                if not seen[id] then
                    result[#result + 1] = { StaticItemId = FName(id), Num = unwrap(info.Num) }
                    seen[id] = true
                end
            end)
            local expanded = false
            -- The native caller supplies the names. Keep its exclusion handling,
            -- slot selection and confirmation; never enumerate equipment or chests.
            each(unwrap(staticItemIds), function(name)
                local id = name:ToString()
                if id ~= "None" and not seen[id] then
                    local count = utility:CountLocalPlayerInventoryItemNum64(world, name)
                    if count > 0 then
                        result[#result + 1] = { StaticItemId = FName(id), Num = math.min(count, 2147483647) }
                        seen[id], expanded = true, true
                    end
                end
            end)
            if not expanded then return end
            -- Release the previous TArray before UE4SS table marshaling replaces it.
            existing:Empty()
            outItemInfos:set(result)
        end)
        if not ok then print("[EnhancedBulkStorage] candidate update failed: " .. tostring(err) .. "\n") end
    end)
print("[EnhancedBulkStorage] official inventory candidate hook registered\n")
