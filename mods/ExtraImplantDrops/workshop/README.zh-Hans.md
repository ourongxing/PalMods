# 植入体掉落

1.0.0 · ourongxing

帕鲁死亡或被肢解时，有概率额外掉落与其词条对应的植入体。

## 功能与使用

- 支持 28 种植入体，每种符合条件的词条独立判定掉落。
- 默认掉落概率为 50%，基础数量为 1。
- 数量受游戏掉落加成与世界设置影响。
- 保留原有材料掉落。

## 安装

1. 订阅并启用前置 Mod：UE4SSExperimentalPW。
2. 在游戏的 Mod 管理中启用本 Mod。
3. 完全退出游戏，再重新启动。

## 配置

在 Palworld 安装目录中编辑 `Mods/NativeMods/UE4SS/Mods/ExtraImplantDrops/config.ini`，保存后完全退出并重启游戏。

- `[Harvest]` 中的 `DropChance=0.5`：掉落概率，范围 0～1；0 为不掉落，1 为必定通过概率判定。
- `[Implants]`：按词条分别设置植入体掉落，1 开启、0 关闭。开启后仍需通过概率判定。

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
