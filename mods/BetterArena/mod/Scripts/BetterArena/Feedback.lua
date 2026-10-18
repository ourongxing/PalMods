local I18n=require('BetterArena.I18n')
local M={}
local PATH='/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonReward'
local SOUND='/Game/Pal/Sound/Events/SE/UI/Common/AKE_CommonReward'
local function valid(o) return o and o:IsValid() end
local function itemName(menu,id)
 local ok,name=pcall(function()
  local out={}
  StaticFindObject('/Script/Pal.Default__PalUIUtility'):GetItemName(menu,FName(id),out)
  return out.outName:ToString()
 end)
 return ok and name~='' and name or id
end
function M.clear(session)
 if valid(session.rewardBanner) then session.rewardBanner:RemoveFromParent() end
 session.rewardBanner=nil;session.rewardClose=nil;session.rewardRemove=nil
end
function M.tick(session,now)
 local banner=session.rewardBanner
 if not valid(banner) then return end
 if session.rewardRemove and now>=session.rewardRemove then M.clear(session)
 elseif session.rewardClose and now>=session.rewardClose then
  banner:PlayAnimation(banner.Anm_Close,0,1,0,1,false)
  session.rewardClose=nil;session.rewardRemove=now+1
 end
end
function M.show(session,result)
 local receipt=assert(result.receipt,'reward receipt unavailable')
 local ids,items={},{}
 for id,count in pairs(receipt.items) do if count>0 then ids[#ids+1]=id end end
 table.sort(ids)
 for _,id in ipairs(ids) do items[#items+1]=('%s × %d'):format(itemName(session.menu,id),receipt.items[id]) end
 local banner=session.rewardBanner
 if not valid(banner) then
  local class=StaticFindObject(PATH..'.WBP_CommonReward_C')
  if not valid(class) then LoadAsset(PATH);class=StaticFindObject(PATH..'.WBP_CommonReward_C') end
  banner=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(session.menu,class,session.menu:GetOwningPlayer())
  assert(valid(banner),'reward banner unavailable')
  session.rewardBanner=banner
  banner:AddToViewport(100)
 end
 -- Own this presentation separately from the global reward queue, so it is
 -- visible above the arena menu without hiding cards or taking input focus.
 banner:StopAllAnimations()
 local text=table.concat(items,'    ')
 -- Do not marshal a partial PalUICommonRewardDisplayData through UE4SS.
 -- Only scalar widget setters are needed for this independently owned banner.
 banner:ChangeColor(0)
 banner.Text_Title:SetText(FText(I18n.current().receipt:format(receipt.points)))
 banner.BP_PalRichTextBlock_C_99:SetText(FText(text))
 banner.Icon:SetVisibility(1)
 banner.SizeBox_AddTextTitle:SetVisibility(1)
 banner.VerticalBox_Add:SetVisibility(1)
 banner:SetVisibility(4) -- HitTestInvisible, including children.
 banner:PlayAnimation(banner.Anm_Open,0,1,0,1,false)
 session.rewardClose=os.time()+4;session.rewardRemove=nil
 local sound=StaticFindObject(SOUND..'.AKE_CommonReward')
 if not valid(sound) then LoadAsset(SOUND);sound=StaticFindObject(SOUND..'.AKE_CommonReward') end
 if valid(sound) then
  local u=StaticFindObject('/Script/Pal.Default__PalUtility')
  u:GetHUDService(session.menu:GetOwningPlayer()):PlayAkSound(sound)
 end
end
return M
