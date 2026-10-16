# 随处打开终端

1.0.0 · ourongxing

按 K 随处打开原版帕鲁终端，在野外和地下城也能查看、整理和调整帕鲁。

## 功能与使用

- 在自己公会的据点内，打开当前据点的终端。
- 在野外或地下城，打开公会中建筑物最多的据点终端；建筑数相同时选择距离玩家最近的据点，每次按键重新选择。
- 公会需要已有据点，且对应终端可用。
- 位于其他公会据点内时不会打开终端。
- 使用原版终端界面；其他菜单打开、画面切换或玩家尚未就绪时，按键不生效。

## 安装

1. 订阅并启用前置 Mod：UE4SSExperimentalPW。
2. 在游戏的 Mod 管理中启用本 Mod。
3. 完全退出游戏，再重新启动。

## 配置

在 Palworld 安装目录中编辑 `Mods/NativeMods/UE4SS/Mods/AnywherePalBox/Scripts/config.lua`，保存后完全退出并重启游戏。

`Hotkey = "K"` 设置快捷键，可改为 `"J"`、`"F6"` 等单个按键，不区分大小写。配置缺失或无效时使用 K。

## 使用须知

已在单人游戏中测试，包括地下城。多人游戏尚未验证。

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
