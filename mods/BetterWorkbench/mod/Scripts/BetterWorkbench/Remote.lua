local Network = require("BetterWorkbench.Network")
local Context = require("BetterWorkbench.ServerContext")
local Runtime = require("BetterWorkbench.DisassemblyRuntime")
local Service = require("BetterWorkbench.CraftService")
local M = {}
local function valid(o) return o and o:IsValid() end
local function hex(bytes) return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function unhex(bytes)
    assert(#bytes%2 == 0 and bytes:match("^%x+$"), "invalid job fragment")
    return (bytes:gsub("..", function(c) return string.char(tonumber(c,16)) end))
end
local function identity(pc) return pc:GetFullName() end
local function log(message) print("[BetterWorkbench.Network] " .. tostring(message) .. "\n") end
function M.new(config, api)
    api = api or _G
    local self = { serial = 0, token = tostring(os.time()).."-"..tostring(math.random(1,1000000000)),
        servers = {}, queues = {}, fragments = {}, wanted = {}, serverSerial = 1000000000 }
    self.service = Service.new(Runtime.new(api))
    function self:packet(c, token, serial, body)
        Network.send(c, "BW1|"..token.."|"..body, serial, true)
    end
    function self:definition(c, token, serial, alias, pc)
        local bytes, station, root = api.BetterWorkbenchNativeExportJob(alias)
        assert(type(bytes) == "string", station or "job unavailable")
        Context.read(pc, station, root, api) -- no arbitrary remote journal reads
        local encoded = hex(bytes)
        local count = math.ceil(#encoded/140)
        assert(count >= 1 and count <= 4096, "job fragment limit")
        local key = identity(pc)
        local q = self.queues[key]
        if q then return end -- sender retries; never allocate unbounded queues
        self.queues[key] = { alias = alias, token = token, serial = serial,
            encoded = encoded, count = count, next = 0, at = os.time() }
    end
    function self:receive(c, pc, text, serial)
        local token, body = text:match("^BW1|([%w%-]+)|(.+)$")
        if not token or #token > 32 then return end
        local key = identity(pc)
        local state = self.servers[key]
        if not state then
            local n = 0; for _ in pairs(self.servers) do n = n+1 end
            if n >= 128 then return end
            state = { tokens = {}, n = 0 }; self.servers[key] = state
        end
        local high = state.tokens[token]
        if high and serial <= high then return end
        if not high then if state.n >= 32 then return end; state.n = state.n+1 end
        state.tokens[token] = serial -- consume before any inventory operation
        local alias = body:match("^J|([%w_]+)$")
        if alias and #alias <= 128 then self:definition(c, token, serial, alias, pc); return end
        local station, recipe, batches = body:match("^D|(%x+)|([%w_]+)|(%d+)$")
        if not station or #recipe > 100 then return end
        batches = tonumber(batches)
        assert(batches >= 1 and batches <= 256, "invalid disassembly batches")
        local ok, result, reason = pcall(function()
            assert(config.Enabled and config.Disassembly and config.Disassembly.Enabled, "disassembly disabled")
            local session = Context.read(pc, station, recipe, api)
            return self.service:disassemble(session, recipe, batches)
        end)
        if not ok or not result then
            local failure = tostring(ok and reason or result)
            local code = failure:find("backpack_full",1,true) and "backpack_full" or
                (failure:find("insufficient_products",1,true) and "insufficient_products" or "retry")
            self:packet(c, token, serial, "E|"..code); log("disassembly rejected: "..failure); return
        end
        local count = 0
        self:packet(c, token, serial, "P|"..result.ProductItem.."|"..result.Consumed[result.ProductItem])
        for id, n in pairs(result.Returns) do
            assert(#id <= 100 and id:match("^[%w_]+$") and n >= 1 and n <= 1000000000, "invalid receipt")
            self:packet(c, token, serial, "R|"..id.."|"..n); count = count+1
        end
        self:packet(c, token, serial, "C|"..count)
        log("disassembly completed recipe="..recipe.." batches="..batches)
    end
    function self:accept(c, pc, text, serial)
        local token, body = text:match("^BW1|([%w%-]+)|(.+)$")
        if token ~= self.token and token ~= "S" then return end
        local owner = identity(pc)
        if self.owner and self.owner ~= owner then return end
        local p = self.pending
        if token == self.token and p and p.serial == serial and p.owner == owner then
            local reason = body:match("^E|([%w_]+)$")
            if reason then self.pending = nil; p.callback(nil, reason); return end
            local product, consumed = body:match("^P|([%w_]+)|(%d+)$")
            if product then
                consumed = tonumber(consumed)
                assert(#product <= 100 and consumed >= 1 and consumed <= 1000000000, "invalid consumed receipt")
                p.result.ProductItem, p.result.Consumed = product, { [product] = consumed }; return
            end
            local id, n = body:match("^R|([%w_]+)|(%d+)$")
            if id then
                n = tonumber(n); assert(#id <= 100 and n >= 1 and n <= 1000000000 and not p.result.Returns[id], "invalid receipt")
                p.result.Returns[id] = n; p.count = p.count+1; assert(p.count <= 5, "receipt limit"); return
            end
            local count = body:match("^C|([1-5])$")
            if count and tonumber(count) == p.count and p.result.Consumed then self.pending = nil; p.callback(p.result); return end
        end
        local alias, count = body:match("^B|([%w_]+)|(%d+)$")
        local key = token..":"..serial
        if alias then
            count = tonumber(count)
            assert(#alias <= 128 and count >= 1 and count <= 4096, "invalid job header")
            local n = 0; for _ in pairs(self.fragments) do n = n+1 end
            if n >= 4 then return end
            self.fragments[key] = { alias = alias, count = count, parts = {}, received = 0, at = os.time() }; return
        end
        local p = self.fragments[key]
        local index, bytes = body:match("^F|(%d+)|(%x+)$")
        if p and index then
            index = tonumber(index)
            assert(index >= 1 and index <= p.count and #bytes <= 140, "invalid job fragment")
            if p.parts[index] then return end
            p.parts[index] = unhex(bytes); p.received = p.received+1
            if p.received == p.count then
                self.fragments[key] = nil
                local ok, problem = api.BetterWorkbenchNativeImportJob(p.alias, table.concat(p.parts))
                assert(ok, problem or "job import failed")
                self.wanted[p.alias] = nil
                log("job definition received "..p.alias)
            end
        end
    end
    function self:claim(session, recipe, batches, callback)
        assert(not self.pending, "disassembly_in_progress")
        local pc = session.workspace:GetOwningPlayer()
        assert(valid(pc) and not pc:HasAuthority(), "remote controller required")
        local out = {}
        assert(session.workspace["Convert Item Model"]:TryGetConcreteModel(out) and valid(out.Model), "workbench closed")
        local station = Context.text(out.Model.ModelInstanceId)
        assert(#recipe <= 100 and recipe:match("^[%w_]+$") and batches >= 1 and batches <= 256 and batches%1 == 0, "invalid request")
        self.serial = self.serial+1; self.owner = identity(pc)
        self.pending = { serial = self.serial, owner = self.owner, callback = callback, at = os.time(), count = 0,
            result = { RecipeId = recipe, Batches = batches, Returns = {} } }
        local ok, problem = pcall(Network.send, Network.component(pc),
            "BW1|"..self.token.."|D|"..station.."|"..recipe.."|"..batches, self.serial, false)
        if not ok then self.pending = nil; error(problem) end
    end
    function self:tick()
        if self.pending and os.time()-self.pending.at > 15 then
            local p = self.pending; self.pending = nil; p.callback(nil, "retry") -- never resend mutations
        end
        for key, p in pairs(self.fragments) do if os.time()-p.at > 30 then self.fragments[key] = nil end end
        local alias = api.BetterWorkbenchNativePollJob and api.BetterWorkbenchNativePollJob()
        if not alias and not next(self.queues) and not next(self.wanted) then return end
        local players = api.FindAllOf("PalPlayerController") or {}
        if #players > 128 then return end
        for _, pc in ipairs(players) do
            if valid(pc) then
                if pc:HasAuthority() then
                    if alias and not pc:IsLocalController() then
                        self.serverSerial = self.serverSerial+1
                        pcall(self.definition, self, Network.component(pc), "S", self.serverSerial, alias, pc)
                    end
                    local key = identity(pc)
                    local q = self.queues[key]
                    if q then
                        if os.time()-q.at > 30 then self.queues[key] = nil
                        else
                            local c = Network.component(pc)
                            for _ = 1, 16 do
                                if q.next == 0 then self:packet(c, q.token, q.serial, "B|"..q.alias.."|"..q.count)
                                else self:packet(c, q.token, q.serial, "F|"..q.next.."|"..q.encoded:sub((q.next-1)*140+1,q.next*140)) end
                                q.next = q.next+1
                                if q.next > q.count then self.queues[key] = nil; break end
                            end
                        end
                    end
                elseif pc:IsLocalController() then
                    if alias then
                        local n = 0; for _ in pairs(self.wanted) do n = n+1 end
                        if n < 64 then self.wanted[alias] = 0 end
                    end
                    for wanted, at in pairs(self.wanted) do
                        if os.time()-at >= 5 then
                            self.serial = self.serial+1
                            Network.send(Network.component(pc), "BW1|"..self.token.."|J|"..wanted, self.serial, false)
                            self.wanted[wanted] = os.time(); break
                        end
                    end
                end
            end
        end
    end
    return self
end
function M.start(config, api)
    api = api or _G
    local self = M.new(config, api); M.instance = self
    local Lifecycle = require("BetterWorkbench.Lifecycle")
    local incoming = {}
    Lifecycle.onReset(function()
        incoming = {}
        self.pending = nil; self.owner = nil
        self.servers = {}; self.queues = {}; self.fragments = {}; self.wanted = {}
        self.token = tostring(os.time()).."-"..tostring(math.random(1,1000000000))
    end)
    local function enqueue(up, c, pc, text, serial)
        if #incoming >= 256 then return end
        incoming[#incoming+1] = { up = up, c = c, pc = pc, text = text, serial = serial }
    end
    -- Retain copied values and UObject wrappers, never RemoteUnrealParam values
    -- pointing into the native RPC stack. Revalidate ownership when draining.
    Network.install(function(...) enqueue(true, ...) end, function(...) enqueue(false, ...) end)
    -- Lua coroutines share one VM/registry. A LoopAsync callback can allocate
    -- and collect objects concurrently with a native RPC hook on the game
    -- thread. Keep the timer itself on that thread, not just its payload.
    assert(type(api.ExecuteInGameThreadWithDelay) == "function", "game-thread timer unavailable")
    local function tick()
        local count = math.min(#incoming, 64)
        for _ = 1, count do
            local p = table.remove(incoming, 1)
            local ok, problem = pcall(function()
                if not valid(p.c) or not valid(p.pc) or p.pc:HasAuthority() ~= p.up then return end
                if Network.owner(p.c):GetAddress() ~= p.pc:GetAddress() then return end
                if p.up then self:receive(p.c, p.pc, p.text, p.serial)
                else self:accept(p.c, p.pc, p.text, p.serial) end
            end)
            if not ok then log(problem) end
        end
        local ok, problem = pcall(self.tick, self)
        if not ok and self.lastError ~= tostring(problem) then self.lastError = tostring(problem); log(problem) end
        api.ExecuteInGameThreadWithDelay(100, tick)
    end
    api.ExecuteInGameThreadWithDelay(100, tick)
    return self
end
return M
