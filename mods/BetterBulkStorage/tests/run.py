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
    audit(source.read_text(encoding='utf-8').replace('GetConcreteModel(false)', 'GetConcreteModel()'),
          UE4SS_ROOT / 'UE4SS_ObjectDump.txt')
except AssertionError as error:
    assert 'GetConcreteModel: expected 1 arguments, found 0' in str(error)
else:
    raise AssertionError('Interface audit failed to catch the reported missing-argument regression')

if GAME_EXE.exists():
    generate_guard()
else:
    print('SKIP: native instruction audit requires the supported installed game')
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.execute(r'''
READY, IN_BASE, IS_INVENTORY, IN_SCOPE = true, true, true, true
IN_CANDIDATE_SCOPE=false
HOOKS={}
COUNTS = {stone=7, wood=4, absent=0, large=3000000000, PalEgg=3}
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
    assert(symbol=='luaopen_BetterBulkStorage')
    return function() return function() return READY end, function() return IN_SCOPE end,
        function() return IN_CANDIDATE_SCOPE end,
        function(container,slot,data) return not DENIED[data] end end
end
DENIED={}
DATA={IsValid=function() return true end,GetAddress=function() return DATA_ID end}
IDS={IsValid=function() return true end,GetStaticItemData=function(self,n) DATA_ID=n:ToString(); return DATA end}
local function oid(n) return {A=n,B=0,C=0,D=0} end
SLOT={IsValid=function() return true end,IsEmpty=function() return true end,GetAddress=function() return 2 end}
CONTAINER={IsValid=function() return true end,GetAddress=function() return 1 end,ItemSlotArray=array({SLOT})}
MODULE={IsValid=function() return true end,GetContainer=function() return CONTAINER end}
CHEST={IsValid=function() return true end,IsA=function() return true end,
 GetBaseCampIdBelongTo=function() return oid(10) end,IsLockedPrivateByNot=function() return PRIVATE_LOCK end,
 GetGuildSecurityModule=function() return nil end,GetPasswordLockModule=function() return nil end,
 GetItemContainerModule=function() return MODULE end}
MAPMODEL={IsValid=function() return true end,GetConcreteModel=function(self,...)
 assert(select('#',...)==1 and (...)==false, 'GetConcreteModel requires bIsForce=false')
 return CHEST end}
MAPS={IsValid=function() return true end,FindModel=function() return MAPMODEL end}
COLLECTION={IsValid=function() return true end,MapObjectInstanceIdRepInfoArray={Items=array({{InstanceId=oid(100)}})}}
TARGET={IsValid=function() return true end,GetId=function() return oid(10) end,MapObjectCollection=COLLECTION}
CHECK={IsValid=function() return true end,GetInsideBaseCampModel=function() return TARGET end}
MOCKPLAYER={IsValid=function() return true end,InsideBaseCampCheckComponent=CHECK}
CONTROLLER={IsValid=function() return true end,GetPlayerUId=function() return oid(1) end}
PAL={IsValid=function() return true end,GetPalmi=function() return MOCKPLAYER end,
 GetMapObjectManager=function() return MAPS end,GetLocalPalPlayerController=function() return CONTROLLER end,
 GetItemIDManager=function() return IDS end}
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
''')
lua.execute('assert(load(..., "@/mock/BetterBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
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

-- Destination restrictions remove both original and added candidates. Other
-- bases have no influence; switching bases/filters/space is read each call.
DENIED.stone=true
local blocked=run({'stone','wood'},{{StaticItemId=name('stone'),Num=7}})
assert(#blocked.written==1 and blocked.written[1].StaticItemId:ToString()=='wood')
local onlyBlocked=run({'stone'},{{StaticItemId=name('stone'),Num=7}}); assert(#onlyBlocked.written==0)
DENIED.stone=nil
CONTAINER.ItemSlotArray=array({})
local full=run({'stone'},{{StaticItemId=name('stone'),Num=7}}); assert(#full.written==0)
CONTAINER.ItemSlotArray=array({SLOT})
SLOT.IsEmpty=function() return false end
SLOT.IsMaxStack=function() return false end
SLOT.GetItemId=function() return {StaticId=name('wood'),DynamicId={LocalIdInCreatedWorld={A=0,B=0,C=0,D=0}}} end
local matching=run({'stone','wood'}); assert(#matching.written==1 and matching.written[1].StaticItemId:ToString()=='wood')
SLOT.IsMaxStack=function() return true end
assert(not run({'wood'}).written)
SLOT.IsEmpty=function() return true end
PRIVATE_LOCK=true; assert(not run({'stone'}).written); PRIVATE_LOCK=false
assert(run({'stone'}).written[1].Num==7)
TARGET.GetId=function() return {A=20,B=0,C=0,D=0} end
local otherBase=run({'stone'},{{StaticItemId=name('stone'),Num=7}}); assert(#otherBase.written==0)
TARGET.GetId=function() return {A=10,B=0,C=0,D=0} end
local security={IsValid=function() return true end,CheckGuildSecurityAccess=function() return false end}
CHEST.GetGuildSecurityModule=function() return security end
assert(not run({'stone'}).written)
CHEST.GetGuildSecurityModule=function() return nil end
local lock={IsValid=function() return true end,GetLockState=function() return 0 end,PlayerInfos=array({})}
CHEST.GetPasswordLockModule=function() return lock end
assert(not run({'stone'}).written)
lock.PlayerInfos=array({{PlayerUId={A=1,B=0,C=0,D=0},TrySuccessCache=true}})
assert(run({'stone'}).written[1].Num==7)
CHEST.GetPasswordLockModule=function() return nil end
MAPMODEL.IsValid=function() return false end
local unknown=run({'stone','wood'},{{StaticItemId=name('wood'),Num=4}}); assert(not unknown.written)
MAPMODEL.IsValid=function() return true end
IN_SCOPE=false
assert(not run({'stone'}).written)
IN_SCOPE=true

-- Pal eggs must reach the static-name candidate collector without changing
-- dynamic classification in unrelated UI/gameplay, or for equipment.
local dynamicHook=HOOKS['/Script/Pal.PalStaticItemDataBase:HasDynamicItemClass']
local egg={TypeB=30, IsValid=function() return true end}
local weapon={TypeB=4, IsValid=function() return true end}
assert(dynamicHook(param(egg),param(true))==nil)
IN_SCOPE=true -- inventory execution alone is not enough
assert(dynamicHook(param(egg),param(true))==nil)
IN_CANDIDATE_SCOPE=true
assert(dynamicHook(param(egg),param(true))==false)
assert(dynamicHook(param(weapon),param(true))==nil)
assert(dynamicHook(param(egg),param(false))==nil)
assert(dynamicHook(param(nil),param(true))==nil)
local eggs=run({'PalEgg','PalEgg'}); assert(#eggs.written==1 and eggs.written[1].Num==3)
READY=false; assert(dynamicHook(param(egg),param(true))==nil); READY=true
IN_CANDIDATE_SCOPE=false; IN_SCOPE=false
assert(dynamicHook(param(egg),param(true))==nil) -- cancel/return restores classification

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

-- Leaving a secondary base must restore remote candidates even when no chest
-- model is loaded. The location read must bypass our own scoped getter fallback.
GUILD.BaseCampIds=array({id(10),id(20)})
BASES[10].GetBuildingNum=function() return 100 end
BASES[20].GetBuildingNum=function() return 10 end
CHECK.GetOwner=function() return OWNER end
CHECK.GetInsideBaseCampModel=function()
 assert(idHook(param(COMPONENT),param(id(0)))==nil) -- neither getter may fake the physical location
 return modelHook(param(COMPONENT),param(nil))
end
MAPS.FindModel=function() error('remote operation must not inspect local chest models') end
DENIED.stone=true -- secondary-base filter must not leak into the remote UI
local outside=run({'stone','PalEgg'})
assert(#outside.written==2 and outside.written[1].Num==7 and outside.written[2].Num==3)
assert(idHook(param(COMPONENT),param(id(0))).A==10)
GUILD.BaseCampIds=array({})
assert(not run({'stone'}).written) -- no target guild base
GUILD.BaseCampIds=array({id(10),id(20)})
CHECK.GetInsideBaseCampModel=function() error('location unavailable') end
assert(not run({'stone'}).written)
assert(modelHook(param(COMPONENT),param(nil))==BASES[10]) -- failure must restore getter fallback
CHECK.GetInsideBaseCampModel=function() return TARGET end
MAPS.FindModel=function() return MAPMODEL end
local backInside=run({'stone'},{{StaticItemId=name('stone'),Num=7}})
assert(#backInside.written==0) -- actual current base still filters
DENIED.stone=nil

-- Repeat the full transition to catch retained base/slot/filter state.
for _=1,3 do
 CHECK.GetInsideBaseCampModel=function() return TARGET end
 DENIED.stone=true
 assert(#run({'stone'},{{StaticItemId=name('stone'),Num=7}}).written==0)
 CHECK.GetInsideBaseCampModel=function()
  assert(idHook(param(COMPONENT),param(id(0)))==nil)
  return modelHook(param(COMPONENT),param(nil))
 end
 assert(run({'stone'}).written[1].Num==7)
 IN_SCOPE=false
 assert(idHook(param(COMPONENT),param(id(0)))==nil)
 assert(not run({'stone'}).written)
 IN_SCOPE=true
end
''')
lua2 = load_lua_runtime()(unpack_returned_tuples=True)
lua2.execute('package.loadlib=function() return nil,"disabled" end; RegisterHook=function() error("must not register") end')
lua2.execute('assert(load(..., "@/mock/BetterBulkStorage/Scripts/main.lua"))()', source.read_text(encoding='utf-8'))
print('PASS: native audit, destination restrictions/space, leave-base remote candidates, scoped eggs and guild base selection')
