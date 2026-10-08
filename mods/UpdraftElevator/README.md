# Updraft Elevator（上升气流）

在建筑气流范围内起跳升空。小／中／大型默认高度为 8／16／32 米，直径为 2／4／6 米。
建成后透明，拆除瞄准时显示底座；重叠区域取最高一档。

第 9 级古代科技消耗 1 点，解锁三种尺寸。每个建筑需要 10 帕鲁矿碎片、30 石头、3 古代文明部件。

## 安装与配置

依赖 UE4SS 和 PalSchema。退出游戏，将发布包的 `Mods/` 内容合并到 UE4SS Mods 目录。
配置位于安装目录 `UpdraftElevator/Scripts/config.lua`：`Small`、`Medium`、`Large` 分别设置升空高度，
单位米，范围 0.1～1000，允许小数，重启生效。安装器保留已有配置。
旧版迁移步骤见包内 [README](mod/README.txt)。

建筑与科技名称、说明支持简体中文、繁体中文、日语和英语，由 PalSchema 跟随游戏语言加载；
切换语言后重启游戏。语言表位于 `mod/translations/`，其他语言回退英文。
工坊四语使用说明和介绍位于 `workshop/README.*.md` 与 `workshop/listing.json`。

## 开发

在仓库根目录执行：

```powershell
python tools/build.py UpdraftElevator
python tools/test.py
```

建筑模板和尺寸参数位于 `data/`，源贴图位于 `assets/`。
资源生成与单步构建见 [原生说明](docs/NATIVE.md)。
