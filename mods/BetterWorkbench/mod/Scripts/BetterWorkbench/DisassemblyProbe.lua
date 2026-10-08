-- Explicit one-shot, read-only reflection probe. Not started by main.lua.
-- No hooks, timers, UObject instance traversal, inventory queries or writes.
local M = {}
local classes = {
    "PalPlayerInventoryData", "PalNetworkPlayerComponent", "PalPlayerController",
    "PalItemUtility", "PalItemContainer", "PalItemContainerManager", "PalPlayerState",
    "PalCharacterUtility",
}
local wanted = {
    RequestAddItem_ToServer = true, AddItem_ServerInternal = true,
    RequestConsumeInventoryItem = true, RequestConsumeItem = true,
    GetInventoryContainers = true, TryGetInventoryContainer = true,
    TryGetContainerIdFromItemType = true, RequestMoveItemToInventoryFromContainer = true,
    RequestSellItems_ToServer = true, RequestUseItemToCharacter_ToServer = true,
    RequestConsumeItemsByPlayerControllableItems_ServerInternal = true,
}
function M.run(api, options)
    api = api or _G
    local function log(message) print("[BetterWorkbench:DisassemblyProbe] " .. message .. "\n") end
    local seen, structs = {}, {}
    local function propertySchema(property)
        local schema = property:GetFullName()
        if schema:match("^ArrayProperty ") then
            local inner = property:GetInner()
            schema = schema .. " inner=" .. inner:GetFullName()
            if inner:GetFullName():match("^StructProperty ") then
                local struct = inner:GetStruct()
                if #structs < 16 then structs[#structs + 1] = struct end
            end
        elseif schema:match("^StructProperty ") then
            local struct = property:GetStruct()
            schema = schema .. " type=" .. struct:GetFullName()
            if #structs < 16 then structs[#structs + 1] = struct end
        end
        return schema
    end
    for _, name in ipairs(classes) do
        local path = "/Script/Pal." .. name
        local ok, problem = pcall(function()
            local class = api.StaticFindObject(path)
            if not class or not class:IsValid() then log("MISSING " .. path); return end
            log("CLASS " .. class:GetFullName())
            local functions = 0
            class:ForEachFunction(function(func)
                local functionName = func:GetFName():ToString()
                local operation = options and options.ListOperations and
                    (functionName:find("Item", 1, true) or functionName:find("Container", 1, true))
                if not wanted[functionName] and not operation then return end
                functions = functions + 1
                if functions > 64 then return end
                log("FUNCTION " .. func:GetFullName() .. " flags=" .. tostring(func:GetFunctionFlags()))
                func:ForEachProperty(function(property) log("PARAM " .. propertySchema(property)) end)
            end)
        end)
        if not ok then log("ERROR " .. path .. " " .. tostring(problem)) end
    end
    -- Only direct struct fields; do not recurse through arbitrary schemas.
    for _, struct in ipairs(structs) do
        local ok, problem = pcall(function()
            local name = struct:GetFullName()
            if seen[name] then return end
            seen[name] = true
            log("STRUCT " .. name)
            local count = 0
            struct:ForEachProperty(function(property)
                count = count + 1
                if count <= 32 then log("FIELD " .. property:GetFullName()) end
            end)
        end)
        if not ok then log("ERROR struct " .. tostring(problem)) end
    end
    log("DONE read_only=true")
end
return M
