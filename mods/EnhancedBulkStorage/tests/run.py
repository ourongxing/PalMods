"""Exercise candidate expansion through the real Lua entry point; audit the native gate."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, load_lua_runtime
sys.path.insert(0, str(ROOT / 'mods/EnhancedBulkStorage/tools'))
from build import generate_guard

if GAME_EXE.exists():
    generate_guard()
else:
    print('SKIP: native instruction audit requires the supported installed game')
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.execute(r'''
READY, IN_BASE, IS_INVENTORY = true, true, true
COUNTS = {stone=7, wood=4, absent=0, large=3000000000}
function name(id) return {ToString=function() return id end} end
FName=name
function array(values)
    values.ForEach=function(self, cb) for i,v in ipairs(self) do cb(i,{get=function() return v end}) end end
    values.Empty=function(self) for i=#self,1,-1 do self[i]=nil end; self.emptied=true end
    return values
end
function param(value) return {get=function() return value end, set=function(self,v) self.written=v end} end
WORLD={IsValid=function() return true end, IsA=function() return IS_INVENTORY end}
UTILITY={CountLocalPlayerInventoryItemNum64=function(self,world,n) return COUNTS[n:ToString()] or 0 end}
package.loadlib=function(path,symbol)
    assert(path:match('/dlls/main.dll$'))
    assert(symbol=='luaopen_EnhancedBulkStorage')
    return function() return function() return READY end end
end
function RegisterHook(path, pre, post) HOOK=post end
function run(ids, current)
    WORLD.CurrentInBaseCamp=IN_BASE
    local names={} for _,id in ipairs(ids) do names[#names+1]=name(id) end
    local old=array(current or {})
    local output=param(old)
    HOOK(param(UTILITY),param(WORLD),param(array(names)),output)
    return output, old
end
''')
source = ROOT / 'mods/EnhancedBulkStorage/mod/Scripts/main.lua'
lua.execute('assert(load(..., "@/mock/EnhancedBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
lua.execute(r'''
local existing={StaticItemId=name('wood'),Num=100}
local output,old=run({'stone','stone','wood','absent','None'},{existing})
assert(old.emptied and #output.written==2)
assert(output.written[1].StaticItemId:ToString()=='wood' and output.written[1].Num==100)
assert(output.written[2].StaticItemId:ToString()=='stone' and output.written[2].Num==7)
local unchanged=run({'wood'},{existing}); assert(not unchanged.written)
local clamped=run({'large'}); assert(clamped.written[1].Num==2147483647)
READY=false; local disabled=run({'stone'}); assert(not disabled.written); READY=true
IN_BASE=false; local outside=run({'stone'}); assert(not outside.written); IN_BASE=true
IS_INVENTORY=false; local other=run({'stone'}); assert(not other.written); IS_INVENTORY=true
local none=run({'absent','None'}); assert(not none.written)
''')
lua2 = load_lua_runtime()(unpack_returned_tuples=True)
lua2.execute('package.loadlib=function() return nil,"disabled" end; RegisterHook=function() error("must not register") end')
lua2.execute('assert(load(..., "@/mock/EnhancedBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
print('PASS: native binary/instruction audit and Lua candidate lifecycle cases')
