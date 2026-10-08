# Updraft Elevator（上升气流）

在建筑气流范围内起跳，按小／中／大型设置升空高度，默认 8／16／32 米。
建筑直径分别为 2／4／6 米。建成后透明，拆除瞄准时显示底座定位。
直接走入不触发升空；重叠区域只取最高一档，保留水平移动。

第 9 级古代科技「上升气流」消耗 1 点，解锁三种尺寸。
每个建筑需要 10 帕鲁矿碎片、30 石头、3 古代文明部件。
保留原建筑 ID、科技 ID 和 UE 资源路径，避免改名影响已有存档。

## 配置与安装

当前安装包为 `outputs/UpdraftElevator-v9.zip`。依赖 UE4SS 与 PalSchema。
将包内 `Mods/UpdraftElevator` 和 `Mods/PalSchema/mods/UpdraftElevator` 放到 UE4SS 的 Mods 目录。
更新前保存并完全退出游戏。

编辑已安装的 `UpdraftElevator/Scripts/config.lua`，分别设置 `Small`、`Medium`、`Large` 的高度（米），
范围 0.1～1000，允许小数，重启游戏生效。安装脚本保留已有配置。

## 源码

| 路径 | 用途 |
| --- | --- |
| `work/native_cost_only.lua` | 科技判定与起跳升力，两个事件钩子，无后台轮询 |
| `work/wind_config.lua` | 默认高度配置 |
| `work/wind_variants.json` | 三尺寸资源生成参数 |
| `work/wind_data.py`、`work/data/building_template.json` | 当前建筑与科技元数据 |
| `work/WindNative/Source` | UE 5.1.1 蓝图生成与编辑器检查 |
| `work/WindNative/Config` | 构建所需的游戏碰撞配置 |
| `work/wind-art`、`work/generate_wind_art.py` | 六张源贴图及确定性生成器 |
| `work/data/schema` | PalSchema 校验快照及 MIT 许可 |

`Source/Pal` 是编辑器 API 声明替身；发布包只包含生成的资源与 Lua。
`/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot` 是游戏内特效引用，编辑器占位资源不打包。

## 构建与校验

从仓库根目录安装 `requirements-dev.txt`，运行 `python tools/test.py`。
现有离线回归覆盖科技隔离、起跳条件、重力／重叠处理、配置边界、读一次配置和建筑数据。

资源构建需要 UE 5.1.1、VS 2022 和 repak。统一路径配置见根目录 [README](../README.md)。
首次或移动工程后先编译编辑器模块，再生成蓝图、Cook、打包：

```powershell
& "$env:UNREAL_ROOT/Engine/Build/BatchFiles/Build.bat" PalEditor Win64 Development "$(Resolve-Path UpdraftElevator/work/WindNative/Pal.uproject)" -WaitMutex
python UpdraftElevator/work/run_native_build.py
python UpdraftElevator/work/cook_native.py
python UpdraftElevator/work/package_native.py --stage-only
```

脚本可从任意目录调用，资产路径自动定位到本项目。
六张源贴图已纳入仓库；需要重新生成时运行 `python UpdraftElevator/work/generate_wind_art.py`。
`--stage-only` 只生成安装包；省略该参数会在游戏退出时备份并安装到配置的游戏目录。

用户已确认 v7 游戏效果；v8 配置回归通过，v9 精简文案。整理后的资源生成与元数据保持原参数。
离线测试不替代游戏内高度、存档和联机验证。
旧地毯实现、早期脚手架与完整交接历史已移到根目录 `.local/retired/UpdraftElevator`，只保留本地。
