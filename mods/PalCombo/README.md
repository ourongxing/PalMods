# PalCombo

此目录是 PalCombo 的源码目录。游戏中生效的 Mod 位于 `G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\PalCombo`；游戏设置请修改生效目录中的 `config.ini`。

## 产品要求

组合技必须按槽位 1 → 槽位 2 的顺序连续选招，槽位 3 只能在两轮组合之间填空。启动条件和参数含义如下：

1. 槽位 1 已就绪，且槽位 2 已就绪或剩余冷却不超过 `EarlyStartSeconds`：释放槽位 1。
2. 选出槽位 1 后，锁定下一招为槽位 2；槽位 2 尚未就绪时不会插入槽位 3。
3. 组合开始前，如果不满足第 1 条，槽位 3 已就绪则用它填空；不会单独释放槽位 2。

选出槽位 2 后，本轮组合结束，状态重置。下一轮仍须满足第 1 条才能启动；因此槽位 1 的冷却尚未结束时不会再次选它。

`EarlyStartSeconds` 的目的是利用槽位 1 的释放时间覆盖槽位 2 尚未结束的冷却，尽早启动组合，避免无效等待。编辑 [config.ini](mod/config.ini) 中的该参数，单位为秒，允许 0～30，默认 `3.0`。如果 1 → 2 无法衔接，用户根据槽位 1 的释放时长调小它；设为 `0` 时，只有槽位 2 已冷却结束才会启动槽位 1。修改后重启游戏生效。

产品不要求在参数设置过大时额外等待槽位 2，也不要求拦截游戏的原生备用动作。Mod 不会取消正在执行的动作。

骑乘时的手动技能不由 PalCombo 控制。下马恢复自动战斗时，组合从槽位 1 重新判定；骑乘和自动战斗的技能冷却分别以游戏当时提供的数据为准。

## 开发

Lua 入口为 `mod/Scripts/main.lua`，默认配置为 `mod/config.ini`，C++ 源码为 `native/src/`。
纯连招回归在 `tests/native/rotation_test.cpp`，通过仓库根目录 `python tools/test.py` 运行。

```powershell
./tools/setup_ue4ss.ps1
./mods/PalCombo/tools/build_native.bat
```

从仓库根目录执行，编译结果在 `.build/PalCombo/Game__Shipping__Win64/bin/PalComboFillerNative.dll`。
将 DLL 安装到游戏 `PalCombo/dlls/main.dll`，同时安装 `mod/` 的内容。
开发和反编译证据见 [原生说明](docs/NATIVE.md)、[开发说明](docs/DEVELOPMENT.md)、[调用链](docs/DECOMPILATION.md)。
