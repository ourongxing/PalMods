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
READY, IN_BASE, IS_INVENTORY, IN_SCOPE = true, true, true, false
HOOKS={}
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
    return function() return function() return READY end, function() return IN_SCOPE end end
end
function RegisterHook(path, pre, post) HOOKS[path]=post end
HOOK_PATH='/Script/Pal.PalItemUtility:CollectLocalPlayerQuickStackTargetItemInfos'
function run(ids, current)
    WORLD.CurrentInBaseCamp=IN_BASE
    local names={} for _,id in ipairs(ids) do names[#names+1]=name(id) end
    local old=array(current or {})
    local output=param(old)
    HOOKS[HOOK_PATH](param(UTILITY),param(WORLD),param(array(names)),output)
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

-- Exercise the actual native getter companions and guild/model selection.
local function object(value) value.IsValid=function() return true end; return value end
local function id(n) return {A=n,B=0,C=0,D=0} end
PLAYER=object({GetAddress=function() return 1000 end,K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end})
-- GetOwner and GetPalmi return separate wrappers for the same native UObject.
OWNER=object({GetAddress=function() return 1000 end})
assert(OWNER~=PLAYER)
COMPONENT=object({GetOwner=function() return OWNER end})
GUILD=object({GetId=function() return id(1) end,BaseCampIds=array({id(10),id(20),id(30),id(40),id(50)})})
local function base(n,group,x,z)
    return object({GetId=function() return id(n) end,GetGroupIdBelongTo=function() return id(group) end,
        GetTransform=function() return {Translation={X=x,Y=0,Z=z or 0}} end})
end
BASES={[10]=base(10,1,100),[20]=base(20,1,20),[30]=base(30,2,1),[50]=base(50,1,2,200)}
MANAGER=object({TryGetModel=function(self,key,output) output.OutModel=BASES[key.A]; return output.OutModel~=nil end})
PAL=object({GetPalmi=function() return PLAYER end,GetBaseCampManager=function() return MANAGER end})
GROUPS=object({GetLocalPlayerGuild=function() return GUILD end})
function StaticFindObject(path) if path:match('PalGroupUtility$') then return GROUPS else return PAL end end
local modelHook=HOOKS['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel']
local idHook=HOOKS['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID']
assert(modelHook(param(COMPONENT),param(nil))==nil) -- unrelated gameplay
IN_SCOPE=true
assert(modelHook(param(COMPONENT),param(nil))==BASES[20]) -- nearer foreign and missing models ignored
assert(idHook(param(COMPONENT),param(id(0))).A==20)
assert(modelHook(param(COMPONENT),param(BASES[10]))==nil) -- keep current in-base result
assert(idHook(param(COMPONENT),param(id(10)))==nil)
PLAYER.K2_GetActorLocation=function() return {X=90,Y=0,Z=0} end
assert(idHook(param(COMPONENT),param(id(0))).A==10) -- recompute after moving
GUILD.BaseCampIds=array({id(30),id(40)})
assert(modelHook(param(COMPONENT),param(nil))==nil) -- no eligible base
assert(idHook(param(COMPONENT),param(id(0)))==nil)
GUILD.BaseCampIds=array({id(20)})
COMPONENT.GetOwner=function() return object({GetAddress=function() return 2000 end}) end
assert(modelHook(param(COMPONENT),param(nil))==nil) -- another player's component
COMPONENT.GetOwner=function() return OWNER end
READY=false; assert(modelHook(param(COMPONENT),param(nil))==nil); READY=true
IN_SCOPE=false; assert(idHook(param(COMPONENT),param(id(0)))==nil) -- scope ends at cancel/return
IN_BASE=true; local remote=run({'stone'}); assert(remote.written[1].Num==7) -- UI sees selected base
''')
lua2 = load_lua_runtime()(unpack_returned_tuples=True)
lua2.execute('package.loadlib=function() return nil,"disabled" end; RegisterHook=function() error("must not register") end')
lua2.execute('assert(load(..., "@/mock/EnhancedBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
print('PASS: native binary/instruction audit, Lua candidates, scoped nearest guild base selection')
