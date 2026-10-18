local Quota=require('BetterArena.Quota')
local I18n=require('BetterArena.I18n')
local Feedback=require('BetterArena.Feedback')
local M={}
local BASE='/Game/Pal/Blueprint/UI/UserInterface/Arena/'
local BUTTON=BASE..'WBP_Arena_TopMenuButton.WBP_Arena_TopMenuButton_C'
local EVENT='BndEvt__WBP_Arena_TopMenuButton_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature'
local CHALLENGE='BndEvt__WBP_Arena_TopMenu_WBP_Arena_TopMenuButton_Solo_K2Node_ComponentBoundEvent_0_OnArenaButtonClicked__DelegateSignature'
local ENTRY=BASE..'WBP_Arena_SoloEntry.WBP_Arena_SoloEntry_C'
local sessions,actions,pending,errors={},{},{},{}
local function valid(o) return o and o:IsValid() end
local function key(o) return o:GetFullName() end
local function unwrap(o) local ok,v=pcall(function() return o:get() end);return ok and v or o end
local function findWidget(menu,name)
 local direct=menu[name]
 if valid(direct) then return direct end
 local panel=StaticFindObject('/Script/UMG.PanelWidget')
 local visited=0
 local function walk(widget)
  if not valid(widget) then return end
  visited=visited+1;assert(visited<=512,'arena widget tree exceeds limit')
  if widget:GetFName():ToString()==name then return widget end
  if widget:IsA(panel) then
   for i=0,widget:GetChildrenCount()-1 do
    local found=walk(widget:GetChildAt(i));if found then return found end
   end
  end
 end
 return walk(menu.WidgetTree.RootWidget)
end
local function report(err)
 err=tostring(err)
 if not errors[err] then print('[BetterArena] '..err..'\n');errors[err]=true end
end
local function message(err,t)
 err=tostring(err)
 if err:find('host only',1,true) then return t.host end
 if err:find('inventory full',1,true) then return t.full end
 if err:find('daily limit',1,true) then return t.empty end
 if err:find('unresolved previous',1,true) then return t.pending end
 if err:find('challenge not cleared',1,true) then return t.notCleared end
 return t.failed
end
function M.start(config,service)
 local clickHook,entryHook=false,false
 local function refresh(s)
  local t=I18n.current()
  local ok,c=pcall(service.preview,service,s.menu)
  -- Disabling the whole native widget turns its UI materials into white
  -- rectangles. Keep it enabled and reject unavailable actions in the handler.
  local ready=ok and c.challengeRank and not c.pending
  local title=ok and ('%s · %d/%d'):format(t.action,c.remaining,Quota.limit(config,c.playerRank)) or t.action
  if s.kind=='top' then
   s.button.Text_ButtonName:SetText(FText(title))
   s.button:SetIsEnabled(true)
   s.button:SetLock(not ready)
   if s.button.IsFocused and valid(s.menu.Text_MenuGuide) then
    local detail=not ok and message(c,t) or c.pending and t.pending or not c.challengeRank and t.locked or c.remaining==0 and t.empty or t.choose
    s.menu.Text_MenuGuide:SetText(FText(detail))
   end
  else
   for _,entry in ipairs(s.cards) do
    local cleared=ok and c.cleared[entry.rank]
    entry.card:SetIsEnabled(true)
    entry.card:SetRenderOpacity(ready and cleared and 1 or 0.45)
    if valid(entry.card.BP_PalTextBlock_Reward) then
     local label=not cleared and t.notCleared or c.remaining==0 and t.empty or title
     entry.card.BP_PalTextBlock_Reward:SetText(FText(label))
    end
   end
  end
 end
 local function release(id,s)
  Feedback.clear(s)
  if s.kind=='top' then
   if valid(s.button) then actions[key(s.button)]=nil;s.button:RemoveFromParent() end
   for _,position in ipairs(s.originals) do
    if valid(position.widget) then position.widget.Slot:SetPosition(position.position) end
   end
  else
   for _,entry in ipairs(s.cards) do
    if valid(entry.input) then
     entry.input.OnButtonBaseClicked:Clear()
     for _,binding in ipairs(entry.bindings) do
      if valid(binding.Object) then entry.input.OnButtonBaseClicked:Add(binding.Object,FName(binding.name)) end
     end
    end
    if valid(entry.card) then
     entry.card:SetIsEnabled(entry.enabled)
     entry.card:SetRenderOpacity(entry.opacity)
     if entry.label and valid(entry.card.BP_PalTextBlock_Reward) then entry.card.BP_PalTextBlock_Reward:SetText(FText(entry.label)) end
    end
    if valid(entry.proxy) then actions[key(entry.proxy)]=nil;entry.proxy:RemoveFromParent() end
   end
  end
  sessions[id]=nil
 end
 local function create(menu)
  local class=StaticFindObject(BUTTON)
  if not valid(class) then LoadAsset(BASE..'WBP_Arena_TopMenuButton');class=StaticFindObject(BUTTON) end
  assert(valid(class),'arena button class unavailable')
  local button=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(menu,class,menu:GetOwningPlayer())
  assert(valid(button),'arena button unavailable')
  return button
 end
 local function attachEntry(menu)
  local owner=key(menu:GetOwningPlayer())
  local request=pending[owner]
  if not request or os.time()>request.expires or sessions[key(menu)] then return end
  pending[owner]=nil
  local s={kind='entry',menu=menu,cards={}}
  sessions[key(menu)]=s
  local ok,err=pcall(function()
   local entries=menu.EntryButtons
   assert(entries:GetArrayNum()==7,'arena challenge cards unavailable')
   entries:ForEach(function(_,parameter)
    local card=unwrap(parameter)
    local rank=card.ArenaRank+1
    assert(rank>=1 and rank<=7,'invalid challenge card rank')
    local input=card.WBP_PalInvisibleButton
    assert(valid(input),'challenge input unavailable')
    local proxy=create(menu)
    menu.WidgetTree.RootWidget:AddChildToCanvas(proxy)
    proxy:SetVisibility(1)
    local bindings={}
    for _,binding in ipairs(input.OnButtonBaseClicked:GetBindings() or {}) do
     bindings[#bindings+1]={Object=binding.Object,name=binding.FunctionName:ToString()}
    end
    assert(#bindings>0,'original challenge click binding unavailable')
    local entry={card=card,rank=rank,input=input,proxy=proxy,bindings=bindings,enabled=card:GetIsEnabled(),opacity=card:GetRenderOpacity()}
    if valid(card.BP_PalTextBlock_Reward) then entry.label=card.BP_PalTextBlock_Reward:GetText():ToString() end
    s.cards[#s.cards+1]=entry
    actions[key(proxy)]={session=s,rank=rank}
    -- Replace only this sweep page's click route. Hover/reward previews remain native.
    input.OnButtonBaseClicked:Clear()
    input.OnButtonBaseClicked:Add(proxy,FName(EVENT))
   end)
   refresh(s)
  end)
  if not ok then release(key(menu),s);error(err) end
  print('[BetterArena] Sweep difficulty page ready; normal Challenge is unchanged\n')
 end
 local function installHooks()
  if not clickHook and valid(StaticFindObject(BUTTON..':'..EVENT)) then
   RegisterHook(BUTTON..':'..EVENT,function(context)
    local action=actions[key(context:get())]
    if not action then return end
    local s=action.session
    if s.queued then return end
    s.queued=true
    ExecuteInGameThread(function()
     local ok,err=pcall(function()
      assert(valid(s.menu) and s.menu:IsVisible(),'arena menu closed')
      if s.kind=='top' then
       local c=service:preview(s.menu)
       if not c.challengeRank or c.pending then refresh(s);return end
       local owner=key(s.menu:GetOwningPlayer())
       pending[owner]={expires=os.time()+10}
       local opened,failure=pcall(function() s.menu[CHALLENGE](s.menu) end)
       if not opened then pending[owner]=nil;error(failure) end
      else
       local c=service:preview(s.menu)
       if not c.cleared[action.rank] or c.pending or c.remaining<=0 then refresh(s);return end
       local result=service:claim(s.menu,action.rank)
       refresh(s)
       -- Presentation failure must never retry or invalidate an awarded claim.
       local shown,failure=pcall(Feedback.show,s,result)
       if not shown then report(failure) end
      end
     end)
     s.queued=false
     if not ok then
      report(err)
      local t=I18n.current()
      if s.kind=='entry' then
       for _,entry in ipairs(s.cards) do
        if entry.rank==action.rank and valid(entry.card.BP_PalTextBlock_Reward) then entry.card.BP_PalTextBlock_Reward:SetText(FText(message(err,t))) end
       end
      elseif valid(s.menu.Text_MenuGuide) then s.menu.Text_MenuGuide:SetText(FText(message(err,t))) end
      s.errorUntil=os.time()+3
     end
    end)
   end)
   clickHook=true
  end
  if not entryHook and valid(StaticFindObject(ENTRY..':Setup')) then
   RegisterHook(ENTRY..':Setup',function(context)
    local ok,err=pcall(attachEntry,context:get());if not ok then report(err) end
   end)
   entryHook=true
  end
 end
 local function attachTop(menu)
  if sessions[key(menu)] then return end
  local canvas=findWidget(menu,'Canvas_MenuButton')
  assert(valid(canvas),'arena menu canvas unavailable')
  local s={kind='top',menu=menu,originals={}}
  local ok,err=pcall(function()
   s.button=create(menu)
   local slot=canvas:AddChildToCanvas(s.button)
   slot:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
   slot:SetAlignment({X=0.5,Y=0.5});slot:SetPosition({X=-190,Y=0});slot:SetSize({X=400,Y=400})
   s.button:Setup(0);s.button:SetLock(false);s.button:SetRenderOpacity(1);s.button:SetVisibility(0)
   for _,spec in ipairs({{menu.WBP_Arena_TopMenuButton_Solo,-570},{menu.WBP_Arena_TopMenuButton_PvP,190},{menu.WBP_Arena_TopMenuButton_Spectate,570}}) do
    local widget=spec[1];assert(valid(widget),'original arena button unavailable')
    local p=widget.Slot:GetPosition()
    s.originals[#s.originals+1]={widget=widget,position={X=p.X,Y=p.Y}}
    widget.Slot:SetPosition({X=spec[2],Y=0})
   end
   sessions[key(menu)]=s;actions[key(s.button)]={session=s}
   installHooks();refresh(s)
  end)
  if not ok then release(key(menu),s);error(err) end
 end
 local queued=false
 LoopAsync(250,function()
  if queued then return end
  queued=true
  ExecuteInGameThread(function()
   local ok,err=pcall(function()
    installHooks()
    for owner,request in pairs(pending) do if os.time()>request.expires then pending[owner]=nil end end
    for id,s in pairs(sessions) do
     if not valid(s.menu) or not s.menu:IsVisible() then release(id,s)
     else
      Feedback.tick(s,os.time())
      if not s.errorUntil or os.time()>=s.errorUntil then refresh(s) end
     end
    end
    for _,menu in ipairs(FindAllOf('WBP_Arena_TopMenu_C') or {}) do
     if valid(menu) and menu:IsVisible() and not key(menu):find('Default__',1,true) then attachTop(menu) end
    end
    for _,menu in ipairs(FindAllOf('WBP_Arena_SoloEntry_C') or {}) do
     if valid(menu) and menu:IsVisible() and not key(menu):find('Default__',1,true) then attachEntry(menu) end
    end
   end)
   queued=false
   if not ok then report(err) end
  end)
 end)
end
return M
