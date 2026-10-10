# PalIconInfo（终端星级与潜力显示）

在帕鲁终端的头像格子上显示居中的浓缩星级，以及高潜力圆点。

## 原始来源

- 原始 Mod：[PalIconInfo - PalBox Utilities](https://www.nexusmods.com/palworld/mods/5281?tab=description)
- 原作者：ikusamaou。
- 本目录基于原作者的 Lua Mod 修改，并非从零开发。原始下载地址也可用于查看更新、截图和完整功能说明。

原版支持显示等级、性别、图鉴编号、浓缩星级、帕鲁之魂强化等级、信赖等级、被动词条和个体值，并提供快捷翻页、队伍预设交换等功能。个体值默认要求佩戴能力眼镜。

## 当前修改

- 显示浓缩星级和高潜力圆点；其他额外信息关闭。
- 头像右侧从上到下对应生命、攻击、防御潜力：90～99 显示绿色圆点，100 显示黄色圆点，低于 90 留空，不显示具体数值。
- 圆点沿用原版 Mod 内置的潜力绿色、黄色配色，默认无需佩戴能力眼镜。
- 根据实际的 1～4 星计算整行宽度，使星级水平居中；0 星不显示。
- 终端格子复用、星数变化时更新位置，保持原有纵向位置。
- F1／右摇杆按下仅保留一个星级与潜力圆点显示状态。
- `scripts/main.lua` 不再加载快捷翻页模块；原版队伍预设交换仍保留。

## 安装与配置

需要与游戏版本匹配的 Palworld 专用 UE4SS。原作者要求 Nexus 下载版使用独立安装的 UE4SS，不与创意工坊版混用；本机已部署到现有 UE4SS 的 Mod 目录，游戏内兼容性和实际画面尚未验证。

将 `scripts/` 和 `enabled.txt` 放入 UE4SS 的 `Mods/PalIconInfo/`，在 `Mods/mods.txt` 中启用 `PalIconInfo : 1`。

将本目录的 `user-config/PalIconInfoConfig.lua` 复制到 UE4SS 的 `Mods/shared/PalIconInfo/PalIconInfoConfig.lua`。`user-config/` 是仓库保存的配置副本，运行时不会直接读取它；不要修改 `scripts/DefaultConfig_DO_NOT_EDIT/` 内的默认配置。

本机安装目录：

```text
G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\PalIconInfo
```

本机实际配置：

```text
G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\shared\PalIconInfo\PalIconInfoConfig.lua
```

修改脚本和运行时配置后重启游戏。Lua 语法及 0～4 星、格子复用、星数变化的模拟检查已通过；潜力圆点另已通过 0／89／90／99／100 边界值、三项独立显示、格子复用及旧配置数值显示兼容检查。游戏内显示效果仍需验证。
