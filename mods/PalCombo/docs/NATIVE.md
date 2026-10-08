# PalCombo 原生构建

项目入口 `native/CMakeLists.txt`，源码 `native/src/`，离线回归 `tests/native/`。
共享 UE4SS 依赖位于仓库根目录 `.tools/RE-UE4SS`，固定版本见根目录说明。

在仓库根目录执行 `./mods/PalCombo/tools/build_native.bat`，输出位于 `.build/PalCombo/`。
只生成构建工程可运行 `./mods/PalCombo/tools/configure_native.bat`。
两个入口都接受附加 CMake 参数，例如 `-T version=14.44.35207`。

实现细节见 [DEVELOPMENT.md](DEVELOPMENT.md)，反编译证据见 [DECOMPILATION.md](DECOMPILATION.md)。
