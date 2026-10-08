local Config = require("config")
local Adapter = require("BetterWorkbench.PalworldAdapter")

if not Config.Enabled then
    print("[BetterWorkbench] Disabled by config.\n")
    return
end

print("[better workbench / 更好的工作台] Runtime profile: native current-workbench crafting when bridge checks pass.\n")
require("BetterWorkbench.MaterialScroll").start(Config.MaterialScroll)
require("BetterWorkbench.DisassemblyUI").start(Config.Disassembly)

local ready, reason = Adapter.start(Config)
if not ready then
    print("[BetterWorkbench] Core loaded; bridge status: " .. reason .. "\n")
end
