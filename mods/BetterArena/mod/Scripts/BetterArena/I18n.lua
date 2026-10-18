local M={}
local words={
 en={loading='Preparing rewards',action='Sweep',notCleared='Not cleared',choose='Choose a cleared difficulty to claim its rewards instantly',
  locked='Clear an Arena challenge to unlock sweeps',
  pending='Previous claim interrupted · available next game day',receipt='Sweep complete · +%d RP',
  host='Sweeps require single player or the host',full='Make room in your inventory',
  failed='Sweep unavailable',empty='No sweeps left today'},
 ['zh-Hans']={loading='奖励准备中',action='扫荡',notCleared='尚未通关',choose='选择已通关的难度，立即获得奖励和积分',
  locked='首次通关竞技场挑战后解锁扫荡',
  pending='上次领取中断 · 下一游戏日恢复',receipt='扫荡完成 · 排名积分 +%d RP',host='仅限单机或房主使用扫荡',
  full='请先腾出背包空间',failed='暂时无法扫荡',empty='今日扫荡次数已用完'},
 ['zh-Hant']={loading='獎勵準備中',action='掃蕩',notCleared='尚未通關',choose='選擇已通關的難度，立即獲得獎勵與積分',
  locked='首次通關競技場挑戰後解鎖掃蕩',
  pending='上次領取中斷 · 下一遊戲日恢復',receipt='掃蕩完成 · 排名積分 +%d RP',host='僅限單機或房主使用掃蕩',
  full='請先騰出背包空間',failed='暫時無法掃蕩',empty='今日掃蕩次數已用完'},
 ja={loading='報酬を準備中',action='掃討',notCleared='未クリア',choose='クリア済みの難易度を選ぶと報酬とランクポイントを即時獲得',
  locked='アリーナの初回クリアで掃討を解放',
  pending='前回の受け取りが中断 · 翌ゲーム日に再開',receipt='掃討完了 · ランクポイント +%d RP',host='ソロまたはホストのみ利用できます',
  full='所持品に空きを作ってください',failed='掃討を利用できません',empty='本日の掃討回数を使い切りました'},
}
function M.current()
 local ok,language=pcall(function()
  local library=StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary')
  local success,tag=pcall(function() return library:GetCurrentCulture() end)
  if not success then tag=library:GetCurrentLanguage() end
  return type(tag)=='string' and tag or tag:ToString()
 end)
 language=ok and language:lower():gsub('_','-') or ''
 if language:find('zh',1,true)==1 then
  return words[(language:find('hant',1,true) or language:find('tw',1,true) or language:find('hk',1,true) or language:find('mo',1,true)) and 'zh-Hant' or 'zh-Hans']
 end
 return words[language:match('^ja') and 'ja' or 'en']
end
return M
