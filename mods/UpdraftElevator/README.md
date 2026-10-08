# Updraft Elevator（上升气流）

在建筑气流范围内起跳，按小／中／大型设置升空高度，默认 8／16／32 米。
建筑直径分别为 2／4／6 米。建成后透明，拆除瞄准时显示底座；重叠区域只取最高一档。

第 9 级古代科技消耗 1 点，解锁三种尺寸。
每个建筑需要 10 帕鲁矿碎片、30 石头、3 古代文明部件。
建筑 ID、科技 ID 和 UE 资源路径保持不变。

依赖 UE4SS 与 PalSchema。发布包位于根目录 `dist/UpdraftElevator/`，
包内 `Mods/UpdraftElevator` 与 `Mods/PalSchema/mods/UpdraftElevator` 放入 UE4SS 的 Mods 目录。
更新前保存并完全退出游戏。

高度配置在已安装的 `UpdraftElevator/Scripts/config.lua`，分别设置 `Small`、`Medium`、`Large`，
单位米，范围 0.1～1000，允许小数，重启生效。安装器保留已有配置。

源码使用与其他 mod 相同的布局：`mod/Scripts/`、`native/`、`tests/`、`tools/`、`docs/`。
建筑模板、尺寸参数、Schema 位于 `data/`，六张源贴图位于 `assets/`。
在仓库根目录运行 `python tools/test.py` 执行离线回归。
资源构建与打包命令见 [原生说明](docs/NATIVE.md)。

用户已确认 v7 游戏效果，v8 配置回归通过，v9 精简文案。
离线测试不代替游戏内高度、存档和联机验证。
