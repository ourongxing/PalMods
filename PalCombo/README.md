# PalCombo

此目录是 PalCombo 的源码仓库。游戏中生效的 Mod 位于 `G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\PalCombo`；游戏设置请修改生效目录中的 `config.ini`。

## 产品要求

组合技必须按槽位 1 → 槽位 2 的顺序连续选招，槽位 3 只能在两轮组合之间填空。启动条件和参数含义如下：

1. 槽位 1 已就绪，且槽位 2 已就绪或剩余冷却不超过 `EarlyStartSeconds`：释放槽位 1。
2. 选出槽位 1 后，锁定下一招为槽位 2；槽位 2 尚未就绪时不会插入槽位 3。
3. 组合开始前，如果不满足第 1 条，槽位 3 已就绪则用它填空；不会单独释放槽位 2。

选出槽位 2 后，本轮组合结束，状态重置。下一轮仍须满足第 1 条才能启动；因此槽位 1 的冷却尚未结束时不会再次选它。

`EarlyStartSeconds` 的目的是利用槽位 1 的释放时间覆盖槽位 2 尚未结束的冷却，尽早启动组合，避免无效等待。编辑 [config.ini](config.ini) 中的该参数，单位为秒，允许 0～30，默认 `3.0`。如果 1 → 2 无法衔接，用户根据槽位 1 的释放时长调小它；设为 `0` 时，只有槽位 2 已冷却结束才会启动槽位 1。修改后重启游戏生效。

产品不要求在参数设置过大时额外等待槽位 2，也不要求拦截游戏的原生备用动作。Mod 不会取消正在执行的动作。

骑乘时的手动技能不由 PalCombo 控制。下马恢复自动战斗时，组合从槽位 1 重新判定；骑乘和自动战斗的技能冷却分别以游戏当时提供的数据为准。

## 开发

原生源码位于 `NativeSrc/MyCPPMods/PalComboFillerNative`。首次构建前从仓库根目录执行 `./tools/setup_ue4ss.ps1`，将共享 UE4SS 固定到 `2281fa311e417b1dfddedbcd49972d764fddb244`。然后执行 `./PalCombo/NativeSrc/build_mods_shipping.bat`。编译产物和依赖源码不会提交到本仓库。将构建出的 DLL 复制到游戏目录的 `dlls/main.dll`，并同时部署 `Scripts/main.lua` 和 `config.ini`。

纯选择逻辑的测试源码位于 `NativeSrc/MyCPPMods/PalComboFillerNative/tests/rotation_test.cpp`。
