Close Range Burst Skills / 近身范围技能施放距离
=========================================

作用
----
将下列围绕施术者展开、距离太远时难以充分命中的技能，在
DT_WazaDataTable 中的 MaxRange 统一设为 50 游戏单位（约 0.5 米）：

- 熔岩爆发 / Volcanic Rain：Eruption（原版 2000）
- 岩爆 / Rockburst：Tremor（原版 1200）
- 毒雨 / Poison Shower：BubbleShower（原版 1000）

所有技能由 raw/close_range_burst_skills.json 统一管理。
WazaType 的 Values 列表指定生效的技能；添加或删除内部技能 ID
即可调整名单。MaxRange 指定它们共同使用的最大施放距离。
若需给不同技能设置不同距离，应拆成多个 JSON 文件。

本模组只修改 AI 的最大施放距离，不修改技能威力、冷却、
最小距离、攻击范围、弹道或伤害判定。距离缩短也不保证 AI
一定主动靠近敌人；实际效果需要在游戏中测试。

安装与卸载
----------
依赖 PalSchema 和与当前 Palworld 版本匹配的 RE-UE4SS。
将 CloseRangeBurstSkills 整个文件夹放在 PalSchema/mods/ 下。
修改后完全重启游戏以重新加载数据。卸载时退出游戏，
删除 PalSchema/mods/CloseRangeBurstSkills 文件夹。

若其他模组也修改同一技能的 MaxRange，最终值取决于加载顺序。
