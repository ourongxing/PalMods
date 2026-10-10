# Better Storage / 更好的收纳

基地内沿用原版快速收纳的候选和灰显；野外将主基地 ID 传入原版基地候选接口，使用与基地内相同的筛选和数量规则。保留原版排除列表、确认窗口和服务器转移规则。箱子中没有同类物品时，不会将新物品放入空槽。原版分类、权限及容量检查继续生效。

保留野外选择公会建筑数量最多的主据点（同数量选最近）、普通物品 99,999 堆叠上限，以及同优先级帕鲁搬运优先叠放。

野外直接调用原版 CollectQuickStackTargetItemInfos，传入主基地与本地玩家 ID。基地查询限定于背包蓝图执行范围，类名校验按弱引用缓存。

构建：`python mods/BetterStorage/tools/build.py`。

产物：`dist/BetterStorage/BetterStorage-0.1.0.zip`。

退出游戏后，将 ZIP 中的 BetterStorage 文件夹放入 UE4SS/Mods。先禁用 BetterBulkStorage，两个 mod 不能同时启用。

联机的堆叠上限与搬运修改需要主机或服务器加载 DLL；野外收纳沿用服务器验证，联机尚未验收。

2026-10-10：用户确认本机野外收纳及灰显符合主基地规则。
