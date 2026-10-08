from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import json
LuaRuntime = load_lua_runtime()
l=LuaRuntime()
l.execute('''
hooks={}; messages={}
package.preload.UEHelpers=function() return {} end
function RegisterHook(p,a,b) hooks[p]=b or a end
function ExecuteWithDelay() end
function print(s) table.insert(messages,s) end
''')
source=Path('mod/Scripts/main.lua').read_text(encoding='utf-8')
l.execute(source)
l.execute('messages={}') # Ignore the one startup version announcement.
l.execute('''
local jump=assert(hooks["/Script/Pal.PalCharacter:OnJump"])
local valid=function() return true end
local movement={IsValid=valid,GetGravityZ=function() return -980 end}
local overlapping={}
local launches=0; local velocity
local player={IsValid=valid,IsPlayerControlled=valid,IsLocallyControlled=valid,
 GetOverlappingActors=function(self,out,filter)
  assert(filter==nil)
  for i,actor in ipairs(overlapping) do out[i]=actor end
 end,
 LaunchCharacter=function(self,v,xy,z)
  assert(v.X==0 and v.Y==0 and xy==false and z==true)
  velocity=v.Z; launches=launches+1
 end}
local function wind(id,available,destroyed)
 return {IsValid=valid,BuildObjectId=id,
  IsAvailable=function() return available~=false end,
  IsActorBeingDestroyed=function() return destroyed==true end}
end
-- No overlap entry hook exists; walking in is inert in the native BP as well.
assert(hooks["/Script/Engine.Actor:ReceiveActorBeginOverlap"]==nil)
jump(player,movement); assert(launches==0) -- outside
for i,id in ipairs({"Small","Medium","Large"}) do
 overlapping={wind("CodexWindNative"..id)}
 jump({get=function() return player end},{get=function() return movement end})
 assert(launches==i)
 assert(math.abs(velocity*velocity/(2*980)-800*2^(i-1))<0.0001)
end
-- Highest overlapping wind wins once, independent of enumeration order.
overlapping={wind("CodexWindNativeLarge"),wind("CodexWindNativeSmall"),wind("CodexWindNativeMedium")}
jump(player,movement); assert(launches==4 and math.abs(velocity*velocity/(2*980)-3200)<0.0001)
movement.GetGravityZ=function() return -1960 end
jump(player,movement); assert(launches==5 and math.abs(velocity*velocity/(2*1960)-3200)<0.0001)
overlapping={wind("CodexWindNativeLarge",false),wind("CodexWindNativeSmall",true,true),wind("WorkBench"),{IsValid=valid}}
jump(player,movement); assert(launches==5) -- preview/inactive/destroyed/unrelated
overlapping={wind("CodexWindNativeLarge")}
player.IsPlayerControlled=function() return false end
jump(player,movement); assert(launches==5) -- AI pals excluded
player.IsPlayerControlled=valid; player.IsLocallyControlled=function() return false end
jump(player,movement); assert(launches==5) -- other clients excluded
player.IsLocallyControlled=valid; movement.GetGravityZ=function() return 0 end
jump(player,movement); assert(launches==5) -- zero gravity
jump(nil,movement); jump(player,nil); assert(launches==5)
assert(#messages==0) -- all normal paths run without error
''')
variants=json.loads(Path('data/variants.json').read_text(encoding='utf-8'))
for v in variants:
    assert f"CodexWindNative{v['Suffix']}={v['LiftHeightCm']}" in source
assert [v['LiftHeightCm'] for v in variants]==[800,1600,3200]
print('PASS: jump-only hook, outside/AI/remote/inactive excluded, 8/16/32m heights, actual gravity, strongest overlap once, horizontal momentum preserved')
