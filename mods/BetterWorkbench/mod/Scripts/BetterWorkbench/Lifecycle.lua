-- Invalidate Lua-owned state before Unreal starts destroying the old world.
-- Reset handlers must drop wrappers, never inspect objects from that world.
local M={epoch=0}
local handlers={}
function M.onReset(callback) handlers[#handlers+1]=callback end
function M.reset()
 M.epoch=M.epoch+1
 for _,callback in ipairs(handlers) do callback() end
 print('[BetterWorkbench] World session invalidated\n')
end
function M.install(api)
 api=api or _G
 api.RegisterLoadMapPreHook(function() M.reset() end)
end
return M
