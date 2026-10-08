# RainbowWildGlow

UE4SS Lua Mod，版本 **0.9.9-fishing-lilac-worldtree**。

含彩色词条（Rank = 4）的帕鲁显示淡紫色光晕，默认仅野外显示。带世界树词条（WorldTree_* / Rank 5）或稀有词条（Rare）的帕鲁整只排除，包括混合词条。

## 设置

`mod/Scripts/config.lua` 中的 `OnlyWildPals` 默认为 `true`，仅野外帕鲁显示。设为 `false` 后，符合上述词条条件的己方和据点帕鲁也会显示。
词条品质条件和 1000 毫秒刷新间隔固定在代码中。通过 `PalCharacter:LocalInitialized` 后置钩子发现帕鲁，并在启动及每 5 秒全量补扫；每秒检查已跟踪帕鲁的光晕状态。仅靠初始化钩子的无扫描试验未通过用户游戏内验证，因此恢复扫描兜底。5 秒为当前补显延迟与扫描频率的选择，并非引擎要求。

## 实现

使用原生 `WorldTreeAura`（47）蓝图生成 `NS_AwakeningAura`，由蓝图完成尺寸初始化、网格挂载与缩放。
随后清空蓝图的 `Effect` 引用，由 Mod 独立管理生成的 NiagaraComponent，避免原生显示规则停用光晕。
颜色参数使用 `FName("User.Color")`，以钓鱼紫色粒子的原生 RGB `(12.6998, 0, 100)` 为底色，归一化后混入 35% 白色，得到淡紫色 `(0.4325487, 0.35, 1, 1)`。
保留世界树光晕的形状、材质、运动和亮度范围，不修改共享游戏资源。
不再满足显示条件或死亡时销毁 Mod 的粒子并清理包装实例。

## 安装

退出游戏后在仓库根目录执行：

```powershell
python mods/RainbowWildGlow/tests/run.py
powershell -ExecutionPolicy Bypass -File mods/RainbowWildGlow/install.ps1
```

安装位置：`Mods/NativeMods/UE4SS/Mods/RainbowWildGlow`。当前实现只需 Lua。
安装脚本备份已有 Mod、校验安装哈希，并迁移停用旧版本的 DLL/Pak。
更新时保留已安装的 `Scripts/config.lua`，默认配置只在首次安装时复制；如需调整显示范围，请修改游戏目录中的配置。

## 验证

0.9.4 的光晕外观已由用户确认可用。0.9.9 回归覆盖 Lua 表/TArray 两种词条数组、初始化钩子遗漏时的扫描补偿、仅野外显示开关、严格 Rank 4 筛选、世界树/稀有及混合词条排除、词条变化清理、延迟生成、粒子接管、激活恢复、组件重建、捕获、死亡。模拟测试不能证明游戏内初始化钩子的覆盖率。
旧 native/Pak 源码和实验、崩溃记录保存在 `.build/RainbowWildGlow/`，不参与当前实现。
