# PalCombo

玩家帕鲁按技能槽 1 → 2 连招，槽 3 在两轮组合之间填空。

1. 槽 1 就绪，且槽 2 就绪或剩余冷却不超过 `EarlyStartSeconds` 时，启动组合。
2. 槽 1 实际进入冷却后等待槽 2，期间槽 3 不插入。
3. 槽 2 进入冷却后重置组合；下一轮尚不能启动时使用就绪的槽 3。

骑乘时使用手动技能；下马恢复自动战斗后从槽 1 重新判定。目标变化会重置待选状态。

## 配置与安装

配置位于游戏 UE4SS `Mods/PalCombo/config.ini`。
`EarlyStartSeconds` 单位为秒，范围 0～30，默认 3.0；连招无法衔接时调小，设为 0 时等待槽 2 完全就绪。
修改配置或 DLL 后重启游戏。

构建后将 DLL 放入 `Mods/PalCombo/dlls/main.dll`，并复制 `mod/` 内容到 `Mods/PalCombo/`。

## 开发

在仓库根目录执行，环境见 [根 README](../../README.md)：

```powershell
python tools/build.py PalCombo
python tools/test.py
```

[原生工程](docs/NATIVE.md) · [实现与调试](docs/DEVELOPMENT.md) · [调用链](docs/DECOMPILATION.md)
