# 上升气流

1.1.0 · ourongxing

建造上升气流，在气流范围内按跳跃键，借助原版气流的起跳动画升空。

## 功能与使用

- 小型：默认升空高度 8 米，范围直径 2 米。
- 中型：默认升空高度 16 米，范围直径 4 米。
- 大型：默认升空高度 32 米，范围直径 6 米。
- 范围重叠时采用最高一档的升空高度。

在第 9 级古代科技中花费 1 个古代科技点，一次解锁三种尺寸。每座建筑需要 10 帕鲁矿碎片、30 石头和 3 古代文明部件。

在建造菜单的“基础设施／上升气流”分类中放置。建筑完成后透明；拆除时进入拆除模式，瞄准气流下部的底座。

## 安装

1. 订阅并启用前置 Mod：UE4SSExperimentalPW, PalSchema。
2. 在游戏的 Mod 管理中启用本 Mod。
3. 完全退出游戏，再重新启动。

## 配置

在 Palworld 安装目录中编辑 `Mods/NativeMods/UE4SS/Mods/UpdraftElevator/Scripts/config.lua`，保存后完全退出并重启游戏。

`Small`、`Medium`、`Large` 分别设置三种尺寸的升空高度，单位为米，默认值为 8、16、32。支持 0.1～1000 和小数，无效数值使用默认值。

建筑和科技文字支持简体中文、繁体中文、日语和英语，其他语言回退为英语。切换语言后重启游戏。

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
