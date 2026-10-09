from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
l = load_lua_runtime()()
l.execute("""
hooks={}; messages={}
function RegisterHook(p,a,b) hooks[p]=b or a end
function print(s) table.insert(messages,s) end
function StaticFindObject() return {IsValid=function() return true end} end
""")
source=Path('mod/Scripts/main.lua').read_text(encoding='utf-8')
l.execute(source)
l.execute("""
messages={}
local begin=assert(hooks['/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorBeginOverlap'])
local finish=assert(hooks['/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorEndOverlap'])
assert(hooks['/Script/Pal.PalCharacter:OnJump']==nil)
local valid=function() return true end
local movement={IsValid=valid, GetGravityZ=function() return -980 end}
local overlapping={}; local selected; local registrations=0
local player={IsValid=valid, IsPlayerControlled=valid, IsLocallyControlled=valid,
 CharacterMovement=movement, GetOverlappingActors=function(self,out)
  for i,v in ipairs(overlapping) do out[i]=v end
 end, LaunchCharacter=function() error('Lua must not bypass the original action/notify') end}
local function proxy(size)
 local parent={IsValid=valid, BuildObjectId='CodexWindNative'..size,
  IsAvailable=valid, IsActorBeingDestroyed=function() return false end}
 local spot={IsValid=valid, IsActorBeingDestroyed=function() return false end,
  IsOverlappingActor=valid, GetParentActor=function() return parent end,
  GetClass=function() return {GetFName=function() return 'BP_WindJump'..size..'_C' end} end}
 spot.EventOnActorBeginOverlap=function(self,actor,p)
  assert(actor==self and p==player); selected=self; registrations=registrations+1
  begin(self,self,p) -- exercise recursion protection
 end
 spot.EventOnActorEndOverlap=function(self,actor,p)
  selected=nil; finish(self,self,p)
 end
 return spot,parent
end
local small,smallParent=proxy('Small'); local medium=proxy('Medium'); local large=proxy('Large')
for i,spot in ipairs({small,medium,large}) do
 overlapping={spot}; begin(spot,spot,player)
 assert(selected==spot and registrations==i and spot.bPlayJumpPrepareMontage)
 assert(spot.JumpFowardVelocity==0)
 assert(math.abs(spot.JumpZVelocity^2/(2*980)-800*2^(i-1))<0.0001)
end
-- Entry only registers a modifier: no animation or launch before jump input.
overlapping={large,small,medium}; begin(small,small,player); assert(selected==large)
overlapping={small,medium,large}; begin(small,small,player); assert(selected==large)
-- Leaving/dismantling the strongest selects the next surviving volume.
overlapping={small,medium}; selected=nil; finish(large,large,player); assert(selected==medium)
smallParent.IsAvailable=function() return false end
overlapping={small}; selected=nil; finish(medium,medium,player); assert(selected==nil)
smallParent.IsAvailable=valid
small.IsOverlappingActor=function() return false end
begin(small,small,player); assert(selected==nil) -- stale engine overlap entries ignored
small.IsOverlappingActor=valid
movement.GetGravityZ=function() return -1960 end
begin(small,small,player); assert(selected==small and math.abs(small.JumpZVelocity^2/(2*1960)-800)<0.0001)
movement.GetGravityZ=function() return 0 end
begin(small,small,player); assert(selected==nil)
movement.GetGravityZ=function() return -980 end
-- Entering under glider gravity must cache the ordinary falling launch speed,
-- which stays correct after landing even without another overlap event.
movement.CustomMovementMode=4; movement.GliderGravityScale=0.025
movement.GetGravityZ=function() return -784*movement.GliderGravityScale end
for _,spot in ipairs({small,medium,large}) do
 overlapping={spot}; begin(spot,spot,player)
 local target=({[small]=800,[medium]=1600,[large]=3200})[spot]
 assert(math.abs(spot.JumpZVelocity^2/(2*784)-target)<0.0001)
end
movement.CustomMovementMode=0; movement.GetGravityZ=function() return -784 end
assert(math.abs(large.JumpZVelocity^2/(2*784)-3200)<0.0001)
-- A different glider factor and stronger world/character gravity also work.
movement.CustomMovementMode=4; movement.GliderGravityScale=0.1
movement.GetGravityZ=function() return -1960*0.1 end
overlapping={small}; begin(small,small,player)
assert(math.abs(small.JumpZVelocity^2/(2*1960)-800)<0.0001)
-- An old glider factor must not affect walking or ordinary falling.
movement.CustomMovementMode=0; movement.GetGravityZ=function() return -980 end
begin(small,small,player)
assert(math.abs(small.JumpZVelocity^2/(2*980)-800)<0.0001)
selected=nil
player.IsPlayerControlled=function() return false end
begin(small,small,player); assert(selected==nil)
player.IsPlayerControlled=valid; player.IsLocallyControlled=function() return false end
begin(small,small,player); assert(selected==nil)
player.IsLocallyControlled=valid
-- A map spot keeps its original action, speed and direction; exit restores wind.
local map={IsValid=valid, IsActorBeingDestroyed=function() return false end,
 IsOverlappingActor=valid, IsA=valid,
 GetClass=function() return {GetFName=function() return 'BP_LevelGimmickJumpSpotSmall_C' end} end,
 JumpZVelocity=1234, JumpFowardVelocity=456,
 EventOnActorBeginOverlap=function(self) selected=self end}
overlapping={small,map}; begin(small,small,player)
assert(selected==map and map.JumpZVelocity==1234 and map.JumpFowardVelocity==456)
overlapping={small}; finish(map,map,player); assert(selected==small)
overlapping={}; finish(small,small,player); assert(selected==nil)
begin(nil,nil,player); begin(small,small,nil)
begin(small,small,{IsValid=valid}) -- non-character overlap ignored
assert(#messages==0)
""")
assert 'LaunchCharacter(' not in source
print('PASS: original jump modifier and prepare montage, strongest overlap, exit/dismantle reselection, actual gravity and gliding-entry/landing regression, local players only, native map priority, recursion guard, no direct launch')
