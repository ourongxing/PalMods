Close Range Burst Skills / 近身范围技能施放距离

将以下技能的 AI 最大施放距离 MaxRange 设为 50 游戏单位（约 0.5 米）：
- 熔岩爆发 / Volcanic Rain：Eruption，原版 2000。
- 岩爆 / Rockburst：Tremor，原版 1200。
- 毒雨 / Poison Shower：BubbleShower，原版 1000。

配置：raw/close_range_burst_skills.json。
WazaType.Values 设置技能 ID 名单，MaxRange 设置共同距离；不同距离拆成多个 JSON 文件。
技能威力、冷却、攻击范围和伤害判定使用原版数据，AI 是否主动靠近需游戏验证。

依赖：PalSchema、与游戏版本匹配的 RE-UE4SS。
安装：将 CloseRangeBurstSkills 文件夹放入 UE4SS 的 Mods/PalSchema/mods/。
修改后完全重启游戏；卸载时退出游戏并删除该文件夹。
其他 mod 修改相同技能的 MaxRange 时，最终值取决于加载顺序。
