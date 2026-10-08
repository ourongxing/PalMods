# 气流资源构建

需要 UE 5.1.1、VS 2022、repak 和仓库的 `requirements-dev.txt`。
路径由共享工具管理，环境变量见根目录 [README](../../../README.md)。

在仓库根目录依次运行：

```powershell
python mods/UpdraftElevator/tools/build_native.py
python mods/UpdraftElevator/tools/run_native_build.py
python mods/UpdraftElevator/tools/cook_native.py
python mods/UpdraftElevator/tools/package_native.py --stage-only
```

`build_native.py` 使用 UE 自带的 .NET 6，避免受本机系统 .NET 版本影响。
蓝图生成读取 `data/variants.json` 和 `assets/`。
`Source/Pal` 是编辑器使用的游戏 API 声明替身，其 DLL 不安装到游戏。
游戏特效引用 `/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot` 的编辑器占位资源不打包。

UE 自身的编译与 Cook 缓存按引擎约定位于 `native/` 的忽略目录。
其余日志、备份、PAK 输入和打包暂存分别位于根目录 `.build/UpdraftElevator/`。
发布包输出到根目录 `dist/UpdraftElevator/`。

`--stage-only` 只生成安装包；省略该参数会在游戏退出时备份并安装到配置的游戏目录。
安装升级保留玩家已有高度配置。

`tools/wind_data.py` 从 `data/building_template.json` 生成当前建筑与科技元数据；
`data/schema` 保存 PalSchema 校验快照与 MIT 许可。
可通过 `python mods/UpdraftElevator/tools/generate_wind_art.py` 重生成六张源贴图。
