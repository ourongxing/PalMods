# 爆发技能贴脸释放

1.1.0 · ourongxing

让帕鲁靠近目标后，再使用熔岩爆发、岩爆和毒雨。

## 功能与使用

这三个技能需要接近目标至约 0.5 米内才会由帕鲁自动施放。技能威力、冷却、攻击范围和伤害判定沿用原版。

## 安装

1. 订阅并启用前置 Mod：UE4SSExperimentalPW, PalSchema。
2. 在游戏的 Mod 管理中启用本 Mod。
3. 完全退出游戏，再重新启动。

## 配置

在 Palworld 安装目录中编辑 `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json`，保存后完全退出并重启游戏。

`MaxRange` 设置自动施放的最大距离，默认 50 个游戏单位，约 0.5 米。

## 使用须知

与其他修改这三个技能施放距离的 Mod 同时启用时，结果取决于加载顺序。

## 问题反馈

请到 GitHub Issues 报告问题：https://github.com/ourongxing/PalMods/issues

没有 UE4SS 日志，我无法定位并修复 Bug。

请提供以下信息，方便定位：

- Mod 名称、游戏与 Mod 版本、游戏语言。
- 单人游戏、联机房主、加入他人房间或专用服务器。
- 复现步骤、预期与实际表现，以及相关截图和已启用的其他 Mod。
- 出现问题后的完整 `UE4SS.log` 文件，请作为附件上传。

在 Steam 中右键 Palworld → 管理 → 浏览本地文件，然后打开 `Mods\NativeMods\UE4SS\UE4SS.log`。
例如，游戏安装在 G 盘时，完整路径为：
`G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\UE4SS.log`

盘符和 Steam 库目录以你的安装位置为准。请在再次启动游戏前复制日志，避免本次问题的记录被覆盖。

## 开源

本 Mod 以 GPL-3.0 协议开源。
https://github.com/ourongxing/PalMods
