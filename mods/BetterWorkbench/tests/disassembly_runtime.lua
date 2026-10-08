return function(test, equal)
    local Runtime = require("BetterWorkbench.DisassemblyRuntime")
    local Capacity = require("BetterWorkbench.DisassemblyCapacity")
    local Service = require("BetterWorkbench.CraftService")
    local function name(id) return { ToString = function() return id end } end
    local function object(o)
        o.IsValid = function() return true end
        return o
    end
    local function fixture(options)
        options = options or {}
        local records = options.records or { { "Part", 6 }, { "Ingot", 1 }, { "None", 0 }, { "None", 0 } }
        local slots = {}
        for _, row in ipairs(records) do
            slots[#slots + 1] = object({ ItemId = { StaticId = name(row[1]) }, StackCount = row[2],
                OnRep_StackCount = function() end, OnRep_ItemId = function() end })
        end
        local container = object({ GetFullName = function() return "bag" end,
            Num = function() return #slots end, Get = function(_, index) return slots[index + 1] end })
        local inventory = object({ adds = 0 })
        function inventory:TryGetContainerFromInventoryType(kind, out)
            if kind ~= 0 then return false end
            out.OutContainer = container; return true
        end
        function inventory:TryGetContainerFromStaticItemID(_, out) out.OutContainer = container; return true end
        function inventory:AddItem_ServerInternal(id, count, assignPassive, delay, notify)
            assert(assignPassive == true and delay == 0.0 and notify == true,
                "material return must enable the game's acquisition notification")
            self.adds = self.adds + 1
            if options.partial then count = count - 1 end
            for _, slot in ipairs(slots) do
                if slot.StackCount == 0 or slot.ItemId.StaticId:ToString() == id then
                    slot.ItemId.StaticId = name(id)
                    slot.StackCount = slot.StackCount + count
                    return 0
                end
            end
            error("no capacity")
        end
        local manager = object({ GetStaticItemData = function() return object({ MaxStackCount = 100 }) end })
        local utility = object({ GetItemIDManager = function() return manager end })
        local external, baseContainer = {}, nil
        for _, row in ipairs(options.baseRecords or {}) do
            external[#external + 1] = object({ ItemId = { StaticId = name(row[1]) }, StackCount = row[2],
                OnRep_StackCount = function() end, OnRep_ItemId = function() end })
        end
        if #external > 0 then
            container.OnRep_ItemSlotArray = function() end
            baseContainer = object({ GetFullName = function() return "base" end,
                OnRep_ItemSlotArray = function() end, Num = function() return #external end,
                Get = function(_, index) return external[index + 1] end })
        end
        local backend = Runtime.new({ FName = function(id) return id end, StaticFindObject = function() return utility end })
        function backend:read()
            local totals, snapshot = {}, {}
            for index, slot in ipairs(slots) do
                local id = slot.StackCount > 0 and slot.ItemId.StaticId:ToString() or "None"
                if slot.StackCount > 0 then totals[id] = (totals[id] or 0) + slot.StackCount end
                snapshot[#snapshot + 1] = { Key = "bag:" .. (index - 1), Container = "bag", Item = id,
                    Count = slot.StackCount, Object = slot }
            end
            local backpackTotals, sourceSnapshot = {}, {}
            for id, count in pairs(totals) do backpackTotals[id] = count end
            for _, slot in ipairs(snapshot) do sourceSnapshot[#sourceSnapshot + 1] = slot end
            for index, slot in ipairs(external) do
                local id = slot.StackCount > 0 and slot.ItemId.StaticId:ToString() or "None"
                if slot.StackCount > 0 then totals[id] = (totals[id] or 0) + slot.StackCount end
                sourceSnapshot[#sourceSnapshot + 1] = { Key = "base:" .. (index - 1), Container = "base", Item = id,
                    Count = slot.StackCount, Object = slot }
            end
            return { Recipes = { Part = { OutputItem = "Part", OutputAmount = 2,
                Materials = { Ingot = 3, Fiber = 1 }, WorkAmount = 20 } }, Inventory = totals,
                Context = { StationRecipes = { Part = true }, canDisassemble = function() return true end } },
                { inventory = inventory, slots = snapshot, controller = {}, backpackTotals = backpackTotals,
                    sourceSlots = sourceSnapshot, sourceContainers = baseContainer and { container, baseContainer } or nil }
        end
        return backend, Service.new(backend), inventory, slots, external
    end
    test("return capacity reserves all materials together without freeing products", function()
        local slots = { { Container = "bag", Item = "Part", Count = 1 },
            { Container = "bag", Item = "None", Count = 0 } }
        local ok, reason = Capacity.check(slots, { A = 1, B = 1 }, { A = "bag", B = "bag" }, { A = 100, B = 100 })
        assert(not ok and reason == "backpack_full")
        equal(slots[2], { Container = "bag", Item = "None", Count = 0 })
        assert(Capacity.check({ { Container = "bag", Item = "A", Count = 99 } },
            { A = 1 }, { A = "bag" }, { A = 100 }))
    end)
    test("runtime native returns are verified and whole product batches consumed", function()
        local backend, service, inventory = fixture()
        local result = assert(service:disassemble({}, "Part", 3))
        equal(result.Returns, { Ingot = 9, Fiber = 3 })
        equal(backend:read().Inventory, { Ingot = 10, Fiber = 3 })
        equal(inventory.adds, 2)
        assert(not backend.busy)
    end)
    test("runtime full backpack rejects before any native write", function()
        local backend, service, inventory = fixture({ records = { { "Part", 6 }, { "Ingot", 1 } } })
        local result, reason = service:disassemble({}, "Part", 3)
        assert(not result and reason == "backpack_full")
        equal(inventory.adds, 0)
        equal(backend:read().Inventory, { Part = 6, Ingot = 1 })
    end)
    test("runtime disassembles base stock and returns materials only to backpack", function()
        local backend, service, _, slots, base = fixture({ records = { { "Part", 2 }, { "None", 0 }, { "None", 0 } },
            baseRecords = { { "Part", 28 }, { "Ingot", 50 } } })
        equal(service:previewDisassembly({}, "Part", 1).OwnedAmount, 30)
        assert(service:disassemble({}, "Part", 15))
        equal(base[1].StackCount, 0); equal(base[2].StackCount, 50)
        equal(backend:read().Inventory, { Ingot = 95, Fiber = 15 })
        equal(slots[2].StackCount + slots[3].StackCount, 60)
    end)
    test("base empty slots cannot provide backpack return capacity", function()
        local _, service, inventory, _, base = fixture({ records = { { "Ingot", 1 } },
            baseRecords = { { "Part", 6 }, { "None", 0 }, { "None", 0 } } })
        local result, reason = service:disassemble({}, "Part", 3)
        assert(not result and reason == "backpack_full")
        equal(inventory.adds, 0); equal(base[1].StackCount, 6)
    end)
    test("runtime partial native return restores counts and disables retries", function()
        local backend, service, inventory = fixture({ partial = true })
        local result, reason = service:disassemble({}, "Part", 3)
        assert(not result and reason:find("native material return mismatch", 1, true))
        equal(backend:read().Inventory, { Part = 6, Ingot = 1 })
        local adds = inventory.adds
        result, reason = service:disassemble({}, "Part", 1)
        assert(not result and reason == "disassembly_disabled_after_inventory_error")
        equal(inventory.adds, adds)
    end)
    test("runtime rollback restores a fully debited product slot after later failure", function()
        local backend, service, _, slots = fixture({ records = { { "Part", 2 }, { "Part", 4 },
            { "Ingot", 1 }, { "None", 0 } } })
        local count, rejected = 4, false
        slots[2].StackCount = nil
        setmetatable(slots[2], { __index = function(_, k) if k == "StackCount" then return count end end,
            __newindex = function(t, k, v)
                if k ~= "StackCount" then rawset(t, k, v); return end
                if v == 0 and not rejected then rejected = true; error("simulated debit failure") end
                count = v
            end })
        assert(not service:disassemble({}, "Part", 3))
        equal(backend:read().Inventory, { Part = 6, Ingot = 1 })
        assert(backend.disabled and not backend.busy)
    end)
    test("runtime refuses reentrant calls before reading inventory", function()
        local backend, service, inventory = fixture()
        backend.busy = true
        local result, reason = service:disassemble({}, "Part", 1)
        assert(not result and reason == "disassembly_in_progress")
        equal(inventory.adds, 0)
    end)
    test("runtime reads the exact Blueprint UI model field and unwraps recipe results", function()
        local _, _, inventory = fixture()
        local id = name("Part"); id.type = function() return "FName" end
        local concrete = object({ GetBaseCampModelBelongTo = function() return nil end, GetRecipes = function()
            return { { type = function() return "RemoteUnrealParam" end, get = function() return id end } }
        end })
        local model = object({ TryGetConcreteModel = function(_, out) out.Model = concrete; return true end })
        local row = { Product_Id = name("Part"), Product_Count = 2, WorkAmount = 20 }
        for index = 1, 5 do row["Material" .. index .. "_Id"] = name(index == 1 and "Ingot" or "None")
            row["Material" .. index .. "_Count"] = index == 1 and 3 or 0 end
        local access = object({ BP_FindRow = function(_, _, found) found.bResult = true; return row end })
        local accessible = 6
        local utility = object({ GetItemRecipeDataTableAccess = function() return access end,
            CollectLocalPlayerControllableItemInfos = function(_, _, ids, out, scope)
                equal(ids, { "Part" }); equal(scope, 2)
                out.OutItemInfos = { { type = function() return "RemoteUnrealParam" end,
                    get = function() return { StaticItemId = name("Part"), Num = accessible } end } }
            end })
        local controller = object({ HasAuthority = function() return true end,
            PlayerState = { GetInventoryData = function() return inventory end } })
        local session = { recipeId = "Part", card = object({ RecipeId = id }),
            workspace = object({ ["Convert Item Model"] = model, GetOwningPlayer = function() return controller end }) }
        local backend = Runtime.new({ StaticFindObject = function() return utility end, FName = function(s) return s end })
        local state = backend:read(session)
        equal(state.Inventory, { Part = 6, Ingot = 1 })
        equal(state.Context.StationRecipes, { Part = true })
        equal(state.Recipes.Part.Materials, { Ingot = 3 })
        local function array(values)
            return { GetArrayNum = function() return #values end, ForEach = function(_, callback)
                for i, v in ipairs(values) do callback(i, { get = function() return v end }) end
            end }
        end
        local baseSlot = object({ ItemId = { StaticId = name("Part") }, StackCount = 24 })
        local baseContainer = object({ GetFullName = function() return "base" end,
            Num = function() return 1 end, Get = function() return baseSlot end })
        local storage = object({ GetClass = function() return { GetFName = function() return name("PalBaseCampModuleItemStorage") end } end,
            ContainerInfos = array({ { bShouldUseContainerIdCache = true, ContainerIdCache = "authorized-base" } }),
            GuildContainerInfo = { bShouldUseContainerIdCache = false } })
        concrete.GetBaseCampModelBelongTo = function() return object({ ModuleArray = array({ storage }) }) end
        utility.GetItemContainerManager = function() return object({ GetContainer = function(_, id)
            equal(id, "authorized-base"); return baseContainer
        end }) end
        accessible = 30
        equal(backend:read(session).Inventory.Part, 30)
        storage.ContainerInfos = array({
            { bShouldUseContainerIdCache = true, ContainerIdCache = "stale-base" },
            { bShouldUseContainerIdCache = true, ContainerIdCache = "authorized-base" },
        })
        utility.GetItemContainerManager = function() return object({ GetContainer = function(_, id)
            if id == "stale-base" then return { IsValid = function() return false end } end
            equal(id, "authorized-base"); return baseContainer
        end }) end
        equal(backend:read(session).Inventory.Part, 30)
        storage.GuildContainerInfo = { bShouldUseContainerIdCache = true, ContainerIdCache = "stale-base" }
        equal(backend:read(session).Inventory.Part, 30)
        -- If the game still counts the missing container, refuse the snapshot.
        accessible = 31
        local readable, mismatch = pcall(backend.read, backend, session)
        assert(not readable and mismatch:find("production inventory scope mismatch", 1, true))
        accessible = 29
        readable, mismatch = pcall(backend.read, backend, session)
        assert(not readable and mismatch:find("production inventory scope mismatch", 1, true))
        controller.HasAuthority = function() return false end
        local ok, reason = pcall(backend.read, backend, session)
        assert(not ok and reason:find("requires the local server host", 1, true))
    end)
    test("disassembly UI retries lazy hooks once without polling or inventory access", function()
        local names = { "StaticConstructObject", "NotifyOnNewObject", "ExecuteInGameThread", "RegisterHook" }
        local previous = {}
        for _, id in ipairs(names) do previous[id] = _G[id] end
        local notifications, registered = {}, {}
        StaticConstructObject = function() error("widget created at startup") end
        ExecuteInGameThread = function(callback) callback() end
        NotifyOnNewObject = function(_, callback) notifications[#notifications + 1] = callback end
        RegisterHook = function(path)
            registered[path] = (registered[path] or 0) + 1
            return 1, 2
        end
        local ok, reason = pcall(function()
            require("BetterWorkbench.DisassemblyUI").start({ Enabled = true, Language = "zh-Hans" })
            for _, callback in ipairs(notifications) do callback(); callback() end
            local total = 0
            for _, calls in pairs(registered) do equal(calls, 1); total = total + 1 end
            equal(total, 7)
        end)
        for _, id in ipairs(names) do _G[id] = previous[id] end
        assert(ok, reason)
    end)
    test("stock count toggles disassembly without a visible button and requires a whole batch", function()
        local globals = { "StaticConstructObject", "StaticFindObject", "NotifyOnNewObject", "ExecuteInGameThread",
            "RegisterHook", "FindAllOf", "LoadAsset", "FText", "FName" }
        local previous = {}
        for _, id in ipairs(globals) do previous[id] = _G[id] end
        local oldModule, oldNew = package.loaded["BetterWorkbench.DisassemblyUI"], Runtime.new
        local registered, attached, opacity, nativeGuard, messages, navigationSetting = {}, nil, nil, nil, {}, nil
        local backend, _, _, inventorySlots = fixture()
        local snapshotReads = 0
        local originalSnapshot = backend.disassemblySnapshot
        function backend:disassemblySnapshot(session)
            snapshotReads = snapshotReads + 1
            return originalSnapshot(self, session)
        end
        Runtime.new = function() return backend end
        package.loaded["BetterWorkbench.DisassemblyUI"] = nil
        local badge = object({ GetFullName = function() return "WBP_CommonButton_C Test" end,
            SetText = function(self, s) self.label = s end, SetVisibility = function() end,
            SetIsEnabled = function(self, enabled) self.enabled = enabled end,
            GetIsEnabled = function(self) return self.enabled end,
            SetRenderOpacity = function(_, n) opacity = n end,
            SetToolTipText = function(_, s) equal(s, "") end })
        local focus = object({ rules = {}, SetIsFocusable = function(self, enabled) self.focusable = enabled end,
            GetFullName = function() return "count focus" end,
            SetToolTipText = function(_, s) equal(s, "") end,
            SetShouldUseFallbackDefaultInputAction = function(self, enabled) self.confirm = enabled end,
            SetNavigationRuleExplicit = function(self, direction, target) self.rules[direction] = target end })
        focus.Slot = object({ SetOffsets = function(_, offsets)
            equal(offsets, { Left = 0, Top = 0, Right = 0, Bottom = 0 })
        end })
        local decoration = object({ GetFullName = function() return "common button decoration" end,
            SetVisibility = function(self, visibility) self.visibility = visibility end })
        badge.WidgetTree = { RootWidget = object({ GetChildrenCount = function() return 2 end,
            GetChildAt = function(_, index) return index == 0 and decoration or focus end }) }
        badge.WBP_PalInvisibleButton = focus
        local slot = object({ SetAnchors = function(_, anchors)
                equal(anchors, { Minimum = { X = 0, Y = 0.5 }, Maximum = { X = 1, Y = 0.5 } })
            end, SetOffsets = function(_, offsets)
                equal(offsets, { Left = 0, Top = -14, Right = 0, Bottom = 28 })
            end,
            SetAutoSize = function(_, enabled) assert(enabled == false) end,
            SetZOrder = function(_, n) equal(n, 100) end })
        local parent = object({ GetChildrenCount = function() return 0 end,
            AddChildToCanvas = function() error("count toggle must not sit beside stock") end,
            GetVisibility = function() return 4 end, GetParent = function() return nil end })
        local counter = object({ GetChildrenCount = function() return 0 end,
            AddChildToCanvas = function(_, widget) if widget == badge then attached = widget end; return slot end,
            GetVisibility = function() return 4 end,
            GetParent = function() return parent end })
        local card = object({ RecipeId = name("Part"), CanvasPanel_Num = {}, Text_Num = {},
            GetFullName = function() return "card" end })
        local function label(initial)
            local current = initial
            return object({ GetText = function() return name(current) end,
                SetText = function(_, s) current = s end, GetFullName = function() return "label:" .. initial end })
        end
        local selector = object({ nowNum = 4, ["Max Num"] = 20, MinNum = 1 })
        selector["Set Min Max Num"] = function(self, maximum, minimum) self["Max Num"], self.MinNum = maximum, minimum end
        function selector:SetNum(number) self.nowNum = number end
        local model = object({ GetFullName = function() return "model" end })
        function model:CanStartProduction() return nativeGuard({ get = function() return self end }) or 0 end
        local start = label("生产")
        local startFocus = object({ rules = {}, GetFullName = function() return "production focus" end,
            SetIsFocusable = function(self, enabled) self.focusable = enabled end,
            SetShouldUseFallbackDefaultInputAction = function(self, enabled) self.confirm = enabled end,
            SetNavigationRuleExplicit = function(self, direction, target) self.rules[direction] = target end,
            GetIsEnabled = function() return true end,
            SetUserFocus = function(self) self.focused = true end,
            HasAnyUserFocus = function(self) return self.focused == true end })
        start.WBP_PalInvisibleButton = startFocus
        function start:SetEnable(enabled) self.enabled = enabled end
        local shown
        local materials = object({ SetDetails = function(_, rows) shown = rows end })
        local workspace = object({ CanvasPanel_ItemNum = counter, LastSelectedSlot = card,
            HasAnyUserFocus = function() return false end,
            IsSelectingProductNumFlag = true, CommonTileView_146 = object({ SetNavigationRuleExplicit = function(_, direction, target)
                equal(direction, 1); assert(target == focus)
            end }), SetNavigationRuleExplicit = function(_, direction, target)
                assert((direction == 2 and target == focus) or (direction == 0 and target == card))
            end,
            ["Convert Item Model"] = model, WBP_IngameCommonSelectNum = selector,
            WBP_IngameMenu_StartButton = start, WBP_InventoryEquipment_ItemInfo_Tecnology = materials,
            BP_PalTextBlock_Name = label("Part"), BP_PalTextBlock_Num = label("生产数量"),
            Text_ManMonth_Value = label("20"),
            Text_ItemNumValue = label("6"),
            GetOwningPlayer = function() return {} end, GetFullName = function() return "workspace" end })
        workspace.OnClickedRecipeSlot = function()
            workspace.Text_ItemNumValue:SetText(tostring(backend:read().Inventory.Part or 0))
        end
        workspace["Update Recipe Detail"] = function() end
        workspace.InputMethodChanged = function(_, input)
            registered["/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C:InputMethodChanged"](
                { get = function() return workspace end }, { type = function() return "RemoteUnrealParam" end,
                    get = function() return input end })
        end
        StaticConstructObject = function() error("unexpected native layout") end
        StaticFindObject = function(path)
            if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then
                return object({ Create = function() return badge end })
            end
            if path == "/Script/Engine.Default__SubsystemBlueprintLibrary" then
                return object({ GetLocalPlayerSubsystem = function()
                    return object({ GetCurrentInputType = function() return 1 end })
                end })
            end
            if path == "/Script/Pal.Default__PalUtility" then
                return object({ Alert = function(_, _, message) messages[#messages + 1] = message end })
            end
            if path == "/Script/Pal.Default__PalUIUtility" then
                return object({ SetCustomSlateNavigation = function(_, owner, setting)
                    assert(owner == workspace); navigationSetting = setting
                end })
            end
            return object({})
        end
        NotifyOnNewObject = function() end
        ExecuteInGameThread = function(callback) callback() end
        RegisterHook = function(path, callback, post)
            registered[path] = callback
            if path:match(":CanStartProduction$") then nativeGuard = post end
            return 1, 2
        end
        FindAllOf, LoadAsset = nil, nil
        FText = function(s) return s end
        FName = function(s) return s end
        local ok, reason = pcall(function()
            require("BetterWorkbench.DisassemblyUI").start({ Enabled = true, Language = "zh-Hans" })
            local selected
            for path, callback in pairs(registered) do
                if path:match(":OnClickedRecipeSlot$") then selected = callback end
            end
            assert(selected)
            selected({ get = function() return workspace end },
                { type = function() return "RemoteUnrealParam" end, get = function() return card end })
            assert(attached == badge)
            equal(opacity, 0)
            equal(badge.label, "")
            equal(decoration.visibility, 1)
            assert(badge.enabled)
            assert(focus.focusable and focus.confirm)
            assert(focus.rules[0] == card and focus.rules[3] == startFocus)
            assert(startFocus.rules[2] == focus and startFocus.rules[0] == card)
            assert(startFocus.focusable and startFocus.confirm and startFocus.focused)
            assert(startFocus.HideFocusCursor == false and focus.HideFocusCursor == false)
            equal(navigationSetting, { IsEnableAnalogNavigation = true, IsEnableLeftKeyNavigation = false,
                IsEnableRightKeyNavigation = false, IsEnableUpKeyNavigation = false, IsEnableDownKeyNavigation = false })
            navigationSetting = nil
            workspace:InputMethodChanged(0)
            assert(navigationSetting == nil)
            startFocus.focused = false
            selected({ get = function() return workspace end },
                { type = function() return "RemoteUnrealParam" end, get = function() return card end })
            assert(not startFocus.focused and navigationSetting == nil)
            equal(card.CanvasPanel_Num, {})
            equal(card.Text_Num, {})
            local clicked
            for path, callback in pairs(registered) do
                if path:find("CommonButtonBaseClicked", 1, true) then clicked = callback end
            end
            -- Focused CommonButton confirm and mouse click share the native event.
            clicked({ get = function() return badge end })
            equal(model:CanStartProduction(), 1)
            equal(badge.label, "")
            equal(selector["Max Num"], 3)
            equal(selector.nowNum, 3)
            equal(workspace.BP_PalTextBlock_Name:GetText():ToString(), "分解 · Part")
            equal(workspace.BP_PalTextBlock_Num:GetText():ToString(), "2")
            equal(workspace.Text_ItemNumValue:GetText():ToString(), "6")
            equal(start:GetText():ToString(), "开始分解")
            assert(start.enabled)
            equal(shown, { { StaticItemId = "Fiber", Num = 3 }, { StaticItemId = "Ingot", Num = 9 } })
            selector.nowNum = 2
            snapshotReads = 0
            for path, callback in pairs(registered) do
                if path:match(":Update Recipe Detail$") then callback({ get = function() return workspace end }) end
            end
            equal(snapshotReads, 1)
            equal(shown, { { StaticItemId = "Fiber", Num = 2 }, { StaticItemId = "Ingot", Num = 6 } })
            equal(workspace.BP_PalTextBlock_Num:GetText():ToString(), "2")
            local startProduce
            for path, callback in pairs(registered) do
                if path:match(":StartProduce$") then startProduce = callback end
            end
            assert(startProduce and model:CanStartProduction() == 1)
            startProduce({ get = function() return workspace end })
            equal(backend:read().Inventory, { Part = 2, Ingot = 7, Fiber = 2 })
            equal(messages, {})
            equal(workspace.Text_ItemNumValue:GetText():ToString(), "2")
            equal(selector.nowNum, 1)
            backend.disabled = true
            startProduce({ get = function() return workspace end })
            equal(#messages, 1)
            assert(messages[1]:find("分解失败：", 1, true))
            equal(backend:read().Inventory, { Part = 2, Ingot = 7, Fiber = 2 })
            backend.disabled = false
            startProduce({ get = function() return workspace end })
            equal(backend:read().Inventory, { Ingot = 10, Fiber = 3 })
            equal(selector.nowNum, 0)
            equal(selector["Max Num"], 0)
            equal(selector.MinNum, 0)
            equal(workspace.Text_ItemNumValue:GetText():ToString(), "0")
            equal(shown, {})
            equal(#messages, 1)
            assert(not start.enabled)
            startProduce({ get = function() return workspace end })
            assert(messages[#messages]:find("已有成品不足", 1, true))
            equal(backend:read().Inventory, { Ingot = 10, Fiber = 3 })
            clicked({ get = function() return badge end })
            equal(model:CanStartProduction(), 0)
            equal(selector.nowNum, 4)
            equal(selector["Max Num"], 20)
            equal(start:GetText():ToString(), "生产")
            equal(workspace.Text_ItemNumValue:GetText():ToString(), "0")
            equal(badge.label, "")
            assert(not badge.enabled)
            clicked({ get = function() return badge end })
            equal(model:CanStartProduction(), 0)
            equal(start:GetText():ToString(), "生产")
            inventorySlots[1].ItemId.StaticId = name("Part")
            inventorySlots[1].StackCount = 1
            clicked({ get = function() return badge end })
            equal(model:CanStartProduction(), 0)
            equal(selector.nowNum, 4)
            assert(not badge.enabled)
        end)
        for _, id in ipairs(globals) do _G[id] = previous[id] end
        Runtime.new, package.loaded["BetterWorkbench.DisassemblyUI"] = oldNew, oldModule
        assert(ok, reason)
    end)
end
