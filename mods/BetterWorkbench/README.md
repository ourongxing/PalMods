# BetterWorkbench（更好的工作台）

提供同工作台配方穿透、材料列表滚动和即时分解。

## 使用

- **配方穿透**：优先使用已有中间材料，将缺口递归展开为当前工作台已解锁配方的原料。例：需要铁锭 ×3，已有铁锭 ×1，其余两份可用本工作台的矿石制作，则投入已有铁锭及所需矿石。
- **材料滚动**：详情区默认显示五行，更多材料可用滚轮查看。
- **即时分解**：点击详情右上角已有成品数量，切换生产／分解；使用数量选择器确定批数并确认。按整批消耗成品，原配方材料全额返还玩家背包。

制作最多 256 批。匹配的原生容器支持 64 种投入，成品槽固定为索引 5；其他容器使用五槽策略。
制作工时沿用根配方，展开中间件的额外工时和多人任务定义同步尚未实现。
即时分解支持单人／房主本机；库存扣除、手柄操作、退款和保存恢复仍需完成游戏验收。

安装到 UE4SS 的 `Mods/BetterWorkbench/`，包含 `Scripts/` 和 `dlls/main.dll`；`mods.txt` 启用 `BetterWorkbench : 1`。
配置位于安装目录的 `Scripts/config.lua`：

| 配置 | 用途 |
| --- | --- |
| `Enabled` | Lua 入口 |
| `PreferredRecipes` | 同物品多配方时指定配方 ID |
| `MaterialScroll.Enabled`、`VisibleRows` | 材料滚动与可视行数 |
| `MaterialScroll.RowHeight` | 原生行高尚不可用时的后备高度 |
| `Disassembly.Enabled` | 即时分解 |
| `Diagnostics.Enabled` | 诊断日志，默认关闭 |

更新 DLL 前保存并退出游戏，更新后重启。`Jobs/*.bwj` 保存未完成任务的不可变定义，须与存档一起保留。
部署脚本迁移旧目录中的 Jobs，冲突时停止迁移；旧 `SRJ_` 任务继续读取 `.srj`。

## 开发

在仓库根目录执行；环境与 SDK 配置见 [根 README](../../README.md)。

```powershell
python tools/build.py BetterWorkbench
python mods/BetterWorkbench/tests/run.py
.\mods/BetterWorkbench/tools/deploy.ps1
```

构建生成 `.build/BetterWorkbench/native/Release/BetterWorkbenchNative.dll` 和导入审核报告。
候选打包使用 `tools/package_candidate.ps1`，要求 `validation.json` 与源码和 DLL 一致。

| 文档 | 内容 |
| --- | --- |
| [原生实现](docs/NATIVE.md) | 制作、扩容、扣料与任务恢复 |
| [接入契约](docs/INTEGRATION.md) | 成本、工作台范围、库存与实机验收 |
| [调用位置](docs/NATIVE_JOB_VIEW.md) | 材料视图、数量表及原生 ABI |
| [即时分解](docs/DISASSEMBLY.md) | UI、库存、容量和接口 |
| [性能](docs/PERFORMANCE.md) | 请求内数据复用与基准结果 |
