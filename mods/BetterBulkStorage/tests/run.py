"""Exercise candidate expansion through the real Lua entry point; audit the native gate."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, UE4SS_ROOT, load_lua_runtime
from audit_interfaces import audit
sys.path.insert(0, str(ROOT / 'mods/BetterBulkStorage/tools'))
from build import generate_guard

source = ROOT / 'mods/BetterBulkStorage/mod/Scripts/main.lua'
audit(source.read_text(encoding='utf-8'), UE4SS_ROOT / 'UE4SS_ObjectDump.txt')
try:
    audit(source.read_text(encoding='utf-8').replace('GetPalmi(world)', 'GetPalmi()'),
          UE4SS_ROOT / 'UE4SS_ObjectDump.txt')
except AssertionError as error:
    assert 'GetPalmi: expected 1 arguments, found 0' in str(error)
else:
    raise AssertionError('Interface audit failed to catch a missing argument')

if GAME_EXE.exists():
    generate_guard()
else:
    print('SKIP: native instruction audit requires the supported installed game')
lua = load_lua_runtime()(unpack_returned_tuples=True)
mock_setup = r'''
READY, IN_BASE, IS_INVENTORY, IN_SCOPE = true, true, true, true
IN_CANDIDATE_SCOPE=false
HOOKS={}
COUNTS = {stone=7, wood=4, absent=0, large=3000000000, PalEgg=3}
COUNT_CALLS={}
function name(id) return {ToString=function() return id end} end
FName=name
function array(values)
 values.ForEach=function(self, cb) for i,v in ipairs(self) do cb(i,{get=function() return v end}) end end
 values.Empty=function(self) for i=#self,1,-1 do self[i]=nil end; self.emptied=true end
 return values
end
function param(value) return {get=function() return value end, set=function(self,v) self.written=v end} end
WORLD={IsValid=function() return true end, IsA=function() return IS_INVENTORY end}
UTILITY={CountLocalPlayerInventoryItemNum64=function(self,world,n)
 local id=n:ToString(); COUNT_CALLS[id]=(COUNT_CALLS[id] or 0)+1; return COUNTS[id] or 0 end}
package.loadlib=function(path,symbol)
 assert(path:match('/dlls/main.dll$') and symbol=='luaopen_BetterBulkStorage')
 return function() return function() return READY end, function() return IN_SCOPE end,
  function() return IN_CANDIDATE_SCOPE end end
end
-- Any destination content/permission inspection fails the test. This applies
-- equally to full, forbidden, locked and unloaded chests, on every refresh.
local function forbidden() error('candidate UI must not inspect chest contents or permissions') end
TARGET=setmetatable({IsValid=function() return true end}, {__index=forbidden})
PHYSICAL_BASE=TARGET
CHECK={IsValid=function() return true end,GetOwner=function() return OWNER end}
CHECK.GetInsideBaseCampModel=function(self)
 local hook=HOOKS['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel']
 return hook(param(self),param(PHYSICAL_BASE)) or PHYSICAL_BASE
end
MOCKPLAYER={IsValid=function() return true end,InsideBaseCampCheckComponent=CHECK}
PAL={IsValid=function() return true end,GetPalmi=function() return MOCKPLAYER end,
 GetMapObjectManager=forbidden,GetItemIDManager=forbidden,GetLocalPalPlayerController=forbidden}
function StaticFindObject() return PAL end
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
'''
lua.execute(mock_setup)
lua.execute('assert(load(..., "@/mock/BetterBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
lua.execute(r'''
local existing={StaticItemId=name('wood'),Num=100}
local output,old=run({'stone','stone','wood','absent','absent','None'},{existing})
assert(old.emptied and #output.written==2)
assert(output.written[1].StaticItemId:ToString()=='wood' and output.written[1].Num==100)
assert(output.written[2].StaticItemId:ToString()=='stone' and output.written[2].Num==7)
assert(COUNT_CALLS.stone==1 and COUNT_CALLS.absent==1 and not COUNT_CALLS.wood)
assert(not run({'wood'},{existing}).written)
assert(run({'large'}).written[1].Num==2147483647)
assert(not run({'absent','None'}).written)
READY=false; assert(not run({'stone'}).written); READY=true
IN_BASE=false; assert(not run({'stone'}).written); IN_BASE=true
IS_INVENTORY=false; assert(not run({'stone'}).written); IS_INVENTORY=true
IN_SCOPE=false; assert(not run({'stone'}).written); IN_SCOPE=true
-- Every original candidate is retained even if the destination cannot fit it.
local original={StaticItemId=name('absent'),Num=50}
local retained=run({'stone'},{original})
assert(#retained.written==2 and retained.written[1].Num==50)
-- Repeated transfer-driven refreshes remain independent of base/chest size.
for _=1,100 do assert(run({'stone','PalEgg','stone'}).written[2].Num==3) end
local count=UTILITY.CountLocalPlayerInventoryItemNum64
UTILITY.CountLocalPlayerInventoryItemNum64=function() error('count unavailable') end
local failed, previous=run({'stone'},{existing})
assert(not failed.written and not previous.emptied)
UTILITY.CountLocalPlayerInventoryItemNum64=count
assert(run({'stone'}).written[1].Num==7)

local dynamicHook=HOOKS['/Script/Pal.PalStaticItemDataBase:HasDynamicItemClass']
local egg={TypeB=30, IsValid=function() return true end}
local weapon={TypeB=4, IsValid=function() return true end}
assert(dynamicHook(param(egg),param(true))==nil)
IN_CANDIDATE_SCOPE=true
assert(dynamicHook(param(egg),param(true))==false)
assert(dynamicHook(param(weapon),param(true))==nil)
assert(dynamicHook(param(egg),param(false))==nil)
assert(dynamicHook(param(nil),param(true))==nil)
assert(#run({'PalEgg','PalEgg'}).written==1)
READY=false; assert(dynamicHook(param(egg),param(true))==nil); READY=true
IN_CANDIDATE_SCOPE=false; IN_SCOPE=false
assert(dynamicHook(param(egg),param(true))==nil)

-- Exercise the actual native getter companions and guild/model selection.
local function object(value) value.IsValid=function() return true end; return value end
local function id(n) return {A=n,B=0,C=0,D=0} end
PLAYER=object({InsideBaseCampCheckComponent=CHECK,GetAddress=function() return 1000 end,K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end})
-- GetOwner and GetPalmi return separate wrappers for the same native UObject.
OWNER=object({GetAddress=function() return 1000 end})
assert(OWNER~=PLAYER)
COMPONENT=object({GetOwner=function() return OWNER end})
GUILD=object({GetId=function() return id(1) end,BaseCampIds=array({id(10),id(20),id(30),id(40),id(50)})})
local function base(n,group,x,z,buildings)
    return object({GetId=function() return id(n) end,GetGroupIdBelongTo=function() return id(group) end,
        GetBuildingNum=function() return buildings or 0 end,
        GetTransform=function() return {Translation={X=x,Y=0,Z=z or 0}} end})
end
BASES={[10]=base(10,1,100,0,100),[20]=base(20,1,20,0,10),
    [30]=base(30,2,1,0,1000),[50]=base(50,1,2,200,100)}
MANAGER=object({TryGetModel=function(self,key,output) output.OutModel=BASES[key.A]; return output.OutModel~=nil end})
PAL.GetPalmi=function() return PLAYER end
PAL.GetBaseCampManager=function() return MANAGER end
GROUPS=object({GetLocalPlayerGuild=function() return GUILD end})
function StaticFindObject(path) if path:match('PalGroupUtility$') then return GROUPS else return PAL end end
local modelHook=HOOKS['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampModel']
local idHook=HOOKS['/Script/Pal.PalInsideBaseCampCheckComponent:GetInsideBaseCampID']
assert(modelHook(param(COMPONENT),param(nil))==nil) -- unrelated gameplay
IN_SCOPE=true
assert(modelHook(param(COMPONENT),param(nil))==BASES[10]) -- more buildings wins; foreign/missing ignored
assert(idHook(param(COMPONENT),param(id(0))).A==10) -- model and ID agree
assert(modelHook(param(COMPONENT),param(BASES[10]))==nil) -- keep current in-base result
assert(idHook(param(COMPONENT),param(id(10)))==nil)
PLAYER.K2_GetActorLocation=function() return {X=90,Y=0,Z=0} end
assert(idHook(param(COMPONENT),param(id(0))).A==10) -- fewer buildings still loses
PLAYER.K2_GetActorLocation=function() return {X=2,Y=0,Z=190} end
assert(idHook(param(COMPONENT),param(id(0))).A==50) -- equal counts use 3D distance
BASES[20].GetBuildingNum=function() return 200 end
assert(idHook(param(COMPONENT),param(id(0))).A==20) -- building changes picked up immediately
BASES[20].GetBuildingNum=function() return -1 end
assert(idHook(param(COMPONENT),param(id(0))).A==50) -- invalid counts ignored
BASES[20].GetBuildingNum=function() return 0/0 end
assert(idHook(param(COMPONENT),param(id(0))).A==50)
BASES[20].GetBuildingNum=function() return 0 end
BASES[10].GetBuildingNum=function() return 0 end
BASES[50].GetBuildingNum=function() return 0 end
assert(idHook(param(COMPONENT),param(id(0))).A==50) -- zero counts remain valid
GUILD.BaseCampIds=array({id(30),id(40)})
assert(modelHook(param(COMPONENT),param(nil))==nil) -- no eligible base
assert(idHook(param(COMPONENT),param(id(0)))==nil)
GUILD.BaseCampIds=array({id(20)})
COMPONENT.GetOwner=function() return object({GetAddress=function() return 2000 end}) end
assert(modelHook(param(COMPONENT),param(nil))==nil) -- another player's component
COMPONENT.GetOwner=function() return OWNER end
READY=false; assert(modelHook(param(COMPONENT),param(nil))==nil); READY=true
IN_SCOPE=false; assert(idHook(param(COMPONENT),param(id(0)))==nil) -- scope ends at cancel/return
IN_SCOPE=true; IN_BASE=true; local remote=run({'stone'}); assert(remote.written[1].Num==7)


-- Both physical and remote bases admit candidates without chest inspection.
GUILD.BaseCampIds=array({id(10),id(20)})
BASES[10].GetBuildingNum=function() return 100 end
BASES[20].GetBuildingNum=function() return 10 end
for _=1,3 do
 PHYSICAL_BASE=TARGET
 assert(run({'stone','PalEgg'}).written[2].Num==3)
 PHYSICAL_BASE=nil
 assert(run({'stone','PalEgg'}).written[2].Num==3)
 assert(idHook(param(COMPONENT),param(id(0))).A==10)
 IN_SCOPE=false
 assert(not run({'stone'}).written)
 assert(idHook(param(COMPONENT),param(id(0)))==nil)
 IN_SCOPE=true
end
GUILD.BaseCampIds=array({})
assert(not run({'stone'}).written) -- no physical or eligible guild base
PHYSICAL_BASE=TARGET
assert(run({'stone'}).written[1].Num==7) -- current base still wins
PHYSICAL_BASE=nil
GUILD.BaseCampIds=array({id(10)})
local getter=CHECK.GetInsideBaseCampModel
CHECK.GetInsideBaseCampModel=function() error('location unavailable') end
assert(not run({'stone'}).written)
CHECK.GetInsideBaseCampModel=getter
assert(run({'stone'}).written[1].Num==7)
''')
lua2 = load_lua_runtime()(unpack_returned_tuples=True)
lua2.execute('package.loadlib=function() return nil,"disabled" end; RegisterHook=function() error("must not register") end')
lua2.execute('assert(load(..., "@/mock/BetterBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
print('PASS: native audit, scan-free candidates, deduplication, original candidates retained, base transitions, scoped eggs and guild base selection')
