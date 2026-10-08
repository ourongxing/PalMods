local Adapter = {}

function Adapter.status()
    if type(BetterWorkbenchNativeIsActive) == "function" then
        local ok, active = pcall(BetterWorkbenchNativeIsActive)
        if ok and active then return { Ready = true, Reason = "Native current-workbench crafting active." } end
        return { Ready = false, Reason = "Waiting for native initialization and game-build checks." }
    end
    return {
        Ready = false,
        Reason = "Native recipe-view and atomic craft hooks are not verified for this game build.",
    }
end

function Adapter.start(config)
    if Adapter.stateMonitor then Adapter.stateMonitor.stopped = true end
    if Adapter.probe then Adapter.probe.stop() end
    if Adapter.planner then Adapter.planner.stop() end
    -- Native crafting and UI previews operate independently of Lua probes.
    -- Keep all background Lua callbacks out of the normal gameplay profile.
    if not config.Diagnostics or config.Diagnostics.Enabled ~= true then
        local status = Adapter.status()
        return status.Ready, status.Reason
    end
    Adapter.planner = require("BetterWorkbench.NativeSnapshotPlan").start(config)
    local ok, probe, reason = pcall(require("BetterWorkbench.Diagnostics").start, config.Diagnostics)
    if ok then
        Adapter.probe = probe
        if not probe then print("[BetterWorkbench] Diagnostic probe unavailable: " .. tostring(reason) .. "\n") end
    else
        print("[BetterWorkbench] Diagnostic probe failed: " .. tostring(probe) .. "\n")
    end
    if type(LoopAsync) == "function" and type(ExecuteInGameThread) == "function" then
        local monitor = { stopped = false, reported = false }
        Adapter.stateMonitor = monitor
        LoopAsync(1000, function()
            if monitor.stopped or monitor.reported then return true end
            ExecuteInGameThread(function()
                if not monitor.stopped and not monitor.reported and Adapter.status().Ready then
                    monitor.reported = true
                    print("[BetterWorkbench] Native crafting active: all current-workbench recipes, same station only.\n")
                end
            end)
            return false
        end)
    end
    local status = Adapter.status()
    return status.Ready, status.Reason
end

return Adapter
