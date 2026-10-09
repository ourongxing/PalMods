from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
LuaRuntime = load_lua_runtime()
source=Path('mod/Scripts/main.lua').read_text(encoding='utf-8')
default=Path('mod/Scripts/config.lua').read_text(encoding='utf-8')

def verify(config_source, expected):
    lua=LuaRuntime()
    lua.execute('''
hooks={}; messages={}; configReads=0
function RegisterHook(p,a,b) hooks[p]=b or a end
function StaticFindObject() return {IsValid=function() return true end} end
function print(s) table.insert(messages,s) end
''')
    if config_source is not None:
        # load() also exercises actual config syntax and its UTF-8 comments.
        lua.globals().configSource=config_source
        lua.execute('''package.preload.config=function()
 configReads=configReads+1
 return assert(load(configSource))()
end''')
    else:
        lua.execute('package.preload.config=function() configReads=configReads+1; error("missing") end')
    lua.execute(source)
    lua.execute('''
movement={IsValid=function() return true end,GetGravityZ=function() return -980 end}
parent={BuildObjectId='',IsValid=function() return true end,IsAvailable=function() return true end,
 IsActorBeingDestroyed=function() return false end}
wind={IsValid=function() return true end,IsActorBeingDestroyed=function() return false end,
 IsOverlappingActor=function() return true end,GetParentActor=function() return parent end,
 GetClass=function() return {GetFName=function() return 'BP_WindJumpSmall_C' end} end,
 EventOnActorBeginOverlap=function(self) measured=self.JumpZVelocity*self.JumpZVelocity/(2*980)/100 end}
player={CharacterMovement=movement,IsValid=function() return true end,IsPlayerControlled=function() return true end,
 IsLocallyControlled=function() return true end,
 GetOverlappingActors=function(self,out) out[1]=wind end}
''')
    for size, meters in zip(['Small','Medium','Large'],expected):
        lua.globals().parent.BuildObjectId='CodexWindNative'+size
        lua.execute('hooks["/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorBeginOverlap"](wind,wind,player)')
        assert abs(lua.globals().measured-meters)<0.00001
        lua.execute('''movement.CustomMovementMode=4; movement.GliderGravityScale=0.025
movement.GetGravityZ=function() return -980*movement.GliderGravityScale end
hooks["/Script/Pal.PalLevelGimmickJumpSpot:EventOnActorBeginOverlap"](wind,wind,player)''')
        assert abs(lua.globals().measured-meters)<0.00001
        lua.execute('movement.CustomMovementMode=0; movement.GetGravityZ=function() return -980 end')
    assert lua.globals().configReads==1 # no per-jump file reads or polling

verify(default,[8,16,32])
verify('return {Small=12.5,Medium=40,Large=75}',[12.5,40,75])
verify('return {Small=1000,Medium=0.1,Large=5}',[1000,0.1,5])
verify('return {Medium=20}',[8,20,32])
verify('return {Small="12",Medium=-1,Large=math.huge}',[8,16,32])
verify('return {Small=0/0,Medium=0,Large=1001}',[8,16,32])
verify('return 7',[8,16,32])
verify('return {Small=',[8,16,32])
verify(None,[8,16,32])
print('PASS: actual config file, custom/fractional heights, independent sizes, bounds, missing fields/file, invalid types/numbers/syntax, read once per startup')
