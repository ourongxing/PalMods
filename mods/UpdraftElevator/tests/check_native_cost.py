from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
LuaRuntime = load_lua_runtime()
l=LuaRuntime()
l.execute('''
hooks={}; paid=false
function RegisterHook(p,a,b) hooks[p]=b or a end
function FName(s) return s end
function ExecuteWithDelay() error("automatic unlock scheduling is forbidden") end
function ExecuteInGameThread() error("automatic unlock is forbidden") end
function print() end
''')
source=Path('mod/Scripts/main.lua').read_text(encoding='utf-8')
l.execute(source)
l.execute('''
local f=assert(hooks["/Script/Pal.PalTechnologyData:IsUnlockBuildObject"])
local tech={IsValid=function() return true end,
 IsUnlockRecipeTechnology=function(self,id)
  assert(id=="CodexWindTechnology"); return paid
 end}
for _,unlocked in ipairs({false,true,false}) do
 paid=unlocked
 for _,size in ipairs({"Small","Medium","Large"}) do
  assert(f({get=function() return tech end},"CodexWindNative"..size)==paid)
  assert(f(nil,"CodexWindNative"..size)==false)
  assert(f(tech,"CodexWindPad"..size)==nil)
 end
 assert(f(tech,"WorkBench")==nil)
end
local count=0
for path in pairs(hooks) do
 count=count+1
 assert(path=="/Script/Pal.PalTechnologyData:IsUnlockBuildObject" or path=="/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorBeginOverlap" or path=="/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorEndOverlap")
end
assert(count==3)
''')
assert all(x not in source for x in ['RequestUnlockRecipeTechnology','IsExistsMaterialForBuildObject','IsEnoughMaterials','IsExistsMaterial','ExecuteWithDelay','FindAllOf','SpawnActor','RegisterKeyBind'])
print('PASS: all sizes require new paid technology, legacy free IDs cannot bypass, ordinary recipes untouched, no auto unlock or free material/menu hooks')
