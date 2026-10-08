from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
LuaRuntime = load_lua_runtime()
source=Path('work/native_cost_only.lua').read_text(encoding='utf-8')
default=Path('work/wind_config.lua').read_text(encoding='utf-8')

def verify(config_source, expected):
    lua=LuaRuntime()
    lua.execute('''
hooks={}; messages={}; configReads=0
function RegisterHook(p,a,b) hooks[p]=b or a end
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
wind={IsValid=function() return true end,IsAvailable=function() return true end,
 IsActorBeingDestroyed=function() return false end}
player={IsValid=function() return true end,IsPlayerControlled=function() return true end,
 IsLocallyControlled=function() return true end,
 GetOverlappingActors=function(self,out) out[1]=wind end,
 LaunchCharacter=function(self,v) measured=v.Z*v.Z/(2*980)/100 end}
''')
    for size, meters in zip(['Small','Medium','Large'],expected):
        lua.globals().wind.BuildObjectId='CodexWindNative'+size
        lua.execute('hooks["/Script/Pal.PalCharacter:OnJump"](player,movement)')
        assert abs(lua.globals().measured-meters)<0.00001
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
