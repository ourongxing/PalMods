# 气流资源构建

环境要求：UE 5.1.1、VS 2022、repak 和 `requirements-dev.txt`，路径设置见 [根 README](../../../README.md)。
完整构建使用 `python tools/build.py UpdraftElevator`；单步诊断顺序如下：

```powershell
python mods/UpdraftElevator/tools/build_native.py
python mods/UpdraftElevator/tools/run_native_build.py
python mods/UpdraftElevator/tools/cook_native.py
python mods/UpdraftElevator/tools/package_native.py --stage-only
```

编辑器编译使用 UE 自带 .NET 6。蓝图生成读取 `data/variants.json` 和六张 `assets/T_Wind*.png`，创建 `native/Content/`。
`Source/Pal` 提供游戏 API 声明，特效 `/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot` 使用编辑器占位资源；二者仅用于生成和 Cook。

UE 缓存位于 `native/`；日志、备份、PAK 输入和暂存位于 `.build/UpdraftElevator/`，发布包位于 `dist/UpdraftElevator/`。
打包脚本的 `--stage-only` 生成安装包；省略时备份并安装，执行前退出游戏。

`tools/wind_data.py` 从 `data/building_template.json` 生成建筑和科技元数据。
源贴图可通过 `tools/generate_wind_art.py` 重生成，需 numpy、Pillow 和 `C:/Windows/Fonts/bahnschrift.ttf`。
Schema 来源及许可见 [data/schema](../data/schema/README.md)。
