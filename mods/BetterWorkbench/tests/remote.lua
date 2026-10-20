return function(test, equal)
    local Remote = require("BetterWorkbench.Remote")
    local Context = require("BetterWorkbench.ServerContext")
    local Network = require("BetterWorkbench.Network")
    local function object(t) t.IsValid = function() return true end; return t end
    local guid = { A = 1, B = -1, C = 2, D = 3 }
    local station = Context.text(guid)
    test("remote workbench binds controller, station, distance and guild access", function()
        equal(Context.guid(station), guid)
        local denied = false
        local pc = object({ HasAuthority = function() return true end, GetAddress = function() return 1 end,
            PlayerState = object({ PlayerUId = guid }) })
        local model = object({ ModelInstanceId = guid, IsA = function() return true end,
            GetTransform = function() return { Translation = { X = 0, Y = 0, Z = 0 } } end,
            GetGuildSecurityModule = function() return object({ CheckGuildSecurityAccess = function() return not denied end }) end })
        local position = 100
        pc.Pawn = object({ Controller = pc, GetCharacterParameterComponent = function()
            return object({ IsDead = function() return false end }) end,
            K2_GetActorLocation = function() return { X = position, Y = 0, Z = 0 } end })
        local api = { StaticFindObject = function() return { GetMapObjectManager = function()
            return object({ FindModel = function(_, id)
                equal(id, guid)
                return object({ GetConcreteModel = function(_, load) assert(load == true); return model end })
            end, FindConcreteModel = function() error("owner ModelInstanceId is not a concrete-instance ID") end }) end } end }
        assert(Context.read(pc, station, "Part", api).controller == pc)
        denied = true; assert(not pcall(Context.read, pc, station, "Part", api))
        denied = false; position = 1001; assert(not pcall(Context.read, pc, station, "Part", api))
        position = 100; pc.Pawn.Controller = object({ GetAddress = function() return 2 end })
        assert(not pcall(Context.read, pc, station, "Part", api))
    end)
    test("remote disassembly consumes each sequence before settlement and sends actual receipt", function()
        local previous, oldSend = Context.read, Network.send
        local packets, calls = {}, 0
        Context.read = function(pc, selected, recipe)
            equal(selected, station); return { controller = pc, recipeId = recipe }
        end
        Network.send = function(_, text, serial, down) packets[#packets+1] = { text, serial, down } end
        local ok, problem = pcall(function()
            local remote = Remote.new({ Enabled = true, Disassembly = { Enabled = true } }, {})
            remote.service = { disassemble = function(_, session, recipe, batches)
                calls = calls+1; equal(recipe, "Part"); equal(batches, 2)
                return { ProductItem = "Part", Consumed = { Part = 4 }, Returns = { Ore = 6 } }
            end }
            local pc = { GetFullName = function() return "owned controller" end }
            local request = "BW1|123-1|D|"..station.."|Part|2"
            remote:receive({}, pc, request, 1)
            remote:receive({}, pc, request, 1)
            equal(calls, 1); equal(#packets, 3)
            equal(packets[1], { "BW1|123-1|P|Part|4", 1, true })
            remote:receive({}, pc, request, 2); equal(calls, 2)
            remote.service.disassemble = function() calls = calls+1; return nil, "backpack_full" end
            remote:receive({}, pc, request, 3)
            assert(packets[#packets][1]:find("E|backpack_full", 1, true))
            remote:receive({}, pc, request, 3); equal(calls, 3)
        end)
        Context.read, Network.send = previous, oldSend
        assert(ok, problem)
    end)
    test("client waits for complete owned receipt and ignores duplicate completion", function()
        local remote = Remote.new({}, {})
        local pc = { GetFullName = function() return "owner" end }
        local results = 0
        remote.pending = { serial = 1, owner = "owner", result = { Returns = {} }, count = 0,
            callback = function(result) equal(result.Returns, { Ore = 6 }); equal(result.Consumed, { Part = 4 }); results = results+1 end }
        remote:accept({}, pc, "BW1|other|R|Ore|6", 1)
        remote:accept({}, pc, "BW1|"..remote.token.."|C|1", 1)
        equal(results, 0)
        remote:accept({}, pc, "BW1|"..remote.token.."|P|Part|4", 1)
        remote:accept({}, pc, "BW1|"..remote.token.."|R|Ore|6", 1)
        remote:accept({}, pc, "BW1|"..remote.token.."|C|1", 1)
        remote:accept({}, pc, "BW1|"..remote.token.."|C|1", 1)
        equal(results, 1)
    end)
    test("fragmented job imports only once complete with duplicates and bounds checked", function()
        local imports = 0
        local alias = "BWJ_0123456789abcdef0123456789abcdef_Part"
        local remote = Remote.new({}, { BetterWorkbenchNativeImportJob = function(id, bytes)
            equal(id, alias); equal(bytes, "a\0b\nc"); imports = imports+1; return true end })
        local pc = { GetFullName = function() return "owner" end }
        remote:accept({}, pc, "BW1|S|B|"..alias.."|2", 2)
        remote:accept({}, pc, "BW1|S|F|1|610062", 2)
        remote:accept({}, pc, "BW1|S|F|1|610062", 2)
        equal(imports, 0)
        remote:accept({}, pc, "BW1|S|F|2|0a63", 2)
        remote:accept({}, pc, "BW1|S|F|2|0a63", 2)
        equal(imports, 1)
        assert(not pcall(remote.accept, remote, {}, pc, "BW1|S|B|"..alias.."|999999", 3))
    end)
    test("claim timeout never retransmits and idle tick never scans all controllers", function()
        local remote = Remote.new({}, { FindAllOf = function() error("idle global search") end })
        local called = 0
        remote.pending = { at = os.time()-20, callback = function(result, reason)
            assert(not result and reason == "retry"); called = called+1 end }
        remote:tick(); remote:tick(); equal(called, 1)
    end)
    test("network timer stays on game thread and defers bounded owned requests across world reset", function()
        local install, owner = Network.install, Network.owner
        local up, down, timers, calls = nil, nil, {}, 0
        local pc = object({ HasAuthority = function() return true end, GetAddress = function() return 7 end })
        local component = object({})
        Network.install = function(u, d) up, down = u, d end
        Network.owner = function(c) assert(c == component); return pc end
        local ok, problem = pcall(function()
            local remote = Remote.start({}, {
                LoopAsync = function() error("background Lua callback forbidden") end,
                FindAllOf = function() error("idle global scan forbidden") end,
                ExecuteInGameThreadWithDelay = function(delay, callback)
                    equal(delay, 100); timers[#timers+1] = callback
                end,
            })
            remote.receive = function() calls = calls+1 end
            for i = 1, 300 do up(component, pc, "packet", i) end
            equal(calls, 0); equal(#timers, 1)
            table.remove(timers, 1)(); equal(calls, 64); equal(#timers, 1)
            table.remove(timers, 1)(); equal(calls, 128)
            table.remove(timers, 1)(); equal(calls, 192)
            table.remove(timers, 1)(); equal(calls, 256)
            table.remove(timers, 1)(); equal(calls, 256)
            up(component, pc, "old world", 301)
            require("BetterWorkbench.Lifecycle").reset()
            table.remove(timers, 1)(); equal(calls, 256)
            down(component, pc, "wrong authority", 302)
            table.remove(timers, 1)(); equal(calls, 256)
            Network.owner = function() return { GetAddress = function() return 8 end } end
            up(component, pc, "different owner", 303)
            table.remove(timers, 1)(); equal(calls, 256)
        end)
        Network.install, Network.owner = install, owner
        assert(ok, problem)
    end)
end
