local Config = require("config")
local Adapter = require("BetterWorkbench.PalworldAdapter")

if not Config.Enabled then
    print("[BetterWorkbench] Disabled by config.\n")
    return
end

if type(RegisterLoadMapPreHook) ~= "function" then
    print("[BetterWorkbench] Disabled: world lifecycle hook unavailable.\n")
    return
end
require("BetterWorkbench.Lifecycle").install()
print("[better workbench / 更好的工作台] Runtime profile: native current-workbench crafting when bridge checks pass.\n")
local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = assert(source:match("^(.*)/Scripts/[^/]+$"), "mod directory unavailable")
local marker = io.open(directory .. "/server.txt", "rb")
local server = marker ~= nil
if marker then marker:close() end
require("BetterWorkbench.Remote").start(Config)
if not server then
    require("BetterWorkbench.MaterialScroll").start(Config.MaterialScroll)
    require("BetterWorkbench.DisassemblyUI").start(Config.Disassembly)
end

local ready, reason = Adapter.start(Config)
if not ready then
    print("[BetterWorkbench] Core loaded; bridge status: " .. reason .. "\n")
end
