local timer,pending,onCreated
local running,elapsed=true,3601
local statusCalls,scans,writes=0,0,0
local nextAddress=0
local function object(t) t=t or {};nextAddress=nextAddress+1;local address=nextAddress;t.GetAddress=function()return address end;t.IsValid=function()return true end;return t end
local view=object({SetRemainSeconds=function(self,n)self.elapsed=n;writes=writes+1 end})
local hud=object({bAlreadySetup=false,ConcreteModel=object(),WBP_PalWork_Expedition=view,IsVisible=function()return true end})
function BetterExpeditionNativeIsActive()return true end
function BetterExpeditionNativeStatus()statusCalls=statusCalls+1;return running,elapsed end
function FindAllOf(name)assert(name=='WBP_ExpeditionStatusWorldHUD_C');scans=scans+1;return {hud}end
function LoopAsync(ms,callback)assert(ms==1000);timer=callback end
function NotifyOnNewObject(_,callback)onCreated=callback end
function ExecuteInGameThread(callback)assert(not pending);pending=callback end
function RegisterHook()error('per-frame hooks forbidden')end
local function flush()local f=pending;pending=nil;f()end

dofile(MAIN)
timer();for i=1,100 do timer()end
assert(scans==0,'object access outside game thread')
flush();assert(scans==1 and statusCalls==0 and writes==0)
hud.bAlreadySetup=true
timer();flush();assert(view.elapsed==3601 and writes==1)
running=false;timer();flush();assert(writes==1)
hud.IsVisible=function()return false end
running=true;timer();flush();assert(statusCalls==2 and writes==1)
hud.IsVisible=function()error('stale')end
timer();flush()
hud.IsVisible=function()return true end
elapsed=3602;timer();flush();assert(view.elapsed==3602 and writes==2)
assert(scans==1,'repeated global object scans')
hud.IsValid=function()return false end
timer();flush();assert(writes==2)
local replacement=object({bAlreadySetup=true,ConcreteModel=object(),WBP_PalWork_Expedition=view,IsVisible=function()return true end})
onCreated(replacement);onCreated(replacement)
timer();flush();assert(writes==3,'created widget duplicated or missed')
print('PASS: one-second HUD, game-thread access, bounded queue, hidden/stale widgets')
