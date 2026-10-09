local function object(t)
    t = t or {}
    function t:IsValid() return not self.invalid end
    return t
end
local function id(n) return {A=n, B=0, C=0, D=0} end
local function array(values)
    function values:ForEach(cb)
        for i, value in ipairs(self) do cb(i, {get=function() return value end}) end
    end
    return values
end
local function base(n, count, x, group)
    local b = object({n=n, count=count, x=x, group=group or 7, reads=0})
    function b:GetId() return id(self.n) end
    function b:GetGroupIdBelongTo() return id(self.group) end
    function b:GetOwnerMapObjectInstanceId() return id(self.owner or self.n+100) end
    function b:GetBuildingNum() self.reads=self.reads+1; return self.count end
    function b:GetTransform() return {Translation={X=self.x,Y=0,Z=self.z or 0}} end
    return b
end
local bases = {[1]=base(1,10,10), [2]=base(2,50,1000), [3]=base(3,50,100)}
local guild = object({BaseCampIds=array({id(1),id(2),id(3)})})
function guild:GetId() return id(7) end
local manager = object()
function manager:TryGetModel(value, out)
    assert(type(value.A)=='number' and value.B==0)
    out.OutModel=bases[value.A]
    return out.OutModel ~= nil
end
local component = object()
function component:GetInsideBaseCampModel()
    if self.fail then error('simulated lookup error') end
    return self.inside
end
local player = object({InsideBaseCampCheckComponent=component})
function player:K2_GetActorLocation() return {X=0,Y=0,Z=0} end
local controller = object()
local service = object()
function service:IsAnyOverlayUIActive() return self.overlay or false end
function service:IsAnyFadeWidgetActive() return self.fade or false end
local calls, selected, missing, mismatch, foreign, fail = 0, nil, false, false, false, false
local objects = object()
function objects:FindModel(value)
    assert(IN_GAME_THREAD)
    if missing then return nil end
    local n=value.A-100
    assert(bases[n])
    local terminal=object({BaseCampId=id(mismatch and 999 or n)})
    function terminal:IsA(path) assert(path=="/Script/Pal.PalMapObjectBaseCampPoint"); return true end
    function terminal:IsSameGuildInLocalPlayer() return not foreign end
    function terminal:OnTriggerInteract(other, indicator)
        assert(IN_GAME_THREAD and other==player and indicator==11)
        if fail then error('simulated interaction failure') end
        calls=calls+1;selected=n
    end
    local model=object()
    function model:GetConcreteModel(force) assert(force==true); return terminal end
    return model
end
local utility, groups = object(), object()
function utility:GetLocalPalPlayerController(context) assert(context==controller); return controller end
function utility:GetPalmi(context) assert(context==controller); return player end
function utility:GetHUDService(context) assert(context==controller); return service end
function utility:GetBaseCampManager(context) assert(context==player); return manager end
function utility:GetMapObjectManager(context) assert(context==player); return objects end
function groups:GetLocalPlayerGuild(context) assert(context==player); return guild end
function FindFirstOf(name) assert(name=='PalPlayerController'); return controller end
function StaticFindObject(path)
    if path=='/Script/Pal.Default__PalUtility' then return utility end
    assert(path=='/Script/Pal.Default__PalGroupUtility'); return groups
end
Key={K=75, J=74, F6=117}
local key, queue, defer, queueFail, registered
function RegisterKeyBind(code, callback) registered=code;key=callback end
function ExecuteInGameThread(callback)
    if queueFail then error('simulated queue failure') end
    if defer then queue=callback;return end
    IN_GAME_THREAD=true;callback();IN_GAME_THREAD=false
end
local logs={}
function print(message) logs[#logs+1]=message end
package.path = PROJECT_ROOT .. '/mod/Scripts/?.lua;' .. package.path
dofile(PROJECT_ROOT .. '/mod/Scripts/main.lua')
assert(registered==Key.K)
local function expect(n)
    local before=calls;key()
    assert(calls==before+(n and 1 or 0))
    if n then assert(selected==n) end
end
expect(3) -- Most buildings, nearest tie.
component.inside=bases[1];expect(1) -- Inside takes priority.
component.inside=nil;bases[2].count=60;expect(2) -- Fresh building count.
bases[2].count=50;bases[3].z=2000;expect(2) -- Full 3D distance.
bases[3].z=0;bases[3].group=8;expect(2) -- Foreign base ignored.
component.inside=bases[3];expect(nil) -- Foreign current base never redirected.
component.inside=nil;bases[3].group=7
service.overlay=true;expect(nil);service.overlay=false
service.fade=true;expect(nil);service.fade=false
missing=true;expect(nil);missing=false
mismatch=true;expect(nil);mismatch=false
foreign=true;expect(nil);foreign=false
bases[3].owner=0;expect(nil);bases[3].owner=nil
bases[3].count=-1;expect(2);bases[3].count=50
bases[3].invalid=true;expect(2);bases[3].invalid=false
local saved=guild.BaseCampIds;guild.BaseCampIds=array({});expect(nil);guild.BaseCampIds=saved
component.fail=true;expect(nil);component.fail=false;expect(3)
fail=true;expect(nil);fail=false;expect(3)
queueFail=true;expect(nil);queueFail=false;expect(3)
defer=true;local before=calls;key();key();assert(calls==before)
IN_GAME_THREAD=true;queue();IN_GAME_THREAD=false;assert(calls==before+1);defer=false
expect(3)
assert(#logs>0)

local function checkHotkey(config, expected, warning)
    package.loaded.config = nil
    package.preload.config = function()
        if config == 'load-error' then error('simulated config error') end
        return config
    end
    local before = #logs
    dofile(PROJECT_ROOT .. '/mod/Scripts/main.lua')
    assert(registered == expected)
    if warning then assert(logs[before+1]:find(warning, 1, true)) end
    expect(3)
end
checkHotkey({Hotkey='J'}, Key.J)
checkHotkey({Hotkey=' f6 '}, Key.F6)
checkHotkey({Hotkey='UNKNOWN'}, Key.K, 'invalid Hotkey')
checkHotkey({Hotkey=''}, Key.K, 'invalid Hotkey')
checkHotkey({Hotkey=75}, Key.K, 'config missing or invalid')
checkHotkey({}, Key.K, 'config missing or invalid')
checkHotkey(false, Key.K, 'config missing or invalid')
checkHotkey('load-error', Key.K, 'config missing or invalid')
package.loaded.config = nil
package.preload.config = nil
